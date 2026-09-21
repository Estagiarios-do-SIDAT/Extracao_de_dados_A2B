USE mdb;
SET NOCOUNT ON;

-- Limpa versão anterior da tabela temporária, caso a sessão tenha executado uma versão antiga.
IF OBJECT_ID('tempdb..#InicioContagem') IS NOT NULL DROP TABLE #InicioContagem;


--------------------------------------------------------------------------------
-- Consulta FAIA - A2B/Protect4
-- Contagem a partir da entrada no grupo A2B e captura por log de status 'Em andamento'.
-- A captura depende do GRUPO (chamado na posse do A2B), não de membros do grupo (grpmem).
--
-- Critério de escopo do fornecedor (a CATEGORIA NÃO é usada em nenhuma etapa):
--   1) Grupo atual do chamado = A2B/Protect4 (group_id = @FornecedorGrupo); E
--   2) O chamado deve ENCERRAR no grupo A2B/Protect4, ou seja:
--        - nasceu no grupo e nunca sofreu transferência de grupo; ou
--        - a ÚLTIMA transferência de grupo, até o fechamento, foi uma entrada
--          em 'Fornecedores - A2B' (não houve saída do grupo depois).
--
-- Tipos de chamado considerados (call_req.type):
--   I = Incidente
--   R = Solicitação
--   P = Problema
-- O tipo NÃO participa do JOIN de SLA: a #SLA_FAIA_P4 da Protect4 é indexada apenas por
-- severidade (P1-P5), então Problema usa a mesma meta de início do Incidente e
-- da Solicitação de mesma severidade. Mesmo critério já vigente no FARC Protect4.
--
-- Status finais considerados:
--   Resolvido, concluído
--   Não resolvido, fechado
--   Cancelado
--
-- Para Power BI, mantenha @MostrarDiagnostico = 0.
--
-- NOMES EXCLUSIVOS DE TEMPORARIA (correcao do Msg 207)
--   Uma tabela # vive ate o fim da SESSAO, e o SQL Server COMPILA o lote inteiro
--   antes de executa-lo. Logo, o "IF OBJECT_ID(...) DROP TABLE" abaixo so roda na
--   execucao: se outra consulta ja deixou na sessao uma # de mesmo nome e esquema
--   DIFERENTE, a compilacao liga esta consulta a tabela velha e acusa
--   "Msg 207 - Invalid column name".
--
--   Duas temporarias desta consulta tinham esquema incompativel com as homonimas
--   do FAIA Decision (decision/queries/consulta_faia.sql) e por isso receberam
--   nome exclusivo:
--     #SLA_FAIA_P4         (o #SLA do Decision nao tem meta_resolucao_seg nem
--                           tipo_resolucao)
--     #TransfGrupo_FAIA_P4 (o #TransfGrupo do Decision usa
--                           primeira/ultima_entrada_FORNECEDOR_epoch, nao _a2b_)
--
--   Com isso a consulta roda sozinha em qualquer ordem, sem limpeza previa de
--   sessao e sem script auxiliar. As demais temporarias mantiveram o nome porque
--   sao compativeis (subconjunto) e nao provocam Msg 207.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- [PARAMETROS FACILMENTE ALTERAVEIS]
--------------------------------------------------------------------------------
DECLARE @FornecedorNome  nvarchar(100) = N'A2B/Protect4';
DECLARE @FornecedorGrupo varbinary(16) = 0xCE4FDD26D5053545BF4A11332BB07485;

-- Período informado em horário do Brasil, GMT-3.
DECLARE @InicioBrasil datetime2(0) = '2026-03-24 00:00:00';
DECLARE @FimBrasil    datetime2(0) = '2026-04-23 23:59:59';

-- Conversão para UTC/GMT usado pelo SDM em pdmtime/epoch.
DECLARE @HorasBrasilParaUTC int = 3;
DECLARE @Epoch datetime2(0) = '1970-01-01 00:00:00';
DECLARE @FromUTC datetime2(0) = DATEADD(HOUR, @HorasBrasilParaUTC, @InicioBrasil);
DECLARE @ToUTC   datetime2(0) = DATEADD(HOUR, @HorasBrasilParaUTC, @FimBrasil);
DECLARE @FromEpoch int = DATEDIFF(SECOND, @Epoch, @FromUTC);
DECLARE @ToEpoch   int = DATEDIFF(SECOND, @Epoch, @ToUTC);

-- 1 = mostra result sets extras de conferência. Use 0 no Power BI.
DECLARE @MostrarDiagnostico bit = 0;

-- Janela comercial usada nos SLAs do tipo COMERCIAL.
DECLARE @HoraInicioComercial int = 8;
DECLARE @HoraFimComercial    int = 20;

--------------------------------------------------------------------------------
-- [SLA por severidade]
-- Conforme SLA por Severidade.png:
-- P1: início 15 min corridos; resolução 12h corrida
-- P2: início 60 min corridos; resolução 24h corrida
-- P3/P4: início 240 min comerciais; resolução 36h comercial
-- P5: início 720 min comerciais; resolução 360h comercial
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#SLA_FAIA_P4') IS NOT NULL DROP TABLE #SLA_FAIA_P4;
CREATE TABLE #SLA_FAIA_P4 (
    prioridade            tinyint     NOT NULL PRIMARY KEY,
    meta_inicio_seg       int         NOT NULL,
    tipo_inicio           varchar(10) NOT NULL, -- CORRIDA | COMERCIAL
    meta_resolucao_seg    int         NOT NULL,
    tipo_resolucao        varchar(10) NOT NULL  -- CORRIDA | COMERCIAL
);

INSERT INTO #SLA_FAIA_P4(prioridade, meta_inicio_seg, tipo_inicio, meta_resolucao_seg, tipo_resolucao)
VALUES
    (1,  15 * 60,       'CORRIDA',    12 * 60 * 60,       'CORRIDA'),
    (2,  60 * 60,       'CORRIDA',    24 * 60 * 60,       'CORRIDA'),
    (3, 240 * 60,       'COMERCIAL',  36 * 60 * 60,       'COMERCIAL'),
    (4, 240 * 60,       'COMERCIAL',  36 * 60 * 60,       'COMERCIAL'),
    (5, 720 * 60,       'COMERCIAL', 360 * 60 * 60,       'COMERCIAL');

--------------------------------------------------------------------------------
-- [FERIADOS E PONTOS FACULTATIVOS]
--
-- Regra de cadastro:
--   - Feriados fixos: MM-DD, porque se repetem todos os anos.
--   - Feriados móveis/diferenciados e pontos facultativos: YYYY-MM-DD, porque
--     valem apenas no ano cadastrado.
--
-- Regra de contagem:
--   - CORRIDA: conta 24h, sem desconto de feriado/facultativo.
--   - COMERCIAL: conta somente segunda a sexta, 08:00-20:00, zerando
--     os dias listados como feriado/facultativo.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#FeriadosFixos') IS NOT NULL DROP TABLE #FeriadosFixos;
CREATE TABLE #FeriadosFixos (
    mes_dia   char(5)        NOT NULL PRIMARY KEY, -- MM-DD
    descricao nvarchar(200)  NOT NULL
);

INSERT INTO #FeriadosFixos (mes_dia, descricao)
VALUES
    ('01-01', N'Confraternização Universal'),
    ('04-21', N'Tiradentes'),
    ('05-01', N'Dia Mundial do Trabalho'),
    ('09-07', N'Independência do Brasil'),
    ('10-12', N'Nossa Senhora Aparecida'),
    ('11-02', N'Finados'),
    ('11-15', N'Proclamação da República'),
    ('11-20', N'Dia Nacional de Zumbi e da Consciência Negra'),
    ('12-25', N'Natal');

IF OBJECT_ID('tempdb..#FeriadosPorData') IS NOT NULL DROP TABLE #FeriadosPorData;
CREATE TABLE #FeriadosPorData (
    data      date           NOT NULL PRIMARY KEY,
    descricao nvarchar(200)  NOT NULL
);

-- Pontos facultativos de 2025 no TCU.
-- Fonte: Portaria-TCU n. 10/2025 e alteracoes n. 157/2025 e n. 176/2025
-- (Boletim do TCU; autenticidade em www.tcu.gov.br/autenticidade, codigos
-- 77411949, 79190602 e 79506777). 27/10, 21/11 e 26/12 incluidos em 2026-09-18.
-- 24/12/2025 e 31/12/2025 NAO estao aqui (existem no painel e no FARC individual);
-- a diferenca e anterior e esta registrada na documentacao.
INSERT INTO #FeriadosPorData (data, descricao)
VALUES
    ('2025-10-27', N'Dia do Servidor Público federal - ponto facultativo'),               -- Portaria-TCU n. 10/2025, inciso XIII.
    ('2025-11-21', N'Ponto facultativo - sexta-feira após Consciência Negra'),          -- Portaria-TCU n. 157/2025.
    ('2025-12-26', N'Ponto facultativo - sexta-feira após o Natal');                     -- Portaria-TCU n. 176/2025.

-- Feriados móveis/diferenciados de 2026.
INSERT INTO #FeriadosPorData (data, descricao)
VALUES
    ('2026-04-03', N'Paixão de Cristo'),
    ('2026-04-05', N'Páscoa');

-- Pontos facultativos de 2026 no TCU.
-- Comentários indicam o feriado/evento ao qual o ponto facultativo está ligado.
INSERT INTO #FeriadosPorData (data, descricao)
VALUES
    ('2026-01-02', N'Ponto facultativo - emenda após Confraternização Universal'),       -- Ligado ao feriado de Confraternização Universal, no dia anterior: 2026-01-01.
    ('2026-02-16', N'Carnaval - ponto facultativo'),                                     -- Ligado ao Carnaval.
    ('2026-02-17', N'Carnaval - ponto facultativo'),                                     -- Ligado ao Carnaval.
    ('2026-02-18', N'Quarta-Feira de Cinzas - ponto facultativo'),                       -- Ligado ao Carnaval, no dia seguinte à terça-feira de Carnaval.
    ('2026-04-02', N'Ponto facultativo - véspera da Paixão de Cristo'),                  -- Ligado ao feriado de Paixão de Cristo, no dia seguinte: 2026-04-03.
    ('2026-04-20', N'Ponto facultativo - emenda antes de Tiradentes'),                   -- Ligado ao feriado de Tiradentes, no dia seguinte: 2026-04-21.
    ('2026-06-04', N'Corpus Christi - ponto facultativo'),                               -- Ligado a Corpus Christi.
    ('2026-06-05', N'Ponto facultativo - emenda após Corpus Christi'),                   -- Ligado a Corpus Christi, no dia anterior: 2026-06-04.
    ('2026-06-29', N'Ponto facultativo - jogo da Seleção Brasileira na Copa do Mundo FIFA 2026'), -- Portaria-TCU n. 93/2026 (codigo 80587034), incluido em 2026-09-18.
    ('2026-10-28', N'Dia do Servidor Público federal - ponto facultativo'),              -- Ligado ao Dia do Servidor Público federal.
    ('2026-12-24', N'Ponto facultativo - véspera do Natal'),                             -- Ligado ao feriado de Natal, no dia seguinte: 2026-12-25.
    ('2026-12-31', N'Ponto facultativo - véspera da Confraternização Universal');         -- Ligado ao feriado de Confraternização Universal, no dia seguinte: 2027-01-01.

-- Pontos facultativos de 2027:
-- Não cadastrar nada por enquanto. Quando houver definição oficial, inserir aqui
-- com data completa no formato YYYY-MM-DD.

--------------------------------------------------------------------------------
-- [0] (Removido) Snapshot de membros do grupo do fornecedor
--
-- A apuração NÃO usa mais a associação de membros ao grupo (dbo.grpmem).
-- Motivo: grpmem reflete a composição ATUAL do grupo. Como um membro pode sair
-- ou trocar de grupo no futuro, depender disso mudaria o resultado de chamados
-- antigos e exigiria um histórico/snapshot de grpmem que o SDM não mantém.
--
-- A captura passa a depender do GRUPO, não do membro: vale o que ocorreu
-- enquanto o chamado estava na posse do grupo A2B/Protect4, ou seja, a partir
-- da entrada no grupo (etapa [6]) e dentro do escopo que encerra no grupo
-- (etapas [4] e [5]).
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- [1] Pré-filtro por período de fechamento: reduz I/O antes das demais regras
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#CRPeriodo') IS NOT NULL DROP TABLE #CRPeriodo;

SELECT
    r.id,
    r.persid,
    r.ref_num,
    r.[type],
    r.priority,
    r.status,
    r.category,
    r.group_id,
    r.assignee,
    r.log_agent,
    r.customer,
    r.open_date,
    r.close_date,
    r.resolve_date,
    r.time_spent_sum,
    CONVERT(nvarchar(4000), r.summary) AS summary_txt
INTO #CRPeriodo
FROM dbo.call_req AS r
WHERE r.close_date IS NOT NULL
  AND r.close_date >= @FromEpoch
  AND r.close_date <= @ToEpoch;

CREATE UNIQUE CLUSTERED INDEX IX_CRPeriodo_id ON #CRPeriodo(id);
CREATE INDEX IX_CRPeriodo_persid ON #CRPeriodo(persid);
CREATE INDEX IX_CRPeriodo_close ON #CRPeriodo(close_date);
CREATE INDEX IX_CRPeriodo_category ON #CRPeriodo(category);
CREATE INDEX IX_CRPeriodo_group ON #CRPeriodo(group_id);
CREATE INDEX IX_CRPeriodo_assignee ON #CRPeriodo(assignee);

--------------------------------------------------------------------------------
-- [2] Base enriquecida: status, categoria (apenas informativa), contatos e severidade real
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Base') IS NOT NULL DROP TABLE #Base;

SELECT
    r.id,
    r.persid,
    r.ref_num,
    r.[type],
    r.priority,
    TRY_CONVERT(tinyint, pri.sym) AS prioridade_por_sym,
    CASE
        WHEN TRY_CONVERT(tinyint, pri.sym) BETWEEN 1 AND 5 THEN TRY_CONVERT(tinyint, pri.sym)
        WHEN r.priority BETWEEN 1 AND 5 THEN CONVERT(tinyint, r.priority)
        ELSE NULL
    END AS prioridade_nivel,
    r.status,
    r.category,
    r.group_id,
    r.assignee,
    r.log_agent,
    r.customer,
    r.open_date,
    r.close_date,
    r.resolve_date,
    r.time_spent_sum,
    r.summary_txt,
    st.sym AS status_sym,
    pc.sym AS categoria_sym,

    LTRIM(RTRIM(
        CASE
            WHEN (ISNULL(la.first_name, N'') <> N'' OR ISNULL(la.last_name, N'') <> N'')
                THEN CONCAT(ISNULL(la.first_name, N''), N' ', ISNULL(la.last_name, N''))
            WHEN ISNULL(la.userid, N'') <> N'' THEN la.userid
            ELSE N'N/A'
        END
    )) AS responsavel_abertura,

    LTRIM(RTRIM(
        CASE
            WHEN (ISNULL(asg.first_name, N'') <> N'' OR ISNULL(asg.last_name, N'') <> N'')
                THEN CONCAT(ISNULL(asg.first_name, N''), N' ', ISNULL(asg.last_name, N''))
            WHEN ISNULL(asg.userid, N'') <> N'' THEN asg.userid
            ELSE N'N/A'
        END
    )) AS responsavel_atendimento
INTO #Base
FROM #CRPeriodo AS r
LEFT JOIN dbo.cr_stat AS st
    ON st.code = r.status
LEFT JOIN dbo.prob_ctg AS pc
    ON pc.persid = r.category
LEFT JOIN dbo.pri AS pri
    ON pri.enum = r.priority
LEFT JOIN dbo.ca_contact AS la
    ON la.contact_uuid = r.log_agent
LEFT JOIN dbo.ca_contact AS asg
    ON asg.contact_uuid = r.assignee;

CREATE UNIQUE CLUSTERED INDEX IX_Base_id ON #Base(id);
CREATE INDEX IX_Base_persid ON #Base(persid);
CREATE INDEX IX_Base_assignee ON #Base(assignee);
CREATE INDEX IX_Base_group ON #Base(group_id);

--------------------------------------------------------------------------------
-- [3] Candidatos do fornecedor pelo GRUPO atual
--
-- Critério único de fornecedor: grupo atual do chamado = A2B/Protect4.
-- A categoria NÃO é mais usada como filtro em nenhuma etapa.
-- A confirmação de que o chamado ENCERROU no grupo é feita na etapa [5].
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Candidatos') IS NOT NULL DROP TABLE #Candidatos;

SELECT b.*
INTO #Candidatos
FROM #Base AS b
WHERE b.group_id = @FornecedorGrupo
  -- Tipos apurados: I = Incidente, R = Solicitação, P = Problema.
  -- 'P' foi incluído para alinhar o escopo do FAIA ao do FARC Protect4, que já
  -- usava IN ('I','R','P'). Sem hardcode por SDM: o critério é o tipo real do
  -- chamado em call_req.type. Nenhuma etapa posterior filtra por tipo, e a #SLA_FAIA_P4
  -- é indexada só por severidade, então Problema recebe meta/contagem normais.
  AND b.[type] IN ('I', 'R', 'P')
  AND b.status IN (
        'CL',        -- Resolvido, concluido
        'CLD',       -- Fechado, Solucao Implantada
        'CLUNRSLV',  -- Nao resolvido, fechado
        'CNCL',      -- Cancelada
        'ATGR',      -- Cancelado
        'END',       -- Encerrado
        'PC',        -- Fechado, solucao nao implantada
        'RE',        -- Resolvido, Solucao Definida
        'VARES'      -- Resolvido pelo VA
      );

CREATE UNIQUE CLUSTERED INDEX IX_Candidatos_id ON #Candidatos(id);
CREATE INDEX IX_Candidatos_persid ON #Candidatos(persid);

--------------------------------------------------------------------------------
-- [4] Histórico de transferência de GRUPO dos candidatos
--
-- Para cada chamado candidato (já no grupo A2B/Protect4, tipo I/R/P e em status
-- final), levantamos as transferências de GRUPO ocorridas ATÉ o fechamento:
--   - qtd_transf_grupo          : quantas transferências de grupo houve
--   - ultima_transf_grupo_epoch : data/hora da ÚLTIMA transferência de grupo
--   - primeira_entrada_a2b_epoch: PRIMEIRA vez que entrou em 'Fornecedores - A2B'
--   - ultima_entrada_a2b_epoch  : ÚLTIMA vez que entrou em 'Fornecedores - A2B'
--
-- Com isso decidimos, sem usar categoria, se o chamado ENCERROU no grupo A2B:
-- basta a ÚLTIMA transferência de grupo de todas ter sido justamente uma entrada
-- em 'Fornecedores - A2B' (etapa [5]). A 'primeira_entrada_a2b_epoch' continua
-- servindo de marco para o início da contagem (etapa [6]).
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#TransfGrupo_FAIA_P4') IS NOT NULL DROP TABLE #TransfGrupo_FAIA_P4;

SELECT
    b.id,
    COUNT(*)                                                       AS qtd_transf_grupo,
    MAX(al.system_time)                                            AS ultima_transf_grupo_epoch,
    MIN(CASE WHEN flag.eh_entrada_a2b = 1 THEN al.system_time END) AS primeira_entrada_a2b_epoch,
    MAX(CASE WHEN flag.eh_entrada_a2b = 1 THEN al.system_time END) AS ultima_entrada_a2b_epoch
INTO #TransfGrupo_FAIA_P4
FROM #Candidatos AS b
JOIN dbo.act_log AS al
    ON al.call_req_id = b.persid
CROSS APPLY (
    SELECT texto_log =
        CONVERT(nvarchar(max), ISNULL(al.description, N'')) + N' ' +
        CONVERT(nvarchar(max), ISNULL(al.action_desc,  N''))
) AS txt
CROSS APPLY (
    SELECT eh_entrada_a2b =
        CASE
            WHEN txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%Fornecedores - A2B%'
             AND (
                   txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%para ''Fornecedores - A2B''%'
                OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%para Fornecedores - A2B%'
                OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%to ''Fornecedores - A2B''%'
                OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%to Fornecedores - A2B%'
                 )
            THEN 1 ELSE 0
        END
) AS flag
WHERE al.system_time IS NOT NULL
  AND al.type = 'TR'
  AND (b.open_date  IS NULL OR al.system_time >= b.open_date)
  AND (b.close_date IS NULL OR al.system_time <= b.close_date)
  AND (
        txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%Transferir Grupo%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%Transfer Group%'
  )
GROUP BY b.id;

CREATE UNIQUE CLUSTERED INDEX IX_TransfGrupo_id ON #TransfGrupo_FAIA_P4(id);

--------------------------------------------------------------------------------
-- [5] Escopo final: chamados que ENCERRARAM no grupo A2B/Protect4
--
-- Além de estar no grupo A2B/Protect4 (já garantido em #Candidatos), o chamado
-- precisa TERMINAR no grupo A2B. Isso vale quando:
--   (a) o chamado nasceu no grupo e nunca sofreu transferência de grupo; ou
--   (b) a ÚLTIMA transferência de grupo de todas, até o fechamento, foi uma
--       entrada em 'Fornecedores - A2B' (não houve saída do grupo depois).
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#EscopoIds') IS NOT NULL DROP TABLE #EscopoIds;
CREATE TABLE #EscopoIds (
    id int NOT NULL PRIMARY KEY,
    FonteFornecedor nvarchar(120) NOT NULL
);

INSERT INTO #EscopoIds(id, FonteFornecedor)
SELECT
    c.id,
    CASE
        WHEN tg.id IS NULL
            THEN N'Nasceu e permaneceu no grupo A2B/Protect4 (sem transferência de grupo)'
        ELSE N'Encerrou no grupo A2B/Protect4 (última transferência de grupo foi para Fornecedores - A2B)'
    END AS FonteFornecedor
FROM #Candidatos AS c
LEFT JOIN #TransfGrupo_FAIA_P4 AS tg
    ON tg.id = c.id
WHERE
    -- (a) nasceu no grupo e nunca foi transferido; group_id = A2B já garantido em #Candidatos
    tg.id IS NULL
    -- (b) a última transferência de grupo de todas foi uma entrada em Fornecedores - A2B
    OR (
        tg.ultima_entrada_a2b_epoch IS NOT NULL
        AND tg.ultima_entrada_a2b_epoch = tg.ultima_transf_grupo_epoch
    );

IF @MostrarDiagnostico = 1
BEGIN
    -- Total no escopo e como cada chamado terminou no grupo A2B/Protect4
    SELECT
        COUNT(*)                                                              AS TotalNoEscopoFornecedor,
        SUM(CASE WHEN e.FonteFornecedor LIKE N'Nasceu%'   THEN 1 ELSE 0 END)  AS QtdNasceuNoGrupo,
        SUM(CASE WHEN e.FonteFornecedor LIKE N'Encerrou%' THEN 1 ELSE 0 END)  AS QtdEntrouEEncerrouNoGrupo
    FROM #EscopoIds AS e;

    -- Distribuição por status final dentro do escopo
    SELECT
        ISNULL(b.status_sym, N'N/A') AS Status,
        COUNT(*) AS Qtd
    FROM #Base AS b
    JOIN #EscopoIds AS e
        ON e.id = b.id
    GROUP BY ISNULL(b.status_sym, N'N/A')
    ORDER BY Qtd DESC, Status;

    -- Candidatos que estão no grupo A2B mas NÃO encerraram no grupo (excluídos do escopo)
    SELECT
        COUNT(*) AS QtdCandidatosForaDoEscopo
    FROM #Candidatos AS c
    LEFT JOIN #EscopoIds AS e
        ON e.id = c.id
    WHERE e.id IS NULL;
END;

--------------------------------------------------------------------------------
-- [6] Início de contagem, captura e reabertura
--------------------------------------------------------------------------------
-- Regra de contagem:
--   A Data Abertura usada na apuração FAIA/FARC NÃO é a abertura original do SDM
--   quando o chamado foi criado em outro grupo.
--
--   A contagem começa quando o chamado passa para a posse do grupo
--   Fornecedores - A2B. Exemplo de log usado como marco:
--     Transferir Grupo de 'COI' para 'Fornecedores - A2B'
--
--   Se o chamado já nasceu no grupo A2B/Protect4 e não houver log de transferência
--   para o grupo, o fallback é a abertura original do chamado.
--
--   Para FAIA, a captura é a primeira alteração de status para 'Em andamento'
--   registrada DEPOIS da entrada do chamado no grupo A2B/Protect4. Não importa
--   quem é o analista nem se ele pertence hoje ao grupo: o que vale é o chamado
--   já estar na posse do grupo A2B no momento do evento.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#InicioContagemA2B') IS NOT NULL DROP TABLE #InicioContagemA2B;

CREATE TABLE #InicioContagemA2B (
    id int NOT NULL PRIMARY KEY,
    inicio_contagem_epoch int NULL,
    fonte_inicio_contagem nvarchar(120) NOT NULL
);

INSERT INTO #InicioContagemA2B (id, inicio_contagem_epoch, fonte_inicio_contagem)
SELECT
    e.id,
    COALESCE(tg.primeira_entrada_a2b_epoch, b.open_date) AS inicio_contagem_epoch,
    CASE
        WHEN tg.primeira_entrada_a2b_epoch IS NOT NULL THEN N'Transferência para Fornecedores - A2B'
        WHEN b.open_date IS NOT NULL THEN N'Fallback: chamado nasceu no grupo A2B/Protect4'
        ELSE N'Sem início de contagem identificado'
    END AS fonte_inicio_contagem
FROM #EscopoIds AS e
JOIN #Base AS b
    ON b.id = e.id
LEFT JOIN #TransfGrupo_FAIA_P4 AS tg
    ON tg.id = b.id;

IF OBJECT_ID('tempdb..#CapturaStatus') IS NOT NULL DROP TABLE #CapturaStatus;

SELECT
    b.id,
    MIN(al.system_time) AS captura_status_epoch
INTO #CapturaStatus
FROM #EscopoIds AS e
JOIN #Base AS b
    ON b.id = e.id
JOIN #InicioContagemA2B AS ic
    ON ic.id = b.id
JOIN dbo.act_log AS al
    ON al.call_req_id = b.persid
WHERE al.system_time IS NOT NULL
  AND ic.inicio_contagem_epoch IS NOT NULL
  AND al.system_time >= ic.inicio_contagem_epoch
  AND al.type = 'ST'
  -- Sem filtro por membro do grupo: a captura depende do chamado já estar
  -- na posse do grupo A2B (system_time >= entrada no grupo), não de quem atua.
  AND (
        CONVERT(nvarchar(max), ISNULL(al.description, N'')) COLLATE Latin1_General_CI_AI LIKE N'%para ''Em andamento''%'
     OR CONVERT(nvarchar(max), ISNULL(al.action_desc,  N'')) COLLATE Latin1_General_CI_AI LIKE N'%para ''Em andamento''%'
     OR CONVERT(nvarchar(max), ISNULL(al.description, N'')) COLLATE Latin1_General_CI_AI LIKE N'%to ''Em andamento''%'
     OR CONVERT(nvarchar(max), ISNULL(al.action_desc,  N'')) COLLATE Latin1_General_CI_AI LIKE N'%to ''Em andamento''%'
     OR CONVERT(nvarchar(max), ISNULL(al.description, N'')) COLLATE Latin1_General_CI_AI LIKE N'%to ''In Progress''%'
     OR CONVERT(nvarchar(max), ISNULL(al.action_desc,  N'')) COLLATE Latin1_General_CI_AI LIKE N'%to ''In Progress''%'
  )
GROUP BY b.id;

CREATE UNIQUE CLUSTERED INDEX IX_CapturaStatus_id ON #CapturaStatus(id);

-- Fallback de captura, também por GRUPO (sem depender de membro):
-- primeira atividade registrada após a entrada no grupo A2B/Protect4, exceto as
-- próprias transferências de grupo (type 'TR'), que não representam atendimento.
IF OBJECT_ID('tempdb..#CapturaAtividade') IS NOT NULL DROP TABLE #CapturaAtividade;

SELECT
    b.id,
    MIN(al.system_time) AS primeira_atividade_epoch
INTO #CapturaAtividade
FROM #EscopoIds AS e
JOIN #Base AS b
    ON b.id = e.id
JOIN #InicioContagemA2B AS ic
    ON ic.id = b.id
JOIN dbo.act_log AS al
    ON al.call_req_id = b.persid
WHERE al.system_time IS NOT NULL
  AND ic.inicio_contagem_epoch IS NOT NULL
  AND al.system_time >= ic.inicio_contagem_epoch
  AND ISNULL(al.type, N'') <> 'TR'
GROUP BY b.id;

CREATE UNIQUE CLUSTERED INDEX IX_CapturaAtividade_id ON #CapturaAtividade(id);

IF OBJECT_ID('tempdb..#Captura') IS NOT NULL DROP TABLE #Captura;

SELECT
    e.id,
    COALESCE(cs.captura_status_epoch, caf.primeira_atividade_epoch) AS captura_epoch,
    CASE
        WHEN cs.captura_status_epoch IS NOT NULL THEN N'ST para Em andamento após entrada no grupo A2B/Protect4'
        WHEN caf.primeira_atividade_epoch IS NOT NULL THEN N'Fallback: primeira atividade após entrada no grupo A2B/Protect4'
        ELSE N'Sem captura identificada'
    END AS fonte_captura
INTO #Captura
FROM #EscopoIds AS e
LEFT JOIN #CapturaStatus AS cs
    ON cs.id = e.id
LEFT JOIN #CapturaAtividade AS caf
    ON caf.id = e.id;

CREATE UNIQUE CLUSTERED INDEX IX_Captura_id ON #Captura(id);

IF OBJECT_ID('tempdb..#Reabertura') IS NOT NULL DROP TABLE #Reabertura;

SELECT DISTINCT
    b.id,
    CAST(1 AS bit) AS houve_reabertura
INTO #Reabertura
FROM #EscopoIds AS e
JOIN #Base AS b
    ON b.id = e.id
JOIN dbo.act_log AS al
    ON al.call_req_id = b.persid
WHERE
    CONVERT(nvarchar(max), ISNULL(al.type, N'')) COLLATE Latin1_General_CI_AI LIKE N'%reab%'
    OR CONVERT(nvarchar(max), ISNULL(al.description, N'')) COLLATE Latin1_General_CI_AI LIKE N'%reabert%'
    OR CONVERT(nvarchar(max), ISNULL(al.action_desc, N'')) COLLATE Latin1_General_CI_AI LIKE N'%reabert%';

CREATE UNIQUE CLUSTERED INDEX IX_Reabertura_id ON #Reabertura(id);

--------------------------------------------------------------------------------
-- [7] Base final com datas em horário do Brasil
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#BaseEscopo') IS NOT NULL DROP TABLE #BaseEscopo;

SELECT
    b.*,
    e.FonteFornecedor,
    ic.inicio_contagem_epoch,
    ic.fonte_inicio_contagem,
    COALESCE(c.captura_epoch, ic.inicio_contagem_epoch) AS captura_epoch,
    CASE WHEN ic.inicio_contagem_epoch IS NULL THEN NULL
         ELSE DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, ic.inicio_contagem_epoch, @Epoch))
    END AS data_abertura_br,
    CASE WHEN COALESCE(c.captura_epoch, ic.inicio_contagem_epoch) IS NULL THEN NULL
         ELSE DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, COALESCE(c.captura_epoch, ic.inicio_contagem_epoch), @Epoch))
    END AS data_captura_br,
    CASE WHEN b.close_date IS NULL THEN NULL
         ELSE DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, b.close_date, @Epoch))
    END AS data_fechamento_br,
    CASE WHEN r.houve_reabertura = 1 THEN N'Sim' ELSE N'Não' END AS indicador_reabertura
INTO #BaseEscopo
FROM #EscopoIds AS e
JOIN #Base AS b
    ON b.id = e.id
LEFT JOIN #InicioContagemA2B AS ic
    ON ic.id = b.id
LEFT JOIN #Captura AS c
    ON c.id = b.id
LEFT JOIN #Reabertura AS r
    ON r.id = b.id;

CREATE UNIQUE CLUSTERED INDEX IX_BaseEscopo_id ON #BaseEscopo(id);

--------------------------------------------------------------------------------
-- [8] Números para cálculo de horas comerciais 08:00-20:00, segunda a sexta
--------------------------------------------------------------------------------
DECLARE @MaxDiasFAIA int =
(
    SELECT ISNULL(MAX(
        CASE
            WHEN data_abertura_br IS NOT NULL
             AND data_captura_br IS NOT NULL
             AND data_captura_br >= data_abertura_br
            THEN DATEDIFF(DAY, CAST(data_abertura_br AS date), CAST(data_captura_br AS date))
            ELSE 0
        END
    ), 0)
    FROM #BaseEscopo
);

IF OBJECT_ID('tempdb..#Nums') IS NOT NULL DROP TABLE #Nums;
CREATE TABLE #Nums (n int NOT NULL PRIMARY KEY);

INSERT INTO #Nums(n)
SELECT TOP (@MaxDiasFAIA + 1)
       ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1
FROM sys.all_objects a
CROSS JOIN sys.all_objects b;

--------------------------------------------------------------------------------
-- [8.1] Quantidade de logs por chamado (coluna auxiliar de conferência)
--
-- Conta TODOS os registros de dbo.act_log do chamado, sem filtro por tipo:
-- INIT, ST, TR, SOLN, CL, LOG, FLD, SRVY_SENT, ATTACHTDOC e quaisquer outros.
-- Regra: 1 registro em dbo.act_log = 1 log. Não é a contagem dos logs que
-- participam do cálculo do FAIA; é o total bruto, para conferência.
--
-- A agregação é feita AQUI, por chamado, justamente para que o SELECT final não
-- precise fazer JOIN direto com dbo.act_log — o que multiplicaria a linha do
-- chamado pela quantidade de logs. O GROUP BY b.id mais o índice UNIQUE abaixo
-- garantem, estruturalmente, no máximo uma linha por chamado.
--
-- LEFT JOIN + COUNT(al.call_req_id): chamado sem nenhum log conta 0, não NULL
-- (COUNT de coluna ignora os NULL gerados pelo LEFT JOIN sem correspondência).
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#QtdLogs') IS NOT NULL DROP TABLE #QtdLogs;

SELECT
    b.id,
    COUNT_BIG(al.call_req_id) AS quantidade_logs
INTO #QtdLogs
FROM #EscopoIds AS e
JOIN #Base AS b
    ON b.id = e.id
LEFT JOIN dbo.act_log AS al
    ON al.call_req_id = b.persid
GROUP BY b.id;

CREATE UNIQUE CLUSTERED INDEX IX_QtdLogs_id ON #QtdLogs(id);

--------------------------------------------------------------------------------
-- [9] Cálculo FAIA
--------------------------------------------------------------------------------
;WITH Calc AS (
    SELECT
        b.*,
        sl.meta_inicio_seg,
        sl.tipo_inicio,
        CASE
            WHEN b.data_abertura_br IS NULL OR b.data_captura_br IS NULL THEN NULL
            WHEN b.data_captura_br < b.data_abertura_br THEN 0
            WHEN sl.tipo_inicio = 'CORRIDA'
                -- Corrida: conta o intervalo bruto 24x7, sem desconto de feriado/facultativo
                THEN COALESCE(bh.segundos_corridos, 0)
            WHEN sl.tipo_inicio = 'COMERCIAL'
                -- Comercial: só conta seg-sex 08:00-20:00, excluindo feriados/facultativos
                THEN COALESCE(bh.segundos_comerciais, 0)
            ELSE NULL
        END AS tempo_primeiro_seg
    FROM #BaseEscopo AS b
    LEFT JOIN #SLA_FAIA_P4 AS sl
        ON sl.prioridade = b.prioridade_nivel
    OUTER APPLY (
        SELECT
            segundos_corridos   = COALESCE(SUM(x.seg_corrido),   0),
            segundos_comerciais = COALESCE(SUM(x.seg_comercial), 0)
        FROM (
            SELECT
                -- CORRIDA: conta 24x7, sem desconto de feriados/facultativos
                seg_corrido = CASE
                    WHEN janela_c.fim_calc > janela_c.ini_calc
                        THEN DATEDIFF(SECOND, janela_c.ini_calc, janela_c.fim_calc)
                    ELSE 0
                END,
                -- COMERCIAL: 08:00-20:00 seg-sex, excluindo feriados/facultativos
                seg_comercial = CASE
                    WHEN cal.eh_feriado_ou_facultativo = 1 THEN 0
                    WHEN cal.eh_dia_util = 0              THEN 0
                    WHEN janela_h.fim_calc > janela_h.ini_calc
                        THEN DATEDIFF(SECOND, janela_h.ini_calc, janela_h.fim_calc)
                    ELSE 0
                END
            FROM (
                SELECT DATEADD(DAY, n.n, CAST(b.data_abertura_br AS date)) AS dt
                FROM #Nums AS n
                WHERE b.data_abertura_br IS NOT NULL
                  AND b.data_captura_br IS NOT NULL
                  AND b.data_captura_br >= b.data_abertura_br
                  AND n.n <= DATEDIFF(DAY, CAST(b.data_abertura_br AS date), CAST(b.data_captura_br AS date))
            ) AS dias
            CROSS APPLY (
                SELECT
                    dt_date = CAST(dias.dt AS date),
                    mes_dia = RIGHT(CONVERT(char(10), CAST(dias.dt AS date), 120), 5)
            ) AS d
            CROSS APPLY (
                SELECT
                    eh_feriado_ou_facultativo = CASE
                        WHEN EXISTS (SELECT 1 FROM #FeriadosFixos fx WHERE fx.mes_dia = d.mes_dia)
                          OR EXISTS (SELECT 1 FROM #FeriadosPorData fd WHERE fd.data = d.dt_date)
                        THEN 1 ELSE 0
                    END,
                    eh_dia_util = CASE
                        WHEN DATEDIFF(DAY, '19000101', d.dt_date) % 7 BETWEEN 0 AND 4
                        THEN 1 ELSE 0
                    END
            ) AS cal
            -- Janela CORRIDA: dia inteiro (00:00 a 24:00)
            CROSS APPLY (
                SELECT
                    ini_calc = CASE WHEN b.data_abertura_br > CAST(d.dt_date AS datetime2(0))
                                    THEN b.data_abertura_br ELSE CAST(d.dt_date AS datetime2(0)) END,
                    fim_calc = CASE WHEN b.data_captura_br  < DATEADD(DAY, 1, CAST(d.dt_date AS datetime2(0)))
                                    THEN b.data_captura_br  ELSE DATEADD(DAY, 1, CAST(d.dt_date AS datetime2(0))) END
            ) AS janela_c
            -- Janela COMERCIAL: @HoraInicioComercial a @HoraFimComercial
            CROSS APPLY (
                SELECT
                    ini_calc = CASE WHEN b.data_abertura_br > DATEADD(HOUR, @HoraInicioComercial, CAST(d.dt_date AS datetime2(0)))
                                    THEN b.data_abertura_br ELSE DATEADD(HOUR, @HoraInicioComercial, CAST(d.dt_date AS datetime2(0))) END,
                    fim_calc = CASE WHEN b.data_captura_br  < DATEADD(HOUR, @HoraFimComercial,    CAST(d.dt_date AS datetime2(0)))
                                    THEN b.data_captura_br  ELSE DATEADD(HOUR, @HoraFimComercial,  CAST(d.dt_date AS datetime2(0))) END
            ) AS janela_h
        ) AS x
    ) AS bh
),
Final AS (
    SELECT
        c.*,
        CASE
            WHEN c.tempo_primeiro_seg IS NULL OR c.meta_inicio_seg IS NULL THEN NULL
            WHEN c.tempo_primeiro_seg > c.meta_inicio_seg THEN c.tempo_primeiro_seg - c.meta_inicio_seg
            ELSE 0
        END AS primeiro_excedido_seg
    FROM Calc AS c
)
SELECT
    f.ref_num AS [SDM],
    CASE f.[type]
        WHEN 'I' THEN N'Incidente'
        WHEN 'R' THEN N'Solicitação'
        WHEN 'P' THEN N'Problema'
        WHEN 'C' THEN N'Mudança'
        ELSE CONCAT(N'Outro/Não mapeado: ', ISNULL(CONVERT(nvarchar(10), f.[type]), N'NULO'))
    END AS [Tipo Chamado],
    CASE f.prioridade_nivel
        WHEN 1 THEN N'1 - Máxima'
        WHEN 2 THEN N'2 - Alta'
        WHEN 3 THEN N'3 - Média'
        WHEN 4 THEN N'4 - Baixa'
        WHEN 5 THEN N'5 - Mínima'
        ELSE N'NãoInformada'
    END AS [Severidade],
    ISNULL(f.status_sym, N'N/A') AS [Status],
    ISNULL(f.categoria_sym, N'N/A') AS [Categoria],
    f.responsavel_abertura AS [Responsável Abertura],
    f.responsavel_atendimento AS [Responsável Atendimento],
    LTRIM(RTRIM(f.summary_txt)) AS [Resumo],
    f.data_abertura_br AS [Data Abertura],
    f.data_captura_br AS [Data Captura],
    f.data_fechamento_br AS [Data de Fechamento],

    CASE WHEN f.tempo_primeiro_seg IS NULL THEN NULL ELSE CONCAT(
        CONVERT(varchar(20), f.tempo_primeiro_seg / 3600), N':',
        RIGHT(N'00' + CONVERT(varchar(2), (f.tempo_primeiro_seg % 3600) / 60), 2), N':',
        RIGHT(N'00' + CONVERT(varchar(2), f.tempo_primeiro_seg % 60), 2)
    ) END AS [Tempo Primeiro Atendimento],

    CASE WHEN f.primeiro_excedido_seg IS NULL THEN NULL ELSE CONCAT(
        CONVERT(varchar(20), f.primeiro_excedido_seg / 3600), N':',
        RIGHT(N'00' + CONVERT(varchar(2), (f.primeiro_excedido_seg % 3600) / 60), 2), N':',
        RIGHT(N'00' + CONVERT(varchar(2), f.primeiro_excedido_seg % 60), 2)
    ) END AS [Primeiro Atendimento Excedido],

    CASE
        WHEN f.primeiro_excedido_seg IS NULL THEN N'N/A'
        WHEN f.primeiro_excedido_seg > 0 THEN N'Não Atende'
        ELSE N'Atende'
    END AS [Meta Primeiro Atendimento],
    f.indicador_reabertura AS [Indicador Reabertura],
    N'-' AS [Acordo Prazo],
    N'-' AS [Acordo Qualidade],
    N'-' AS [Justificativa],

    -- [nHR_FAIA] PROPORCIONAL, com casas decimais: fração de hora NÃO vira hora
    -- inteira. Mesmo padrão vigente no FAIA Decision (decision/queries/
    -- consulta_faia.sql): CONVERT(decimal(18,2), excedido / 3600.0).
    -- O CEILING anterior transformava 5400 s (1h30) em 2; agora resulta 1.50.
    CASE WHEN f.primeiro_excedido_seg IS NULL THEN NULL ELSE
        CONVERT(decimal(18, 2), f.primeiro_excedido_seg / 3600.0)
    END AS [nHR_FAIA],

    -- [FAIA] = nHR proporcional x fator 0,1 (fator contratual do A2B/Protect4).
    -- Calculado a partir do quociente cheio, e não do nHR já arredondado para 2
    -- casas, exatamente como o FAIA Decision faz com o fator_inicio.
    CASE WHEN f.primeiro_excedido_seg IS NULL THEN NULL ELSE
        CONVERT(decimal(18, 2), (f.primeiro_excedido_seg / 3600.0) * 0.1)
    END AS [FAIA],

    --------------------------------------------------------------------------
    -- Colunas auxiliares de conferência (somente nesta consulta FAIA Protect4).
    -- Acrescentadas ao FINAL do SELECT, depois de todas as colunas existentes,
    -- para não alterar a ordem nem o nome do layout já usado pelo relatório.
    --
    -- Dia da semana determinístico: usa DATEDIFF a partir de 1900-01-01, que foi
    -- uma segunda-feira, e o resto da divisão por 7. Não depende de SET LANGUAGE,
    -- SET DATEFIRST nem DATENAME(WEEKDAY, ...), então o resultado é o mesmo em
    -- qualquer sessão. É o mesmo idioma de calendário já usado no bloco comercial
    -- desta consulta (`% 7 BETWEEN 0 AND 4` para dias úteis):
    --   0=Segunda 1=Terça 2=Quarta 3=Quinta 4=Sexta 5=Sábado 6=Domingo.
    -- Os timestamps são os já convertidos para horário do Brasil em #BaseEscopo
    -- (data_abertura_br / data_captura_br): NÃO há segunda conversão de fuso.
    --------------------------------------------------------------------------
    CONVERT(varchar(8), f.data_abertura_br, 108) AS [Hora da Abertura],

    -- Mesmo marco de captura usado no cálculo de [Tempo Primeiro Atendimento]:
    -- a coluna data_captura_br de #BaseEscopo. Não existe segunda definição de
    -- captura nem log alternativo só para esta coluna. Sem captura, o valor é
    -- NULL, igual ao tratamento já dado à coluna [Data Captura].
    CONVERT(varchar(8), f.data_captura_br, 108) AS [Hora da Captura],

    CASE DATEDIFF(DAY, '19000101', CAST(f.data_abertura_br AS date)) % 7
        WHEN 0 THEN N'Segunda-feira'
        WHEN 1 THEN N'Terça-feira'
        WHEN 2 THEN N'Quarta-feira'
        WHEN 3 THEN N'Quinta-feira'
        WHEN 4 THEN N'Sexta-feira'
        WHEN 5 THEN N'Sábado'
        WHEN 6 THEN N'Domingo'
        ELSE NULL
    END AS [Dia da Semana da Abertura],

    CASE DATEDIFF(DAY, '19000101', CAST(f.data_captura_br AS date)) % 7
        WHEN 0 THEN N'Segunda-feira'
        WHEN 1 THEN N'Terça-feira'
        WHEN 2 THEN N'Quarta-feira'
        WHEN 3 THEN N'Quinta-feira'
        WHEN 4 THEN N'Sexta-feira'
        WHEN 5 THEN N'Sábado'
        WHEN 6 THEN N'Domingo'
        ELSE NULL
    END AS [Dia da Semana da Captura],

    -- Total bruto de registros em dbo.act_log, já agregado por chamado em [8.1].
    -- O ISNULL cobre apenas o caso teórico de o chamado não constar de #QtdLogs;
    -- chamados sem log já saem de lá com 0.
    ISNULL(ql.quantidade_logs, 0) AS [Quantidade de Logs]
FROM Final AS f
LEFT JOIN #QtdLogs AS ql
    ON ql.id = f.id
ORDER BY
    f.data_fechamento_br ASC,
    f.ref_num ASC
OPTION (RECOMPILE);

-- As colunas [nHR_FAIA] e [FAIA] ficam no SELECT final para manter o layout esperado pelo relatório.
-- As cinco colunas auxiliares ([Hora da Abertura], [Hora da Captura], [Dia da
-- Semana da Abertura], [Dia da Semana da Captura] e [Quantidade de Logs]) vêm
-- depois delas, no fim do SELECT, e existem somente nesta consulta FAIA Protect4.