USE mdb;
SET NOCOUNT ON;

-- Limpa versão anterior da tabela temporária, caso a sessão tenha executado uma versão antiga.
IF OBJECT_ID('tempdb..#InicioContagem') IS NOT NULL DROP TABLE #InicioContagem;

--------------------------------------------------------------------------------
-- MAPA DOS BLOCOS (índice)
--   [SLA]          #SLA_FARC_P4                       metas por severidade
--   [0]            #FornecedorMembros         membros do grupo A2B
--   [1]            #CRPeriodo                 pré-filtro por período de fechamento
--   [2]            #Base                      base enriquecida (status, categoria, sev)
--   [3]            #EscopoIds                 quais chamados entram (A2B, I/R/P, terminal)
--   [3.1]          #LogEscopo                 copia do act_log lida uma vez (perf)
--   [4]            #EntradaGrupo/#InicioContagemA2B_FARC_P4  início da contagem (entrada na A2B)
--   [4]            #CapturaStatus/#Captura    1ª ida para 'Em andamento'
--   [4]            #Reabertura                marca reabertura
--   [5]            #BaseEscopo_FARC_P4                base final com datas em horário do Brasil
--   [6]            #TerminalFARC              limite máximo da contagem
--   [6.1]          #TempoAtendimentoLog       auditoria de time_spent (não entra no FARC)
--   [6.3.1-3]      #GrupoEventos/#GrupoInicial/#JanelasA2B  janelas de posse A2B (reposse)
--   [6.3.4-6]      #StatusEvA2B/#SegAtivoA2B/#PisoInicial/#PecasAtivasA2B  tempo ativo
--   [7/7.1]        #Nums/#TempoAtivoJanelasA2B  soma corrida/comercial das peças A2B
--   [8A]           #TempoAtendimentoRotina    motor de rotina (intervalo)
--   [8B]           #TempoAtendimentoStatusLead  motor unico (tempo em 'Em andamento')
--   [8C]           #MotorBase_FARC_P4                 motor base por chamado (rotina ou contido)
--   [9]            BaseCalc/Final/SELECT      tempo_atendimento_seg e FARC
--
-- Nesta versão refatorada (sem mudar o cálculo):
--   - removido #CapturaAtividadeFornecedor (era calculado e nunca usado);
--   - a escolha do motor base virou #MotorBase_FARC_P4, calculada UMA vez, em vez de
--     repetida três vezes (cálculo final + duas no diagnóstico).
--   Validação obrigatória: rode com @MostrarDiagnostico = 1 e compare a coluna
--   SegundosFinal por SDM com a versão anterior. Devem ser idênticas.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Consulta FARC - A2B/Protect4
-- Versão BO - tempo ATIVO somado por janelas de posse A2B (corrige reposse).
--
-- Regra do Tempo de Atendimento:
--   1) Rotinas operacionais parametrizadas (A2B.Realizar - Passagem de turno e
--      A2B.Job Summary Report) usam o intervalo Data Abertura FARC -> Fechamento,
--      com recorte comercial quando a severidade é P3/P4/P5.
--   2) Demais chamados usam a SOMA do tempo ATIVO em TODAS as janelas em que o
--      grupo A2B teve a posse do chamado (entra, sai e volta = reposse; conta-se
--      cada janela, não só a última).
--        - Status que CONTAM como ativo: 'Em andamento' e 'Aberto, aguarda
--          atendimento' (espera inicial na fila do A2B, antes do 1o atendimento).
--        - Status que NÃO contam: Agendado, Aguarda atendimento, Em homologação,
--          Em teste na TI e quaisquer outros.
--        - A soma é cortada no terminal (resolução -> 1a ida 'Em homologação';
--          senão 'Resolvido') e respeita a severidade: P1/P2 corrida; P3/P4/P5
--          comercial seg-sex 08:00-20:00.
--
-- Posse A2B (janelas): reconstruída a partir de TODAS as mudanças de grupo no
--   act_log (entradas e saídas), começando no estado de grupo da criação
--   (open_date). O motor antigo pegava só a última entrada e por isso perdia o
--   tempo das janelas anteriores nos casos de reposse.
--
-- NOMES EXCLUSIVOS DE TEMPORARIA (correcao do Msg 207)
--   Uma tabela # vive ate o fim da SESSAO, e o SQL Server COMPILA o lote inteiro
--   antes de executa-lo. Logo, o "IF OBJECT_ID(...) DROP TABLE" so roda na
--   execucao: se outra consulta ja deixou na sessao uma # de mesmo nome e esquema
--   DIFERENTE, a compilacao liga esta consulta a tabela velha e acusa
--   "Msg 207 - Invalid column name".
--
--   Quatro temporarias desta consulta tinham esquema incompativel com homonimas
--   de outras consultas e por isso receberam nome exclusivo:
--     #SLA_FARC_P4                 (o #SLA do FAIA Decision nao tem
--                                   meta_resolucao_seg nem tipo_resolucao)
--     #BaseEscopo_FARC_P4          (as versoes do FAIA Protect4 e do FAIA
--                                   Decision nao tem detalhe_inicio_contagem)
--     #InicioContagemA2B_FARC_P4   (a versao do FAIA Protect4 nao tem
--                                   detalhe_inicio_contagem)
--     #MotorBase_FARC_P4           (o #MotorBase do FARC Decision nao tem
--                                   motivo_base)
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

--------------------------------------------------------------------------------
-- [SLA por severidade]
-- Conforme SLA por Severidade.png:
-- P1: início 15 min corridos; resolução 12h corrida
-- P2: início 60 min corridos; resolução 24h corrida
-- P3/P4: início 240 min comerciais; resolução 36h comercial
-- P5: início 720 min comerciais; resolução 360h comercial
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#SLA_FARC_P4') IS NOT NULL DROP TABLE #SLA_FARC_P4;
CREATE TABLE #SLA_FARC_P4 (
    prioridade            tinyint     NOT NULL PRIMARY KEY,
    meta_inicio_seg       int         NOT NULL,
    tipo_inicio           varchar(10) NOT NULL, -- CORRIDA | COMERCIAL
    meta_resolucao_seg    int         NOT NULL,
    tipo_resolucao        varchar(10) NOT NULL  -- CORRIDA | COMERCIAL
);

INSERT INTO #SLA_FARC_P4(prioridade, meta_inicio_seg, tipo_inicio, meta_resolucao_seg, tipo_resolucao)
VALUES
    (1,  15 * 60,       'CORRIDA',    12 * 60 * 60,       'CORRIDA'),
    (2,  60 * 60,       'CORRIDA',    24 * 60 * 60,       'CORRIDA'),
    (3, 240 * 60,       'COMERCIAL',  36 * 60 * 60,       'COMERCIAL'),
    (4, 240 * 60,       'COMERCIAL',  36 * 60 * 60,       'COMERCIAL'),
    (5, 720 * 60,       'COMERCIAL', 360 * 60 * 60,       'COMERCIAL');

--------------------------------------------------------------------------------
-- [SLA+] Feriados e pontos facultativos (para o recorte comercial P3/P4/P5)
--
-- O calculo comercial (08:00-20:00 seg-sex) desconta estes dias, alem do fim de
-- semana. So afeta severidades comerciais; corrido (P1/P2) ignora feriado.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#FeriadosFixos') IS NOT NULL DROP TABLE #FeriadosFixos;
CREATE TABLE #FeriadosFixos (mes_dia char(5) NOT NULL PRIMARY KEY, descricao nvarchar(200) NOT NULL);
INSERT INTO #FeriadosFixos (mes_dia, descricao)
VALUES
    ('01-01', N'Confraternizacao Universal'),
    ('04-21', N'Tiradentes'),
    ('05-01', N'Dia Mundial do Trabalho'),
    ('09-07', N'Independencia do Brasil'),
    ('10-12', N'Nossa Senhora Aparecida'),
    ('11-02', N'Finados'),
    ('11-15', N'Proclamacao da Republica'),
    ('11-20', N'Dia Nacional de Zumbi e da Consciencia Negra'),
    ('12-25', N'Natal');

IF OBJECT_ID('tempdb..#FeriadosPorData') IS NOT NULL DROP TABLE #FeriadosPorData;
CREATE TABLE #FeriadosPorData (data date NOT NULL PRIMARY KEY, descricao nvarchar(200) NOT NULL);
-- Pontos facultativos de 2025 no TCU (24/12 e 31/12 ja existiam).
-- Fonte: Portaria-TCU n. 10/2025 e alteracoes n. 157/2025 e n. 176/2025
-- (Boletim do TCU; autenticidade em www.tcu.gov.br/autenticidade, codigos
-- 77411949, 79190602 e 79506777). 27/10, 21/11 e 26/12 incluidos em 2026-09-18.
INSERT INTO #FeriadosPorData (data, descricao)
VALUES
    ('2025-10-27', N'Dia do Servidor Publico federal - ponto facultativo'),
    ('2025-11-21', N'Ponto facultativo - sexta-feira apos Consciencia Negra'),
    ('2025-12-24', N'Ponto facultativo - vespera do Natal'),
    ('2025-12-26', N'Ponto facultativo - sexta-feira apos o Natal'),
    ('2025-12-31', N'Ponto facultativo - vespera da Confraternizacao Universal');
-- Moveis/diferenciados de 2026:
INSERT INTO #FeriadosPorData (data, descricao)
VALUES
    ('2026-04-03', N'Paixao de Cristo'),
    ('2026-04-05', N'Pascoa');
-- Pontos facultativos de 2026 no TCU:
INSERT INTO #FeriadosPorData (data, descricao)
VALUES
    ('2026-01-02', N'Ponto facultativo - emenda apos Confraternizacao Universal'),
    ('2026-02-16', N'Carnaval - ponto facultativo'),
    ('2026-02-17', N'Carnaval - ponto facultativo'),
    ('2026-02-18', N'Quarta-Feira de Cinzas - ponto facultativo'),
    ('2026-04-02', N'Ponto facultativo - vespera da Paixao de Cristo'),
    ('2026-04-20', N'Ponto facultativo - emenda antes de Tiradentes'),
    ('2026-06-04', N'Corpus Christi - ponto facultativo'),
    ('2026-06-05', N'Ponto facultativo - emenda apos Corpus Christi'),
    ('2026-06-29', N'Ponto facultativo - jogo da Selecao Brasileira na Copa do Mundo FIFA 2026'), -- Portaria-TCU n. 93/2026 (codigo 80587034), incluido em 2026-09-18
    ('2026-10-28', N'Dia do Servidor Publico federal - ponto facultativo'),
    ('2026-12-24', N'Ponto facultativo - vespera do Natal'),
    ('2026-12-31', N'Ponto facultativo - vespera da Confraternizacao Universal');

--------------------------------------------------------------------------------
-- [0] Membros do grupo do fornecedor
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#FornecedorMembros') IS NOT NULL DROP TABLE #FornecedorMembros;
CREATE TABLE #FornecedorMembros (
    contact_uuid varbinary(16) NOT NULL PRIMARY KEY
);

INSERT INTO #FornecedorMembros(contact_uuid)
SELECT DISTINCT gm.member
FROM dbo.grpmem AS gm
WHERE gm.group_id = @FornecedorGrupo
  AND gm.member IS NOT NULL;

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
-- [2] Base enriquecida: status, categoria, contatos e severidade real
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
-- IX_Base_categoria removido: categoria_sym excede 1700 bytes e gerava aviso de
-- chave de indice muito grande. A coluna nao e usada como chave de busca.
CREATE INDEX IX_Base_assignee ON #Base(assignee);
CREATE INDEX IX_Base_group ON #Base(group_id);

--------------------------------------------------------------------------------
-- [3] Escopo do fornecedor
--
-- Regra oficial: chamado pertence ao fornecedor quando o grupo atual do chamado
-- é o grupo A2B/Protect4. Não use categoria como filtro principal.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#EscopoIds') IS NOT NULL DROP TABLE #EscopoIds;
CREATE TABLE #EscopoIds (
    id int NOT NULL PRIMARY KEY,
    FonteFornecedor nvarchar(50) NOT NULL
);

INSERT INTO #EscopoIds(id, FonteFornecedor)
SELECT b.id, N'Grupo atual A2B/Protect4'
FROM #Base AS b
WHERE b.group_id = @FornecedorGrupo
  AND b.[type] IN ('I', 'R', 'P')
  -- Encerramento/resolucao/cancelamento por CODIGO (sigla) de status, nunca por
  -- texto/descricao. Lista estavel e reaproveitavel para qualquer mes: contem
  -- apenas estados TERMINAIS. Nao inclui intermediarios, suspensos, abertos, em
  -- andamento, homologacao, teste, reabertura nem aguardando fornecedor.
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

--------------------------------------------------------------------------------
-- [3.1] Materializacao do log do escopo (PERFORMANCE)
--
-- act_log e a maior tabela e era varrida ~12 vezes, cada uma reconvertendo
-- description/action_desc. Aqui ela e lida UMA vez, so para os chamados do
-- escopo, e as passadas seguintes leem desta copia (#LogEscopo) em vez de
-- dbo.act_log. Mesmas colunas e mesmos tipos: a logica de cada passada nao muda.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#LogEscopo') IS NOT NULL DROP TABLE #LogEscopo;
SELECT
    src.id AS log_id,  -- desempate de eventos no mesmo segundo (ver nota junto aos LEAD)
    src.call_req_id,
    src.system_time,
    src.description,
    src.action_desc,
    src.[type],
    src.time_spent,
    CONVERT(nvarchar(max), ISNULL(src.description, N'')) + N' ' +
    CONVERT(nvarchar(max), ISNULL(src.action_desc,  N'')) AS texto_log
INTO #LogEscopo
FROM dbo.act_log AS src
WHERE src.call_req_id IN (
    SELECT b.persid
    FROM #EscopoIds AS e
    JOIN #Base AS b ON b.id = e.id
);
CREATE INDEX IX_LogEscopo_cr_time ON #LogEscopo(call_req_id, system_time);

IF @MostrarDiagnostico = 1
BEGIN
    SELECT
        COUNT(*) AS TotalNoEscopoFornecedor,
        SUM(CASE WHEN categoria_sym COLLATE Latin1_General_CI_AI LIKE N'A2B.%' THEN 1 ELSE 0 END) AS QtdCategoriaA2B,
        SUM(CASE WHEN categoria_sym COLLATE Latin1_General_CI_AI LIKE N'A2B.%' THEN 0 ELSE 1 END) AS QtdForaCategoriaA2B
    FROM #Base AS b
    JOIN #EscopoIds AS e
        ON e.id = b.id;

    SELECT
        ISNULL(status_sym, N'N/A') AS Status,
        COUNT(*) AS Qtd
    FROM #Base AS b
    JOIN #EscopoIds AS e
        ON e.id = b.id
    GROUP BY ISNULL(status_sym, N'N/A')
    ORDER BY Qtd DESC, Status;

    SELECT
        ISNULL(categoria_sym, N'N/A') AS Categoria,
        COUNT(*) AS Qtd
    FROM #Base AS b
    JOIN #EscopoIds AS e
        ON e.id = b.id
    WHERE categoria_sym COLLATE Latin1_General_CI_AI NOT LIKE N'A2B.%'
    GROUP BY ISNULL(categoria_sym, N'N/A')
    ORDER BY Qtd DESC, Categoria;
END;

--------------------------------------------------------------------------------
-- [4] Entrada no grupo, captura e reabertura somente para chamados já no escopo
--------------------------------------------------------------------------------
-- Regra revisada:
--   A Data Abertura usada na apuração FAIA/FARC NÃO é a abertura original do SDM
--   quando o chamado foi criado em outro grupo.
--
--   A contagem começa quando o chamado passa para a posse do grupo Fornecedores - A2B.
--   Exemplo de log usado como marco:
--     Transferir Grupo de 'COI' para 'Fornecedores - A2B'
--
--   Se o chamado já nasceu no grupo A2B/Protect4 e não houver log de transferência
--   para o grupo, o fallback é a abertura original do chamado.
--
--   Para FAIA, a captura continua sendo a primeira alteração de status para
--   'Em andamento' feita por membro do grupo Fornecedores - A2B, mas somente
--   depois da entrada do chamado no grupo.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#EntradaGrupo') IS NOT NULL DROP TABLE #EntradaGrupo;
IF OBJECT_ID('tempdb..#EntradaGrupoCandidato') IS NOT NULL DROP TABLE #EntradaGrupoCandidato;

--------------------------------------------------------------------------------
-- [4.1] Entrada efetiva no grupo A2B/Protect4
--
-- Correção real aplicada após reanálise dos chamados 1693946, 1693751,
-- 1694180, 1692381 e 1691161.
--
-- O erro da versão anterior foi tentar descobrir a entrada no fornecedor apenas
-- por texto livre do act_log.description/action_desc. Nos logs exportados, o
-- marco correto é a mudança de GRUPO; porém a linha exportada aparece apenas
-- como "Transferir", sem expor no XLS o detalhe do destino. Por isso o texto do
-- act_log pode não bater, e a consulta cai no open_date ou em uma transferência
-- anterior.
--
-- Nesta versão, a ordem de confiança é:
--   1) View_Audit_Group, quando existir: fonte própria de histórico de grupo.
--   2) audit_log direto, quando existir: attr_name de grupo e attr_after_val do
--      grupo do fornecedor.
--   3) act_log textual: apenas fallback, com filtro estrito de transferência de
--      GRUPO, sem aceitar qualquer "A2B" genérico.
--
-- Seleção final: usa primeiro o act_log.TR textual exato quando ele traz:
--   Transferir Grupo de '...' para 'Fornecedores - A2B'
-- porque esse é o mesmo marco que aparece nos logs detalhados e nos exemplos
-- 1691161, 1692381, 1693751, 1693946 e 1694180.
-- As fontes View_Audit_Group e audit_log ficam como fallback, não como fonte
-- preferencial, porque podem trazer permanências ou alterações correlatas que
-- não representam exatamente o corte do relatório.
-- Dentro da mesma fonte, usa a última entrada antes do fechamento para evitar
-- contar tempo de um trecho anterior caso o chamado tenha saído e reentrado no
-- fornecedor.
--------------------------------------------------------------------------------
CREATE TABLE #EntradaGrupoCandidato (
    id                   int NOT NULL,
    entrada_grupo_epoch  int NOT NULL,
    prioridade_fonte     tinyint NOT NULL,
    fonte_entrada        nvarchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
    detalhe_entrada      nvarchar(4000) COLLATE DATABASE_DEFAULT NULL
);

DECLARE @FornecedorGrupoHex nvarchar(100) = CONVERT(nvarchar(100), @FornecedorGrupo, 1);
DECLARE @FornecedorGrupoHexSem0x nvarchar(100) = CASE
    WHEN CONVERT(nvarchar(100), @FornecedorGrupo, 1) LIKE N'0x%'
        THEN SUBSTRING(CONVERT(nvarchar(100), @FornecedorGrupo, 1), 3, 200)
    ELSE CONVERT(nvarchar(100), @FornecedorGrupo, 1)
END;

--------------------------------------------------------------------------------
-- Fonte 1: View_Audit_Group
-- CA SDM fornece esta view avançada para histórico de permanência por grupo.
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.View_Audit_Group', N'V') IS NOT NULL
BEGIN
    DECLARE @sqlViewAuditGroup nvarchar(max) = N'
        INSERT INTO #EntradaGrupoCandidato
            (id, entrada_grupo_epoch, prioridade_fonte, fonte_entrada, detalhe_entrada)
        SELECT
            b.id,
            TRY_CONVERT(int, vag.from_time) AS entrada_grupo_epoch,
            CONVERT(tinyint, 10) AS prioridade_fonte,
            N''View_Audit_Group'' AS fonte_entrada,
            CONCAT(N''to_val='', CONVERT(nvarchar(4000), vag.to_val)) AS detalhe_entrada
        FROM #EscopoIds AS e
        JOIN #Base AS b
            ON b.id = e.id
        JOIN dbo.View_Audit_Group AS vag
            ON (
                   CONVERT(nvarchar(100), vag.audobj_uniqueid) = CONVERT(nvarchar(100), b.id)
                OR CONVERT(nvarchar(100), vag.audobj_uniqueid) = CONVERT(nvarchar(100), b.persid)
                OR CONVERT(nvarchar(100), vag.audobj_uniqueid) = CONVERT(nvarchar(100), b.ref_num)
            )
        CROSS APPLY (
            SELECT to_val_txt = CONVERT(nvarchar(4000), ISNULL(vag.to_val, N''''))
        ) AS tv
        WHERE TRY_CONVERT(int, vag.from_time) IS NOT NULL
          AND (b.open_date IS NULL OR TRY_CONVERT(int, vag.from_time) >= b.open_date)
          AND (b.close_date IS NULL OR TRY_CONVERT(int, vag.from_time) <= b.close_date)
          AND (
                 tv.to_val_txt COLLATE Latin1_General_CI_AI LIKE N''%Fornecedores%A2B%''
              OR tv.to_val_txt COLLATE Latin1_General_CI_AI LIKE N''%A2B/Protect4%''
              OR tv.to_val_txt COLLATE Latin1_General_CI_AI LIKE N''%A2B%Protect4%''
              OR UPPER(tv.to_val_txt) LIKE N''%'' + UPPER(@FornecedorGrupoHex) + N''%''
              OR UPPER(tv.to_val_txt) LIKE N''%'' + UPPER(@FornecedorGrupoHexSem0x) + N''%''
          );';

    EXEC sp_executesql
        @sqlViewAuditGroup,
        N'@FornecedorGrupoHex nvarchar(100), @FornecedorGrupoHexSem0x nvarchar(100)',
        @FornecedorGrupoHex = @FornecedorGrupoHex,
        @FornecedorGrupoHexSem0x = @FornecedorGrupoHexSem0x;
END;

--------------------------------------------------------------------------------
-- Fonte 2: audit_log direto
-- Usado se a view não existir ou não trouxer linhas; compara alteração do campo
-- de grupo com o destino do fornecedor.
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.audit_log', N'U') IS NOT NULL
BEGIN
    DECLARE @sqlAuditLogGrupo nvarchar(max) = N'
        INSERT INTO #EntradaGrupoCandidato
            (id, entrada_grupo_epoch, prioridade_fonte, fonte_entrada, detalhe_entrada)
        SELECT
            b.id,
            TRY_CONVERT(int, au.change_date) AS entrada_grupo_epoch,
            CONVERT(tinyint, 20) AS prioridade_fonte,
            N''audit_log.group'' AS fonte_entrada,
            CONCAT(
                N''attr_name='', CONVERT(nvarchar(4000), au.attr_name),
                N''; before='', CONVERT(nvarchar(4000), au.attr_before_val),
                N''; after='', CONVERT(nvarchar(4000), au.attr_after_val)
            ) AS detalhe_entrada
        FROM #EscopoIds AS e
        JOIN #Base AS b
            ON b.id = e.id
        JOIN dbo.audit_log AS au
            ON (
                   CONVERT(nvarchar(100), au.audobj_uniqueid) = CONVERT(nvarchar(100), b.id)
                OR CONVERT(nvarchar(100), au.audobj_uniqueid) = CONVERT(nvarchar(100), b.persid)
                OR CONVERT(nvarchar(100), au.audobj_uniqueid) = CONVERT(nvarchar(100), b.ref_num)
                OR CONVERT(nvarchar(100), au.audobj_persid)   = CONVERT(nvarchar(100), b.persid)
                OR CONVERT(nvarchar(100), au.audobj_trkid)    = CONVERT(nvarchar(100), b.ref_num)
            )
        CROSS APPLY (
            SELECT
                attr_name_txt = CONVERT(nvarchar(4000), ISNULL(au.attr_name, N'''')),
                after_val_txt = CONVERT(nvarchar(4000), ISNULL(au.attr_after_val, N''''))
        ) AS av
        WHERE TRY_CONVERT(int, au.change_date) IS NOT NULL
          AND (b.open_date IS NULL OR TRY_CONVERT(int, au.change_date) >= b.open_date)
          AND (b.close_date IS NULL OR TRY_CONVERT(int, au.change_date) <= b.close_date)
          AND (
                 av.attr_name_txt COLLATE Latin1_General_CI_AI IN (N''group'', N''group_id'', N''Grupo'')
              OR av.attr_name_txt COLLATE Latin1_General_CI_AI LIKE N''%group%''
              OR av.attr_name_txt COLLATE Latin1_General_CI_AI LIKE N''%grupo%''
          )
          AND (
                 av.after_val_txt COLLATE Latin1_General_CI_AI LIKE N''%Fornecedores%A2B%''
              OR av.after_val_txt COLLATE Latin1_General_CI_AI LIKE N''%A2B/Protect4%''
              OR av.after_val_txt COLLATE Latin1_General_CI_AI LIKE N''%A2B%Protect4%''
              OR UPPER(av.after_val_txt) LIKE N''%'' + UPPER(@FornecedorGrupoHex) + N''%''
              OR UPPER(av.after_val_txt) LIKE N''%'' + UPPER(@FornecedorGrupoHexSem0x) + N''%''
          );';

    EXEC sp_executesql
        @sqlAuditLogGrupo,
        N'@FornecedorGrupoHex nvarchar(100), @FornecedorGrupoHexSem0x nvarchar(100)',
        @FornecedorGrupoHex = @FornecedorGrupoHex,
        @FornecedorGrupoHexSem0x = @FornecedorGrupoHexSem0x;
END;

--------------------------------------------------------------------------------
-- Fonte 3: act_log textual estrito
-- Fallback. Não usa "para%A2B%" genérico, pois isso captura transferências que
-- não são de grupo. Só entra quando o texto indicar explicitamente GRUPO.
--------------------------------------------------------------------------------
INSERT INTO #EntradaGrupoCandidato
    (id, entrada_grupo_epoch, prioridade_fonte, fonte_entrada, detalhe_entrada)
SELECT
    b.id,
    al.system_time AS entrada_grupo_epoch,
    CONVERT(tinyint, 5) AS prioridade_fonte,
    N'act_log.TR textual exato' AS fonte_entrada,
    LEFT(txt.texto_log, 4000) AS detalhe_entrada
FROM #EscopoIds AS e
JOIN #Base AS b
    ON b.id = e.id
JOIN #LogEscopo AS al
    ON al.call_req_id = b.persid
CROSS APPLY (
    SELECT texto_log =
        CONVERT(nvarchar(max), ISNULL(al.description, N'')) + N' ' +
        CONVERT(nvarchar(max), ISNULL(al.action_desc,  N''))
) AS txt
WHERE al.system_time IS NOT NULL
  AND (b.open_date IS NULL OR al.system_time >= b.open_date)
  AND (b.close_date IS NULL OR al.system_time <= b.close_date)
  AND al.type = 'TR'
  AND (
        txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%Transferir%Grupo%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%Transfer Group%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%Grupo%Transferid%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%Grupo%alterad%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%Group%changed%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%group_id%'
  )
  AND (
        txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%Fornecedores%A2B%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%A2B/Protect4%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%A2B%Protect4%'
     OR UPPER(CONVERT(nvarchar(max), txt.texto_log)) LIKE N'%' + UPPER(@FornecedorGrupoHex) + N'%'
     OR UPPER(CONVERT(nvarchar(max), txt.texto_log)) LIKE N'%' + UPPER(@FornecedorGrupoHexSem0x) + N'%'
  )
  AND (
        txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%para%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%to%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%Novo valor%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%New Value%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%->%'
  );

CREATE INDEX IX_EntradaGrupoCandidato_id_epoch
    ON #EntradaGrupoCandidato(id, prioridade_fonte, entrada_grupo_epoch);

;WITH EscolhaEntrada AS (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY c.id
            ORDER BY c.prioridade_fonte ASC, c.entrada_grupo_epoch DESC
        ) AS rn
    FROM #EntradaGrupoCandidato AS c
)
SELECT
    id,
    entrada_grupo_epoch,
    fonte_entrada,
    detalhe_entrada
INTO #EntradaGrupo
FROM EscolhaEntrada
WHERE rn = 1;

CREATE UNIQUE CLUSTERED INDEX IX_EntradaGrupo_id ON #EntradaGrupo(id);

IF OBJECT_ID('tempdb..#InicioContagemA2B_FARC_P4') IS NOT NULL DROP TABLE #InicioContagemA2B_FARC_P4;

CREATE TABLE #InicioContagemA2B_FARC_P4 (
    id int NOT NULL PRIMARY KEY,
    inicio_contagem_epoch int NULL,
    fonte_inicio_contagem nvarchar(200) NOT NULL,
    detalhe_inicio_contagem nvarchar(4000) COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #InicioContagemA2B_FARC_P4 (id, inicio_contagem_epoch, fonte_inicio_contagem, detalhe_inicio_contagem)
SELECT
    e.id,
    COALESCE(eg.entrada_grupo_epoch, b.open_date) AS inicio_contagem_epoch,
    CASE
        WHEN eg.entrada_grupo_epoch IS NOT NULL
            THEN CONCAT(N'Entrada no grupo fornecedor via ', eg.fonte_entrada)
        WHEN b.open_date IS NOT NULL
            THEN N'Fallback: chamado já no grupo ou sem histórico auditável de grupo'
        ELSE N'Sem início de contagem identificado'
    END AS fonte_inicio_contagem,
    CASE
        WHEN eg.entrada_grupo_epoch IS NOT NULL THEN eg.detalhe_entrada
        ELSE NULL
    END AS detalhe_inicio_contagem
FROM #EscopoIds AS e
JOIN #Base AS b
    ON b.id = e.id
LEFT JOIN #EntradaGrupo AS eg
    ON eg.id = b.id;

IF OBJECT_ID('tempdb..#CapturaStatus') IS NOT NULL DROP TABLE #CapturaStatus;

SELECT
    b.id,
    MIN(al.system_time) AS captura_status_epoch
INTO #CapturaStatus
FROM #EscopoIds AS e
JOIN #Base AS b
    ON b.id = e.id
JOIN #InicioContagemA2B_FARC_P4 AS ic
    ON ic.id = b.id
JOIN #LogEscopo AS al
    ON al.call_req_id = b.persid
CROSS APPLY (
    SELECT texto_log =
        CONVERT(nvarchar(max), ISNULL(al.description, N'')) + N' ' +
        CONVERT(nvarchar(max), ISNULL(al.action_desc,  N''))
) AS txt
WHERE al.system_time IS NOT NULL
  AND ic.inicio_contagem_epoch IS NOT NULL
  AND al.system_time >= ic.inicio_contagem_epoch
  AND al.type = 'ST'
  -- Captura = primeira ida PARA "Em andamento" depois da entrada na A2B.
  -- Não filtra por membro atual do grupo, porque o histórico precisa refletir
  -- o evento do chamado, não a composição atual do grupo.
  -- Importante: não basta o texto conter "Em andamento", pois linhas como
  -- "Em andamento -> Agendado" ou "Em andamento -> Aguarda atendimento"
  -- também contêm esse termo e NÃO são captura.
  AND (
        -- destino EXATO do status = Em andamento.
        -- Não aceitar linhas como: 'Em andamento' para 'Aguarda atendimento'.
        txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%Status alterado de%para ''Em andamento''%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%Status changed from%to ''In Progress''%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%NOVO=''Em andamento''%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%New Value=''In Progress''%'
  )
GROUP BY b.id;

CREATE UNIQUE CLUSTERED INDEX IX_CapturaStatus_id ON #CapturaStatus(id);

-- (Removido: #CapturaAtividadeFornecedor. Era calculado e nunca usado no cálculo
--  final; eliminá-lo tira uma leitura inteira do act_log sem mudar resultado.)

IF OBJECT_ID('tempdb..#Captura') IS NOT NULL DROP TABLE #Captura;

SELECT
    e.id,
    COALESCE(cs.captura_status_epoch, ic.inicio_contagem_epoch) AS captura_epoch,
    CASE
        WHEN cs.captura_status_epoch IS NOT NULL THEN N'ST com destino exato para Em andamento'
        WHEN ic.inicio_contagem_epoch IS NOT NULL THEN N'Fallback: Data Abertura FARC; não houve ST posterior para Em andamento'
        ELSE N'Sem captura identificada'
    END AS fonte_captura
INTO #Captura
FROM #EscopoIds AS e
LEFT JOIN #InicioContagemA2B_FARC_P4 AS ic
    ON ic.id = e.id
LEFT JOIN #CapturaStatus AS cs
    ON cs.id = e.id;

CREATE UNIQUE CLUSTERED INDEX IX_Captura_id ON #Captura(id);

IF OBJECT_ID('tempdb..#Reabertura') IS NOT NULL DROP TABLE #Reabertura;

SELECT DISTINCT
    b.id,
    CAST(1 AS bit) AS houve_reabertura
INTO #Reabertura
FROM #EscopoIds AS e
JOIN #Base AS b
    ON b.id = e.id
JOIN #LogEscopo AS al
    ON al.call_req_id = b.persid
WHERE
    CONVERT(nvarchar(max), ISNULL(al.type, N'')) COLLATE Latin1_General_CI_AI LIKE N'%reab%'
    OR CONVERT(nvarchar(max), ISNULL(al.description, N'')) COLLATE Latin1_General_CI_AI LIKE N'%reabert%'
    OR CONVERT(nvarchar(max), ISNULL(al.action_desc, N'')) COLLATE Latin1_General_CI_AI LIKE N'%reabert%';

CREATE UNIQUE CLUSTERED INDEX IX_Reabertura_id ON #Reabertura(id);

--------------------------------------------------------------------------------
-- [5] Base final com datas em horário do Brasil
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#BaseEscopo_FARC_P4') IS NOT NULL DROP TABLE #BaseEscopo_FARC_P4;

SELECT
    b.*,
    e.FonteFornecedor,
    ic.inicio_contagem_epoch,
    ic.fonte_inicio_contagem,
    ic.detalhe_inicio_contagem,
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
INTO #BaseEscopo_FARC_P4
FROM #EscopoIds AS e
JOIN #Base AS b
    ON b.id = e.id
LEFT JOIN #InicioContagemA2B_FARC_P4 AS ic
    ON ic.id = b.id
LEFT JOIN #Captura AS c
    ON c.id = b.id
LEFT JOIN #Reabertura AS r
    ON r.id = b.id;

CREATE UNIQUE CLUSTERED INDEX IX_BaseEscopo_id ON #BaseEscopo_FARC_P4(id);

--------------------------------------------------------------------------------
-- [6] Fonte de tempo para FARC - regra BO por SLA ativo
--------------------------------------------------------------------------------
-- Regra ajustada para bater com o BO observado no chamado 1693751:
--
--   1) Data Abertura FARC continua sendo a entrada no grupo Fornecedores - A2B.
--   2) Data Captura é a primeira ida PARA "Em andamento" depois da entrada na A2B.
--   3) Tempo de Atendimento FARC é tempo decorrido ATIVO, não time_spent.
--   4) O relógio ativo começa em "Em andamento" e pausa/termina quando o chamado
--      entra em Agendado, Aguarda atendimento, Em homologação, resolução ou fechamento.
--   5) Quando o chamado sai de Agendado e volta para "Em andamento", o relógio retoma.
--   6) A contagem dos trechos ativos respeita a severidade:
--        P1/P2 = corrida
--        P3/P4/P5 = comercial, segunda a sexta, 08:00-20:00.
--
-- Observação: act_log.time_spent não compõe mais o FARC. Ele é mantido apenas
-- para auditoria/comparação.
--------------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#TerminalFARC') IS NOT NULL DROP TABLE #TerminalFARC;

SELECT
    b.id,
    CASE
        WHEN b.resolve_date IS NOT NULL
         AND b.captura_epoch IS NOT NULL
         AND b.resolve_date >= b.captura_epoch
         AND (b.close_date IS NULL OR b.resolve_date <= b.close_date)
            THEN b.resolve_date
        WHEN b.close_date IS NOT NULL THEN b.close_date
        ELSE b.resolve_date
    END AS terminal_epoch,
    CASE
        WHEN b.resolve_date IS NOT NULL
         AND b.captura_epoch IS NOT NULL
         AND b.resolve_date >= b.captura_epoch
         AND (b.close_date IS NULL OR b.resolve_date <= b.close_date)
            THEN N'resolve_date'
        WHEN b.close_date IS NOT NULL THEN N'close_date'
        ELSE N'sem terminal'
    END AS fonte_terminal
INTO #TerminalFARC
FROM #BaseEscopo_FARC_P4 AS b;

CREATE UNIQUE CLUSTERED INDEX IX_TerminalFARC_id ON #TerminalFARC(id);

--------------------------------------------------------------------------------
-- [6.1] Auditoria paralela: soma de time_spent, somente para comparação
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#TempoAtendimentoLog') IS NOT NULL DROP TABLE #TempoAtendimentoLog;

SELECT
    b.id,
    SUM(CASE
            WHEN al.system_time IS NOT NULL
             AND (b.close_date IS NULL OR al.system_time <= b.close_date)
                THEN ISNULL(TRY_CONVERT(int, al.time_spent), 0)
            ELSE 0
        END) AS tempo_atendimento_log_total_seg,
    SUM(CASE
            WHEN al.system_time IS NOT NULL
             AND b.inicio_contagem_epoch IS NOT NULL
             AND al.system_time < b.inicio_contagem_epoch
             AND (b.close_date IS NULL OR al.system_time <= b.close_date)
                THEN ISNULL(TRY_CONVERT(int, al.time_spent), 0)
            ELSE 0
        END) AS tempo_atendimento_descartado_antes_a2b_seg,
    SUM(CASE
            WHEN al.system_time IS NOT NULL
             AND b.inicio_contagem_epoch IS NOT NULL
             AND al.system_time >= b.inicio_contagem_epoch
             AND (b.close_date IS NULL OR al.system_time <= b.close_date)
                THEN ISNULL(TRY_CONVERT(int, al.time_spent), 0)
            ELSE 0
        END) AS tempo_atendimento_log_seg
INTO #TempoAtendimentoLog
FROM #BaseEscopo_FARC_P4 AS b
LEFT JOIN #LogEscopo AS al
    ON al.call_req_id = b.persid
GROUP BY b.id;

CREATE UNIQUE CLUSTERED INDEX IX_TempoAtendimentoLog_id ON #TempoAtendimentoLog(id);

--------------------------------------------------------------------------------
-- [6.3] MOTOR PRINCIPAL: tempo ATIVO somado em TODAS as janelas de posse A2B
--------------------------------------------------------------------------------
-- Regra do BO validada contra os logs detalhados:
--   1) O chamado pode ENTRAR, SAIR e VOLTAR para a posse do grupo A2B várias
--      vezes (reposse). O tempo de atendimento conta a soma do tempo ATIVO em
--      TODAS as janelas em que o A2B teve a posse, não só a última.
--   2) Status que CONTAM como ativo: 'Em andamento' e 'Aberto, aguarda
--      atendimento' (a espera inicial na fila do A2B, antes do primeiro
--      atendimento). Qualquer outro status (Agendado, Aguarda atendimento,
--      Em homologação, Em teste na TI, etc.) NÃO conta.
--   3) Recorte: a soma é cortada no terminal (resolução -> Em homologação; senão
--      Resolvido). Corrida para P1/P2 e comercial 08:00-20:00 seg-sex p/ P3/P4/P5.
--
-- Implementação em três passos: janelas de posse, segmentos de status ativos e
-- a interseção dos dois.
--------------------------------------------------------------------------------

-- [6.3.1] Todas as mudanças de GRUPO (entradas e saídas), com origem e destino.
-- Extrai do texto "... Grupo de '<origem>' para '<destino>' ..." mesmo quando
-- vem combinado com "Transferir Responsável de '...' para '...'": ancora em
-- 'Grupo de' e lê os dois primeiros valores entre aspas após esse ponto.
IF OBJECT_ID('tempdb..#GrupoRaw') IS NOT NULL DROP TABLE #GrupoRaw;
IF OBJECT_ID('tempdb..#GrupoEventos') IS NOT NULL DROP TABLE #GrupoEventos;

-- Passo 1: materializa o texto a partir da ancora 'Grupo de' numa coluna CURTA
-- e BOUNDED (nvarchar(400)). Isso quebra a arvore de expressao e evita o erro
-- "expression services limit" (Msg 8632) que ocorre ao encadear muitos
-- CHARINDEX/SUBSTRING sobre nvarchar(max) num unico SELECT.
SELECT
    b.id,
    al.system_time AS ev_epoch,
    al.log_id,
    CONVERT(nvarchar(400), SUBSTRING(t.txt, a.anchor + 8, 400)) AS resto
INTO #GrupoRaw
FROM #BaseEscopo_FARC_P4 AS b
JOIN #LogEscopo AS al
    ON al.call_req_id = b.persid
CROSS APPLY (
    SELECT txt = CONVERT(nvarchar(max), ISNULL(al.description, N'')) + N' '
              + CONVERT(nvarchar(max), ISNULL(al.action_desc, N''))
) AS t
CROSS APPLY (
    SELECT anchor = CHARINDEX(N'Grupo de', t.txt COLLATE Latin1_General_CI_AI)
) AS a
WHERE al.system_time IS NOT NULL
  AND al.type = 'TR'
  AND a.anchor > 0
  AND (b.close_date IS NULL OR al.system_time <= b.close_date);

CREATE INDEX IX_GrupoRaw_id_epoch ON #GrupoRaw(id, ev_epoch);

-- Passo 2: parsing dos dois primeiros valores entre aspas (origem e destino)
-- sobre a coluna curta 'resto'. Cada operacao e barata.
SELECT
    g.id,
    g.ev_epoch,
    g.log_id,
    CASE WHEN dest.destino LIKE N'%A2B%' THEN 1 ELSE 0 END AS destino_a2b,
    CASE WHEN orig.origem  LIKE N'%A2B%' THEN 1 ELSE 0 END AS origem_a2b
INTO #GrupoEventos
FROM #GrupoRaw AS g
CROSS APPLY (SELECT q1 = CHARINDEX(N'''', g.resto)) AS c1
CROSS APPLY (SELECT q2 = CASE WHEN c1.q1 > 0 THEN CHARINDEX(N'''', g.resto, c1.q1 + 1) ELSE 0 END) AS c2
CROSS APPLY (SELECT origem = CASE WHEN c2.q2 > c1.q1 THEN SUBSTRING(g.resto, c1.q1 + 1, c2.q2 - c1.q1 - 1) ELSE N'' END) AS orig
CROSS APPLY (
    SELECT ppos = CASE
        WHEN c2.q2 > 0 AND CHARINDEX(N' para ', g.resto COLLATE Latin1_General_CI_AI, c2.q2) > 0
            THEN CHARINDEX(N' para ', g.resto COLLATE Latin1_General_CI_AI, c2.q2)
        WHEN c2.q2 > 0 THEN CHARINDEX(N' to ', g.resto COLLATE Latin1_General_CI_AI, c2.q2)
        ELSE 0 END
) AS pp
CROSS APPLY (SELECT q3 = CASE WHEN pp.ppos > 0 THEN CHARINDEX(N'''', g.resto, pp.ppos) ELSE 0 END) AS c3
CROSS APPLY (SELECT q4 = CASE WHEN c3.q3 > 0 THEN CHARINDEX(N'''', g.resto, c3.q3 + 1) ELSE 0 END) AS c4
CROSS APPLY (SELECT destino = CASE WHEN c4.q4 > c3.q3 THEN SUBSTRING(g.resto, c3.q3 + 1, c4.q4 - c3.q3 - 1) ELSE N'' END) AS dest;

CREATE INDEX IX_GrupoEventos_id_epoch ON #GrupoEventos(id, ev_epoch);

-- [6.3.2] Estado de grupo inicial do chamado (na criação).
-- Se houve mudança de grupo, o estado inicial é a ORIGEM da primeira mudança.
-- Se não houve nenhuma mudança de grupo e a categoria é A2B, nasceu no A2B.
IF OBJECT_ID('tempdb..#GrupoInicial') IS NOT NULL DROP TABLE #GrupoInicial;
SELECT
    b.id,
    b.open_date AS t_inicial,
    CASE
        WHEN ge1.origem_a2b IS NOT NULL THEN ge1.origem_a2b
        WHEN b.categoria_sym COLLATE Latin1_General_CI_AI LIKE N'A2B.%' THEN 1
        ELSE 0
    END AS inicial_a2b
INTO #GrupoInicial
FROM #BaseEscopo_FARC_P4 AS b
OUTER APPLY (
    SELECT TOP (1) g.origem_a2b
    FROM #GrupoEventos AS g
    WHERE g.id = b.id
    -- log_id so decide quando segundo e destino_a2b empatam; ver DESEMPATE POR act_log.id
    ORDER BY g.ev_epoch ASC, g.destino_a2b DESC, g.log_id ASC
) AS ge1;

CREATE UNIQUE CLUSTERED INDEX IX_GrupoInicial_id ON #GrupoInicial(id);

-- [6.3.3] Janelas de posse A2B: ilhas em que o grupo vigente é A2B.
-- A linha de tempo de grupo = estado inicial (open_date) + cada mudança de grupo.
-- O grupo de cada trecho vale até a próxima mudança (ou até o terminal).
-- Mantém só os trechos A2B, recortados no terminal. Trechos da timeline já são
-- disjuntos, então não há sobreposição/duplicidade.
IF OBJECT_ID('tempdb..#JanelasA2B') IS NOT NULL DROP TABLE #JanelasA2B;
;WITH timeline AS (
    SELECT id, t_inicial AS t, inicial_a2b AS is_a2b, CONVERT(tinyint, 0) AS ord, CONVERT(int, 0) AS log_id
    FROM #GrupoInicial
    UNION ALL
    SELECT id, ev_epoch AS t, destino_a2b AS is_a2b, CONVERT(tinyint, 1) AS ord, log_id
    FROM #GrupoEventos
),
ordered AS (
    SELECT
        id, t, is_a2b,
        -- log_id: dois eventos de grupo no mesmo segundo (ver DESEMPATE POR act_log.id)
        LEAD(t) OVER (PARTITION BY id ORDER BY t ASC, ord ASC, log_id ASC) AS next_t
    FROM timeline
)
SELECT
    o.id,
    o.t AS win_inicio_epoch,
    CASE WHEN COALESCE(o.next_t, tf.terminal_epoch) > tf.terminal_epoch
         THEN tf.terminal_epoch ELSE COALESCE(o.next_t, tf.terminal_epoch) END AS win_fim_epoch
INTO #JanelasA2B
FROM ordered AS o
JOIN #TerminalFARC AS tf
    ON tf.id = o.id
WHERE o.is_a2b = 1
  AND tf.terminal_epoch IS NOT NULL
  AND o.t < tf.terminal_epoch
  AND (CASE WHEN COALESCE(o.next_t, tf.terminal_epoch) > tf.terminal_epoch
            THEN tf.terminal_epoch ELSE COALESCE(o.next_t, tf.terminal_epoch) END) > o.t;

CREATE INDEX IX_JanelasA2B_id ON #JanelasA2B(id, win_inicio_epoch);

-- [6.3.4] Eventos de STATUS com origem e destino, marcando os ativos.
-- Ativo = destino 'Em andamento' ou 'Aberto, aguarda atendimento'.
-- Atenção: 'Aberto, aguarda atendimento' (fila inicial) é ativo; 'Aguarda
-- atendimento' (espera pós-trabalho) NÃO é. O padrão usa o prefixo 'Aberto'.
IF OBJECT_ID('tempdb..#StatusRaw') IS NOT NULL DROP TABLE #StatusRaw;
IF OBJECT_ID('tempdb..#StatusEvA2B') IS NOT NULL DROP TABLE #StatusEvA2B;

-- Passo 1: materializa, a partir da ancora 'alterado de'/'changed from', uma
-- coluna CURTA e BOUNDED com origem e destino. Evita o erro Msg 8632
-- (expression services limit) que ocorria ao encadear muitos CHARINDEX/SUBSTRING
-- sobre nvarchar(max) num unico SELECT (era a causa do erro na linha do #StatusEvA2B).
SELECT
    b.id,
    al.system_time AS ev_epoch,
    al.log_id,
    CONVERT(nvarchar(400), SUBSTRING(t.txt, a.anchor, 400)) AS resto
INTO #StatusRaw
FROM #BaseEscopo_FARC_P4 AS b
JOIN #LogEscopo AS al
    ON al.call_req_id = b.persid
CROSS APPLY (
    SELECT txt = CONVERT(nvarchar(max), ISNULL(al.description, N'')) + N' '
              + CONVERT(nvarchar(max), ISNULL(al.action_desc, N''))
) AS t
CROSS APPLY (
    SELECT anchor = CASE
        WHEN CHARINDEX(N'alterado de', t.txt COLLATE Latin1_General_CI_AI) > 0
            THEN CHARINDEX(N'alterado de', t.txt COLLATE Latin1_General_CI_AI) + 11
        WHEN CHARINDEX(N'changed from', t.txt COLLATE Latin1_General_CI_AI) > 0
            THEN CHARINDEX(N'changed from', t.txt COLLATE Latin1_General_CI_AI) + 12
        ELSE 0 END
) AS a
WHERE al.system_time IS NOT NULL
  AND a.anchor > 0
  AND (b.close_date IS NULL OR al.system_time <= b.close_date);

CREATE INDEX IX_StatusRaw_id_epoch ON #StatusRaw(id, ev_epoch);

-- Passo 2: parsing de origem e destino sobre a coluna curta, e marcacao do que
-- e ATIVO ('Em andamento' / 'In Progress' / 'Aberto, aguarda atendimento').
SELECT
    s.id,
    s.ev_epoch,
    s.log_id,
    CASE
        WHEN dest.destino COLLATE Latin1_General_CI_AI = N'Em andamento'
          OR dest.destino COLLATE Latin1_General_CI_AI = N'In Progress'
          OR dest.destino COLLATE Latin1_General_CI_AI LIKE N'Aberto%aguarda%atendimento%'
          -- Reaberto conta como atendimento (orientacao do gerente, 2026-10-06).
          OR dest.destino COLLATE Latin1_General_CI_AI = N'Reaberto'
          OR dest.destino COLLATE Latin1_General_CI_AI = N'Reopened'
            THEN 1 ELSE 0
    END AS destino_ativo,
    CASE
        WHEN orig.origem COLLATE Latin1_General_CI_AI = N'Em andamento'
          OR orig.origem COLLATE Latin1_General_CI_AI = N'In Progress'
          OR orig.origem COLLATE Latin1_General_CI_AI LIKE N'Aberto%aguarda%atendimento%'
          OR orig.origem COLLATE Latin1_General_CI_AI = N'Reaberto'
          OR orig.origem COLLATE Latin1_General_CI_AI = N'Reopened'
            THEN 1 ELSE 0
    END AS origem_ativo,
    -- Marca se o status ativo e a FILA 'Aberto, aguarda atendimento' (espera que
    -- viaja com o chamado e conta ao entrar na A2B) em vez de 'Em andamento'
    -- (trabalho que pertence a quem estava executando). Usado para nao contar
    -- 'Em andamento' herdado de outro grupo no instante da entrada na A2B.
    CASE WHEN dest.destino COLLATE Latin1_General_CI_AI LIKE N'Aberto%aguarda%atendimento%'
         THEN 1 ELSE 0 END AS destino_aberto,
    CASE WHEN orig.origem COLLATE Latin1_General_CI_AI LIKE N'Aberto%aguarda%atendimento%'
         THEN 1 ELSE 0 END AS origem_aberto
INTO #StatusEvA2B
FROM #StatusRaw AS s
CROSS APPLY (SELECT q1 = CHARINDEX(N'''', s.resto)) AS c1
CROSS APPLY (SELECT q2 = CASE WHEN c1.q1 > 0 THEN CHARINDEX(N'''', s.resto, c1.q1 + 1) ELSE 0 END) AS c2
CROSS APPLY (SELECT origem = CASE WHEN c2.q2 > c1.q1 THEN SUBSTRING(s.resto, c1.q1 + 1, c2.q2 - c1.q1 - 1) ELSE N'' END) AS orig
CROSS APPLY (
    SELECT ppos = CASE
        WHEN c2.q2 > 0 AND CHARINDEX(N' para ', s.resto COLLATE Latin1_General_CI_AI, c2.q2) > 0
            THEN CHARINDEX(N' para ', s.resto COLLATE Latin1_General_CI_AI, c2.q2)
        WHEN c2.q2 > 0 THEN CHARINDEX(N' to ', s.resto COLLATE Latin1_General_CI_AI, c2.q2)
        ELSE 0 END
) AS pp
CROSS APPLY (SELECT q3 = CASE WHEN pp.ppos > 0 THEN CHARINDEX(N'''', s.resto, pp.ppos) ELSE 0 END) AS c3
CROSS APPLY (SELECT q4 = CASE WHEN c3.q3 > 0 THEN CHARINDEX(N'''', s.resto, c3.q3 + 1) ELSE 0 END) AS c4
CROSS APPLY (SELECT destino = CASE WHEN c4.q4 > c3.q3 THEN SUBSTRING(s.resto, c3.q3 + 1, c4.q4 - c3.q3 - 1) ELSE N'' END) AS dest;

-- SOLN seguido de reabertura (2026-10-06): quando o proximo evento de status
-- depois do SOLN e a ida para 'Reaberto' (RO), o trecho SOLN -> RO e periodo
-- resolvido e nao conta; o 'Reaberto' volta a contar. So esses SOLN entram como
-- pausa: SOLN sem reabertura seguinte nao muda a linha de status.
IF OBJECT_ID('tempdb..#SolnReaberturaA2B') IS NOT NULL DROP TABLE #SolnReaberturaA2B;
SELECT
    b.id,
    al.system_time AS ev_epoch,
    al.log_id
INTO #SolnReaberturaA2B
FROM #BaseEscopo_FARC_P4 AS b
JOIN #LogEscopo AS al
    ON al.call_req_id = b.persid
CROSS APPLY (
    SELECT TOP (1) s.resto
    FROM #StatusRaw AS s
    WHERE s.id = b.id
      AND (s.ev_epoch > al.system_time
           OR (s.ev_epoch = al.system_time AND s.log_id > al.log_id))
    ORDER BY s.ev_epoch, s.log_id
) AS prox
WHERE al.system_time IS NOT NULL
  AND al.[type] = 'SOLN'
  AND (b.close_date IS NULL OR al.system_time <= b.close_date)
  AND (   prox.resto COLLATE Latin1_General_CI_AI LIKE N'%para ''Reaberto''%'
       OR prox.resto COLLATE Latin1_General_CI_AI LIKE N'%to ''Reopened''%');

-- Origem tratada como a fila inicial, so para o raro caso de o SOLN ser o 1o
-- evento de status.
INSERT INTO #StatusEvA2B (id, ev_epoch, log_id, destino_ativo, origem_ativo, destino_aberto, origem_aberto)
SELECT sr.id, sr.ev_epoch, sr.log_id, 0, 1, 0, 1
FROM #SolnReaberturaA2B AS sr;

CREATE INDEX IX_StatusEvA2B_id_epoch ON #StatusEvA2B(id, ev_epoch);

-- [6.3.5] Segmentos de status ATIVOS (em epoch), recortados no terminal.
-- Inclui o segmento inicial [open_date, primeiro evento de status] cujo status é
-- a ORIGEM do primeiro evento (status de criação). Para chamados sem nenhum
-- evento de status, o segmento é [open_date, terminal] com o status de criação
-- 'Aberto, aguarda atendimento' (ativo).
IF OBJECT_ID('tempdb..#SegAtivoA2B') IS NOT NULL DROP TABLE #SegAtivoA2B;
;WITH ev AS (
    SELECT
        -- DESEMPATE POR act_log.id (2026-09-18). O SDM grava o tempo em SEGUNDOS
        -- inteiros e a automacao registra rajadas de mudanca de status no mesmo
        -- segundo. Ordenar so pelo segundo deixava a ordem da rajada a criterio do
        -- SQL Server, e o FARC variava de uma execucao para outra. act_log.id e a
        -- sequencia de gravacao: na ordem (segundo, id) a cadeia origem->destino fica
        -- consistente em 16.114 de 16.115 pares medidos.
        id, ev_epoch, destino_ativo, destino_aberto,
        LEAD(ev_epoch) OVER (PARTITION BY id ORDER BY ev_epoch, log_id) AS prox
    FROM #StatusEvA2B
),
prim AS (
    SELECT id, MIN(ev_epoch) AS primeiro_epoch FROM #StatusEvA2B GROUP BY id
),
prim_orig AS (
    SELECT se.id, se.origem_ativo, se.origem_aberto
    FROM #StatusEvA2B AS se
    JOIN prim AS p ON p.id = se.id AND p.primeiro_epoch = se.ev_epoch
),
seg AS (
    -- segmentos a partir de cada evento (status de destino vale até o próximo)
    SELECT e.id, e.ev_epoch AS ini, COALESCE(e.prox, tf.terminal_epoch) AS fim,
           e.destino_ativo AS ativo, e.destino_aberto AS aberto_fila
    FROM ev AS e
    JOIN #TerminalFARC AS tf ON tf.id = e.id

    UNION ALL

    -- segmento inicial (criação -> primeiro evento), status = origem do 1o evento
    SELECT b.id, b.open_date AS ini, p.primeiro_epoch AS fim,
           MAX(po.origem_ativo) AS ativo, MAX(po.origem_aberto) AS aberto_fila
    FROM #BaseEscopo_FARC_P4 AS b
    JOIN prim AS p ON p.id = b.id
    JOIN prim_orig AS po ON po.id = b.id
    WHERE b.open_date IS NOT NULL
    GROUP BY b.id, b.open_date, p.primeiro_epoch

    UNION ALL

    -- chamados sem nenhum evento de status: status de criação o tempo todo.
    -- Criação = 'Aberto, aguarda atendimento' (fila), logo aberto_fila = 1.
    SELECT b.id, b.open_date AS ini, tf.terminal_epoch AS fim, CONVERT(int, 1) AS ativo,
           CONVERT(int, 1) AS aberto_fila
    FROM #BaseEscopo_FARC_P4 AS b
    JOIN #TerminalFARC AS tf ON tf.id = b.id
    WHERE b.open_date IS NOT NULL
      AND tf.terminal_epoch IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM #StatusEvA2B AS se WHERE se.id = b.id)
)
SELECT
    s.id,
    s.ini,
    CASE WHEN s.fim > tf.terminal_epoch THEN tf.terminal_epoch ELSE s.fim END AS fim,
    s.aberto_fila
INTO #SegAtivoA2B
FROM seg AS s
JOIN #TerminalFARC AS tf ON tf.id = s.id
WHERE s.ativo = 1
  AND tf.terminal_epoch IS NOT NULL
  AND (CASE WHEN s.fim > tf.terminal_epoch THEN tf.terminal_epoch ELSE s.fim END) > s.ini;

CREATE INDEX IX_SegAtivoA2B_id ON #SegAtivoA2B(id, ini);

-- [6.3.5b] Piso do Inicial/Criacao.
-- O BO desconta o "Tempo Gasto" lancado no evento de criacao (Inicial). Esse
-- tempo representa o processamento/fila inicial que o BO nao conta como
-- atendimento. Aqui materializamos o piso = open_date + tempo_gasto_do_Inicial.
-- A contagem ativa nunca comeca antes desse piso. Para chamados que entraram na
-- A2B por transferencia, o piso fica antes da janela A2B e nao tem efeito; so
-- afeta os que nasceram na A2B (janela comeca na criacao), cortando o pedaco
-- inicial exatamente como o BO. init_gasto = maior time_spent entre os eventos
-- de act_log no instante da criacao (system_time = open_date).
IF OBJECT_ID('tempdb..#PisoInicial') IS NOT NULL DROP TABLE #PisoInicial;
SELECT
    b.id,
    b.open_date + ISNULL(ig.init_gasto_seg, 0) AS piso_inicial_epoch
INTO #PisoInicial
FROM #BaseEscopo_FARC_P4 AS b
OUTER APPLY (
    SELECT init_gasto_seg = MAX(TRY_CONVERT(int, al.time_spent))
    FROM #LogEscopo AS al
    WHERE al.call_req_id = b.persid
      AND al.system_time = b.open_date
) AS ig
WHERE b.open_date IS NOT NULL;

CREATE UNIQUE CLUSTERED INDEX IX_PisoInicial_id ON #PisoInicial(id);

-- [6.3.6] Interseção dos segmentos ativos com as janelas de posse A2B, em
-- horário do Brasil. Cada peça é um trecho realmente contado.
IF OBJECT_ID('tempdb..#PecasAtivasA2B') IS NOT NULL DROP TABLE #PecasAtivasA2B;
SELECT
    s.id,
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, ov.ini_ep, @Epoch)) AS inicio_br,
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, ov.fim_ep, @Epoch)) AS fim_br
INTO #PecasAtivasA2B
FROM #SegAtivoA2B AS s
JOIN #JanelasA2B AS j
    ON j.id = s.id
LEFT JOIN #PisoInicial AS pi
    ON pi.id = s.id
CROSS APPLY (
    -- inicio da janela elevado pelo piso do Inicial (criacao + Tempo Gasto da
    -- criacao). So afeta quem nasceu na A2B; transferidos ja comecam depois.
    SELECT win_ini_aj = CASE
        WHEN ISNULL(pi.piso_inicial_epoch, j.win_inicio_epoch) > j.win_inicio_epoch
        THEN ISNULL(pi.piso_inicial_epoch, j.win_inicio_epoch)
        ELSE j.win_inicio_epoch
    END
) AS aj
CROSS APPLY (
    SELECT
        ini_ep = CASE WHEN s.ini > aj.win_ini_aj THEN s.ini ELSE aj.win_ini_aj END,
        fim_ep = CASE WHEN s.fim < j.win_fim_epoch THEN s.fim ELSE j.win_fim_epoch END
) AS ov
WHERE ov.fim_ep > ov.ini_ep
  -- Regra do herdado: a FILA 'Aberto, aguarda atendimento' (aberto_fila = 1)
  -- conta normalmente ao entrar na A2B, pois e espera que viaja com o chamado.
  -- Ja um 'Em andamento' (aberto_fila = 0) so conta se tiver COMECADO dentro da
  -- janela de posse A2B (s.ini >= win_inicio). Se o 'Em andamento' ja estava
  -- ligado ANTES da entrada (herdado de outro grupo/analista), nao conta o
  -- trecho ate a A2B assumir de fato. Corrige casos como o 1683467.
  AND (s.aberto_fila = 1 OR s.ini >= j.win_inicio_epoch);

CREATE INDEX IX_PecasAtivasA2B_id ON #PecasAtivasA2B(id);

--------------------------------------------------------------------------------
-- [7] Números para cálculo de horas comerciais 08:00-20:00, segunda a sexta
--------------------------------------------------------------------------------
DECLARE @MaxDiasFARC int =
(
    SELECT ISNULL(MAX(q.dias), 0)
    FROM (
        SELECT
            dias = CASE
                WHEN b.data_abertura_br IS NOT NULL
                 AND b.data_fechamento_br IS NOT NULL
                 AND b.data_fechamento_br >= b.data_abertura_br
                THEN DATEDIFF(DAY, CAST(b.data_abertura_br AS date), CAST(b.data_fechamento_br AS date))
                ELSE 0
            END
        FROM #BaseEscopo_FARC_P4 AS b

        UNION ALL

        SELECT
            dias = CASE
                WHEN p.inicio_br IS NOT NULL
                 AND p.fim_br IS NOT NULL
                 AND p.fim_br >= p.inicio_br
                THEN DATEDIFF(DAY, CAST(p.inicio_br AS date), CAST(p.fim_br AS date))
                ELSE 0
            END
        FROM #PecasAtivasA2B AS p
    ) AS q
);

IF OBJECT_ID('tempdb..#Nums') IS NOT NULL DROP TABLE #Nums;
CREATE TABLE #Nums (n int NOT NULL PRIMARY KEY);

INSERT INTO #Nums(n)
SELECT TOP (@MaxDiasFARC + 1)
       ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1
FROM sys.all_objects a
CROSS JOIN sys.all_objects b;

--------------------------------------------------------------------------------
-- [7.1] MOTOR PRINCIPAL (cont.): soma das peças ativas por janela A2B com regra
--       corrida (P1/P2) ou comercial 08:00-20:00 seg-sex (P3/P4/P5).
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#TempoAtivoJanelasA2B') IS NOT NULL DROP TABLE #TempoAtivoJanelasA2B;

SELECT
    b.id,
    CASE
        WHEN t.terminal_epoch IS NULL THEN NULL
        ELSE COALESCE(SUM(CASE
            WHEN sl.tipo_resolucao = 'CORRIDA'
                THEN DATEDIFF(SECOND, p.inicio_br, p.fim_br)
            WHEN sl.tipo_resolucao = 'COMERCIAL'
                THEN COALESCE(bh.segundos_comerciais, 0)
            ELSE DATEDIFF(SECOND, p.inicio_br, p.fim_br)
        END), 0)
    END AS tempo_ativo_janelas_a2b_seg
INTO #TempoAtivoJanelasA2B
FROM #BaseEscopo_FARC_P4 AS b
LEFT JOIN #SLA_FARC_P4 AS sl
    ON sl.prioridade = b.prioridade_nivel
LEFT JOIN #TerminalFARC AS t
    ON t.id = b.id
LEFT JOIN #PecasAtivasA2B AS p
    ON p.id = b.id
OUTER APPLY (
    SELECT segundos_comerciais = COALESCE(SUM(x.segundos_dia), 0)
    FROM (
        SELECT segundos_dia = CASE WHEN janela.fim_calc > janela.ini_calc
                    THEN DATEDIFF(SECOND, janela.ini_calc, janela.fim_calc) ELSE 0 END
        FROM (
            SELECT DATEADD(DAY, n.n, CAST(p.inicio_br AS date)) AS dt
            FROM #Nums AS n
            WHERE p.inicio_br IS NOT NULL AND p.fim_br IS NOT NULL
              AND p.fim_br >= p.inicio_br
              AND n.n <= DATEDIFF(DAY, CAST(p.inicio_br AS date), CAST(p.fim_br AS date))
        ) AS dias
        CROSS APPLY (
            SELECT inicio_janela = DATEADD(HOUR, 8,  CAST(dias.dt AS datetime2(0))),
                   fim_janela    = DATEADD(HOUR, 20, CAST(dias.dt AS datetime2(0)))
        ) AS h
        CROSS APPLY (
            SELECT ini_calc = CASE WHEN p.inicio_br > h.inicio_janela THEN p.inicio_br ELSE h.inicio_janela END,
                   fim_calc = CASE WHEN p.fim_br    < h.fim_janela    THEN p.fim_br    ELSE h.fim_janela    END
        ) AS janela
        WHERE DATEDIFF(DAY, '19000101', dias.dt) % 7 BETWEEN 0 AND 4
          AND NOT EXISTS (SELECT 1 FROM #FeriadosFixos ff
                          WHERE ff.mes_dia = RIGHT(CONVERT(char(10), dias.dt, 120), 5))
          AND NOT EXISTS (SELECT 1 FROM #FeriadosPorData fp
                          WHERE fp.data = CAST(dias.dt AS date))
    ) AS x
) AS bh
GROUP BY b.id, t.terminal_epoch;

CREATE UNIQUE CLUSTERED INDEX IX_TempoAtivoJanelasA2B_id ON #TempoAtivoJanelasA2B(id);

--------------------------------------------------------------------------------
-- [8A] Tempo de rotinas operacionais por intervalo de abertura -> fechamento
--------------------------------------------------------------------------------
-- O BO não trata algumas rotinas como fluxo de status. Para elas, o tempo de
-- atendimento é o intervalo entre Data Abertura FARC e Data de Fechamento,
-- com recorte comercial quando a severidade usa SLA comercial.
-- Exemplos cobertos:
--   - A2B.Realizar - Passagem de turno
--   - A2B.Job Summary Report
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#TempoAtendimentoRotina') IS NOT NULL DROP TABLE #TempoAtendimentoRotina;

SELECT
    b.id,
    CASE
        WHEN b.data_abertura_br IS NULL
          OR b.data_fechamento_br IS NULL
          OR b.data_fechamento_br < b.data_abertura_br
            THEN NULL
        WHEN sl.tipo_resolucao = 'CORRIDA'
            THEN DATEDIFF(SECOND, b.data_abertura_br, b.data_fechamento_br)
        WHEN sl.tipo_resolucao = 'COMERCIAL'
            THEN COALESCE(bh.segundos_comerciais, 0)
        ELSE NULL
    END AS tempo_atendimento_rotina_seg
INTO #TempoAtendimentoRotina
FROM #BaseEscopo_FARC_P4 AS b
LEFT JOIN #SLA_FARC_P4 AS sl
    ON sl.prioridade = b.prioridade_nivel
OUTER APPLY (
    SELECT
        segundos_comerciais = COALESCE(SUM(x.segundos_dia), 0)
    FROM (
        SELECT
            segundos_dia = CASE
                WHEN janela.fim_calc > janela.ini_calc
                    THEN DATEDIFF(SECOND, janela.ini_calc, janela.fim_calc)
                ELSE 0
            END
        FROM (
            SELECT DATEADD(DAY, n.n, CAST(b.data_abertura_br AS date)) AS dt
            FROM #Nums AS n
            WHERE b.data_abertura_br IS NOT NULL
              AND b.data_fechamento_br IS NOT NULL
              AND b.data_fechamento_br >= b.data_abertura_br
              AND n.n <= DATEDIFF(DAY, CAST(b.data_abertura_br AS date), CAST(b.data_fechamento_br AS date))
        ) AS dias
        CROSS APPLY (
            SELECT
                inicio_janela = DATEADD(HOUR, 8,  CAST(dias.dt AS datetime2(0))),
                fim_janela    = DATEADD(HOUR, 20, CAST(dias.dt AS datetime2(0)))
        ) AS h
        CROSS APPLY (
            SELECT
                ini_calc = CASE WHEN b.data_abertura_br   > h.inicio_janela THEN b.data_abertura_br   ELSE h.inicio_janela END,
                fim_calc = CASE WHEN b.data_fechamento_br < h.fim_janela    THEN b.data_fechamento_br ELSE h.fim_janela    END
        ) AS janela
        WHERE DATEDIFF(DAY, '19000101', dias.dt) % 7 BETWEEN 0 AND 4
          AND NOT EXISTS (SELECT 1 FROM #FeriadosFixos ff
                          WHERE ff.mes_dia = RIGHT(CONVERT(char(10), dias.dt, 120), 5))
          AND NOT EXISTS (SELECT 1 FROM #FeriadosPorData fp
                          WHERE fp.data = CAST(dias.dt AS date))
    ) AS x
) AS bh;

CREATE UNIQUE CLUSTERED INDEX IX_TempoAtendimentoRotina_id ON #TempoAtendimentoRotina(id);

--------------------------------------------------------------------------------
-- [8B] Motor legado por mudança de status via LEAD
--------------------------------------------------------------------------------
-- Este e o motor base dos chamados nao-rotina (motor unico). Caracteristicas:
--   - considera todos os eventos de status em sequência;
--   - conta cada trecho cujo status de destino é "Em andamento" até o próximo
--     evento de status;
--   - usa tempo corrido no trecho, sem recorte comercial;
--   - recorta no intervalo [Data Abertura FARC, fechamento].
--
-- No calculo final ele e combinado (max) com o tempo ativo nas janelas A2B.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#StatusEventosLead') IS NOT NULL DROP TABLE #StatusEventosLead;

;WITH ev AS (
    SELECT
        b.id,
        al.system_time AS ev_epoch,
        al.log_id,
        CASE
            WHEN CONVERT(nvarchar(max), ISNULL(al.description, N'')) COLLATE Latin1_General_CI_AI LIKE N'%para ''Em andamento''%'
              OR CONVERT(nvarchar(max), ISNULL(al.action_desc,  N'')) COLLATE Latin1_General_CI_AI LIKE N'%para ''Em andamento''%'
              OR CONVERT(nvarchar(max), ISNULL(al.description, N'')) COLLATE Latin1_General_CI_AI LIKE N'%to ''In Progress''%'
              OR CONVERT(nvarchar(max), ISNULL(al.action_desc,  N'')) COLLATE Latin1_General_CI_AI LIKE N'%to ''In Progress''%'
              -- Reaberto conta como atendimento (orientacao do gerente, 2026-10-06).
              OR CONVERT(nvarchar(max), ISNULL(al.description, N'')) COLLATE Latin1_General_CI_AI LIKE N'%para ''Reaberto''%'
              OR CONVERT(nvarchar(max), ISNULL(al.action_desc,  N'')) COLLATE Latin1_General_CI_AI LIKE N'%para ''Reaberto''%'
              OR CONVERT(nvarchar(max), ISNULL(al.description, N'')) COLLATE Latin1_General_CI_AI LIKE N'%to ''Reopened''%'
              OR CONVERT(nvarchar(max), ISNULL(al.action_desc,  N'')) COLLATE Latin1_General_CI_AI LIKE N'%to ''Reopened''%'
            THEN 1 ELSE 0
        END AS is_em_andamento
    FROM #BaseEscopo_FARC_P4 AS b
    JOIN #LogEscopo AS al
        ON al.call_req_id = b.persid
    WHERE al.system_time IS NOT NULL
      AND al.system_time >= ISNULL(b.inicio_contagem_epoch, al.system_time)
      AND (b.close_date IS NULL OR al.system_time <= b.close_date)
      AND (
            CONVERT(nvarchar(max), ISNULL(al.description, N'')) COLLATE Latin1_General_CI_AI LIKE N'%Status alterado%para %'
         OR CONVERT(nvarchar(max), ISNULL(al.action_desc,  N'')) COLLATE Latin1_General_CI_AI LIKE N'%Status alterado%para %'
         OR CONVERT(nvarchar(max), ISNULL(al.description, N'')) COLLATE Latin1_General_CI_AI LIKE N'%Status changed%to %'
      )

    UNION ALL

    -- SOLN seguido de reabertura (2026-10-06): pausa ate o RO (ver [6.3.4]).
    SELECT
        sr.id,
        sr.ev_epoch,
        sr.log_id,
        0 AS is_em_andamento
    FROM #SolnReaberturaA2B AS sr
    JOIN #BaseEscopo_FARC_P4 AS b
        ON b.id = sr.id
    WHERE sr.ev_epoch >= ISNULL(b.inicio_contagem_epoch, sr.ev_epoch)
      AND (b.close_date IS NULL OR sr.ev_epoch <= b.close_date)
)
SELECT
    id,
    ev_epoch,
    is_em_andamento,
    -- log_id: rajadas de status no mesmo segundo (ver DESEMPATE POR act_log.id)
    LEAD(ev_epoch) OVER (PARTITION BY id ORDER BY ev_epoch, log_id) AS prox_epoch
INTO #StatusEventosLead
FROM ev;

CREATE INDEX IX_StatusEventosLead_id_epoch ON #StatusEventosLead(id, ev_epoch);

-- Intervalos em 'Em andamento' (motor LEAD) em horario do Brasil, recortados a
-- [inicio_contagem, fechamento]. Materializados para permitir a janela comercial.
IF OBJECT_ID('tempdb..#IntervalosLead') IS NOT NULL DROP TABLE #IntervalosLead;
SELECT
    b.id,
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, ov.ini_ep, @Epoch)) AS inicio_br,
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, ov.fim_ep, @Epoch)) AS fim_br
INTO #IntervalosLead
FROM #BaseEscopo_FARC_P4 AS b
JOIN #StatusEventosLead AS se
    ON se.id = b.id
CROSS APPLY (
    SELECT
        ini = CASE WHEN se.ev_epoch > b.inicio_contagem_epoch
                   THEN se.ev_epoch ELSE b.inicio_contagem_epoch END,
        fim = CASE WHEN ISNULL(se.prox_epoch, b.close_date) < b.close_date
                   THEN ISNULL(se.prox_epoch, b.close_date) ELSE b.close_date END
) AS clip
JOIN #JanelasA2B AS j
    ON j.id = b.id
CROSS APPLY (
    -- Recorte por janela: so conta o 'Em andamento' que cai DENTRO de uma janela
    -- de posse A2B, igual ao #PecasAtivasA2B. 'Em andamento' sob outro grupo
    -- (fora das janelas) nao entra no Tempo de Atendimento da A2B.
    SELECT
        ini_ep = CASE WHEN clip.ini > j.win_inicio_epoch THEN clip.ini ELSE j.win_inicio_epoch END,
        fim_ep = CASE WHEN clip.fim < j.win_fim_epoch    THEN clip.fim    ELSE j.win_fim_epoch    END
) AS ov
WHERE se.is_em_andamento = 1
  AND b.inicio_contagem_epoch IS NOT NULL
  AND b.close_date IS NOT NULL
  AND ov.fim_ep > ov.ini_ep;
CREATE INDEX IX_IntervalosLead_id ON #IntervalosLead(id);

-- Soma do motor LEAD com a MESMA regra do v10: corrido para P1/P2 e recorte
-- comercial 08:00-20:00 seg-sex para P3/P4/P5. Antes era sempre corrido, o que
-- superestimava incidentes comerciais com trechos fora da janela (ex. 1680955:
-- corrido 0:32:03 vs BO 0:26:20, que e o recorte comercial).
IF OBJECT_ID('tempdb..#TempoAtendimentoStatusLead') IS NOT NULL DROP TABLE #TempoAtendimentoStatusLead;
SELECT
    b.id,
    COALESCE(SUM(CASE
        WHEN sl.tipo_resolucao = 'CORRIDA'
            THEN DATEDIFF(SECOND, il.inicio_br, il.fim_br)
        WHEN sl.tipo_resolucao = 'COMERCIAL'
            THEN COALESCE(bh.segundos_comerciais, 0)
        ELSE DATEDIFF(SECOND, il.inicio_br, il.fim_br)
    END), 0) AS tempo_atendimento_status_lead_seg
INTO #TempoAtendimentoStatusLead
FROM #BaseEscopo_FARC_P4 AS b
LEFT JOIN #SLA_FARC_P4 AS sl
    ON sl.prioridade = b.prioridade_nivel
LEFT JOIN #IntervalosLead AS il
    ON il.id = b.id
OUTER APPLY (
    SELECT segundos_comerciais = COALESCE(SUM(x.segundos_dia), 0)
    FROM (
        SELECT segundos_dia = CASE WHEN janela.fim_calc > janela.ini_calc
                    THEN DATEDIFF(SECOND, janela.ini_calc, janela.fim_calc) ELSE 0 END
        FROM (
            SELECT DATEADD(DAY, n.n, CAST(il.inicio_br AS date)) AS dt
            FROM #Nums AS n
            WHERE il.inicio_br IS NOT NULL AND il.fim_br IS NOT NULL
              AND il.fim_br >= il.inicio_br
              AND n.n <= DATEDIFF(DAY, CAST(il.inicio_br AS date), CAST(il.fim_br AS date))
        ) AS dias
        CROSS APPLY (
            SELECT inicio_janela = DATEADD(HOUR, 8,  CAST(dias.dt AS datetime2(0))),
                   fim_janela    = DATEADD(HOUR, 20, CAST(dias.dt AS datetime2(0)))
        ) AS h
        CROSS APPLY (
            SELECT ini_calc = CASE WHEN il.inicio_br > h.inicio_janela THEN il.inicio_br ELSE h.inicio_janela END,
                   fim_calc = CASE WHEN il.fim_br    < h.fim_janela    THEN il.fim_br    ELSE h.fim_janela    END
        ) AS janela
        WHERE DATEDIFF(DAY, '19000101', dias.dt) % 7 BETWEEN 0 AND 4
          AND NOT EXISTS (SELECT 1 FROM #FeriadosFixos ff
                          WHERE ff.mes_dia = RIGHT(CONVERT(char(10), dias.dt, 120), 5))
          AND NOT EXISTS (SELECT 1 FROM #FeriadosPorData fp
                          WHERE fp.data = CAST(dias.dt AS date))
    ) AS x
) AS bh
GROUP BY b.id;

CREATE UNIQUE CLUSTERED INDEX IX_TempoAtendimentoStatusLead_id ON #TempoAtendimentoStatusLead(id);

--------------------------------------------------------------------------------
-- [8C] #MotorBase_FARC_P4 - motor BASE por chamado (motor unico)
--
--   ROTINA  -> categorias de rotina (passagem de turno / job summary): intervalo
--              Data Abertura FARC -> Fechamento.
--   CONTIDO -> demais: tempo em 'Em andamento'. No calculo final ele e combinado
--              (max) com o tempo ativo nas janelas A2B, que cobre a fila inicial
--              e a reposse. O antigo motor v10 foi removido.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#MotorBase_FARC_P4') IS NOT NULL DROP TABLE #MotorBase_FARC_P4;

SELECT
    b.id,
    regra_base = CASE
        WHEN b.categoria_sym COLLATE Latin1_General_CI_AI LIKE N'A2B.Realizar - Passagem de turno%'
          OR b.categoria_sym COLLATE Latin1_General_CI_AI LIKE N'A2B.Job Summary Report%'
            THEN N'ROTINA_INTERVALO_ABERTURA_FECHAMENTO'
        ELSE N'MOTOR_CONTIDO_JANELAS'
    END,
    motivo_base = CASE
        WHEN b.categoria_sym COLLATE Latin1_General_CI_AI LIKE N'A2B.Realizar - Passagem de turno%'
          OR b.categoria_sym COLLATE Latin1_General_CI_AI LIKE N'A2B.Job Summary Report%'
            THEN N'Regra BO: rotina operacional por intervalo Data Abertura FARC -> Fechamento'
        ELSE N'Regra BO: motor unico = tempo em Em andamento (contido), combinado no final com o tempo ativo nas janelas A2B'
    END,
    tempo_base_seg = CASE
        WHEN b.categoria_sym COLLATE Latin1_General_CI_AI LIKE N'A2B.Realizar - Passagem de turno%'
          OR b.categoria_sym COLLATE Latin1_General_CI_AI LIKE N'A2B.Job Summary Report%'
            THEN tr.tempo_atendimento_rotina_seg
        ELSE ISNULL(tsl.tempo_atendimento_status_lead_seg, 0)
    END
INTO #MotorBase_FARC_P4
FROM #BaseEscopo_FARC_P4 AS b
LEFT JOIN #TempoAtendimentoStatusLead AS tsl ON tsl.id = b.id
LEFT JOIN #TempoAtendimentoRotina     AS tr  ON tr.id  = b.id;

CREATE UNIQUE CLUSTERED INDEX IX_MotorBase_id ON #MotorBase_FARC_P4(id);

--------------------------------------------------------------------------------
-- [9] Cálculo FARC final
--------------------------------------------------------------------------------
;WITH BaseCalc AS (
    SELECT
        b.*,
        sl.meta_resolucao_seg,
        sl.tipo_resolucao,
        -- Regra final escolhida: por padrao o motor BASE. Vira o motor ATIVO
        -- (tempo de 'Aberto, aguarda atendimento' + 'Em andamento' desde a entrada
        -- na A2B, somado em TODAS as janelas de posse) sempre que ele somar mais
        -- que o base, pois isso significa que o base perdeu tempo: ou a fila
        -- inicial ('Aberto, aguarda atendimento') antes do 1o 'Em andamento', ou
        -- janelas de reposse anteriores (A2B -> outro -> A2B). Rotinas nunca mudam.
        CASE
            WHEN rb.regra_base <> N'ROTINA_INTERVALO_ABERTURA_FECHAMENTO'
             AND ISNULL(taj.tempo_ativo_janelas_a2b_seg, 0) > ISNULL(rb.tempo_base_seg, 0)
             AND ISNULL(taj.tempo_ativo_janelas_a2b_seg, 0) > 0
                THEN CASE WHEN ISNULL(qj.qtd_janelas_a2b, 0) > 1
                          THEN N'REPOSSE_A2B_MULTIPLAS_JANELAS'
                          ELSE N'ATIVO_A2B_FILA_INICIAL' END
            ELSE rb.regra_base
        END AS regra_tempo_farc,
        CASE
            WHEN rb.regra_base <> N'ROTINA_INTERVALO_ABERTURA_FECHAMENTO'
             AND ISNULL(taj.tempo_ativo_janelas_a2b_seg, 0) > ISNULL(rb.tempo_base_seg, 0)
             AND ISNULL(taj.tempo_ativo_janelas_a2b_seg, 0) > 0
                THEN CASE WHEN ISNULL(qj.qtd_janelas_a2b, 0) > 1
                          THEN N'Reposse A2B: chamado reentrou na A2B (varias janelas de posse). Soma o tempo ativo de TODAS as janelas, pois o base contava so a ultima.'
                          ELSE N'Fila inicial A2B: conta ''Aberto, aguarda atendimento'' desde a entrada na A2B ate o 1o ''Em andamento'', que o motor base ignorava.' END
            ELSE rb.motivo_base
        END AS motivo_regra_tempo_farc,
        ISNULL(tl.tempo_atendimento_log_total_seg, 0) AS tempo_atendimento_log_total_seg,
        ISNULL(tl.tempo_atendimento_descartado_antes_a2b_seg, 0) AS tempo_atendimento_descartado_antes_a2b_seg,
        ISNULL(tl.tempo_atendimento_log_seg, 0) AS tempo_atendimento_log_seg,
        tsl.tempo_atendimento_status_lead_seg,
        tr.tempo_atendimento_rotina_seg,
        rb.tempo_base_seg AS tempo_atendimento_base_seg,
        taj.tempo_ativo_janelas_a2b_seg AS tempo_reposse_a2b_seg,
        ISNULL(qj.qtd_janelas_a2b, 0) AS qtd_janelas_a2b,
        CASE
            WHEN rb.regra_base <> N'ROTINA_INTERVALO_ABERTURA_FECHAMENTO'
             AND ISNULL(taj.tempo_ativo_janelas_a2b_seg, 0) > ISNULL(rb.tempo_base_seg, 0)
             AND ISNULL(taj.tempo_ativo_janelas_a2b_seg, 0) > 0
                THEN ISNULL(taj.tempo_ativo_janelas_a2b_seg, 0) - ISNULL(rb.tempo_base_seg, 0)
            ELSE 0
        END AS delta_reposse_seg,
        CASE
            -- Rotinas operacionais (passagem de turno / job summary): NUNCA mudam;
            -- sempre o intervalo Data Abertura FARC -> Fechamento.
            WHEN rb.regra_base = N'ROTINA_INTERVALO_ABERTURA_FECHAMENTO'
                THEN rb.tempo_base_seg

            -- Motor ATIVO (delta, so adiciona): vale sempre que somar mais que o
            -- base, cobrindo tanto reposse multi-janela quanto a fila inicial
            -- 'Aberto, aguarda atendimento'. Nunca reduz o base.
            WHEN ISNULL(taj.tempo_ativo_janelas_a2b_seg, 0) > ISNULL(rb.tempo_base_seg, 0)
             AND ISNULL(taj.tempo_ativo_janelas_a2b_seg, 0) > 0
                THEN taj.tempo_ativo_janelas_a2b_seg

            ELSE rb.tempo_base_seg
        END AS tempo_atendimento_seg,
        t.terminal_epoch,
        t.fonte_terminal,
        CASE WHEN t.terminal_epoch IS NULL THEN NULL
             ELSE DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, t.terminal_epoch, @Epoch))
        END AS data_terminal_br
    FROM #BaseEscopo_FARC_P4 AS b
    LEFT JOIN #SLA_FARC_P4 AS sl
        ON sl.prioridade = b.prioridade_nivel
    LEFT JOIN #TempoAtendimentoLog AS tl
        ON tl.id = b.id
    LEFT JOIN #TempoAtendimentoStatusLead AS tsl
        ON tsl.id = b.id
    LEFT JOIN #TempoAtendimentoRotina AS tr
        ON tr.id = b.id
    LEFT JOIN #TempoAtivoJanelasA2B AS taj
        ON taj.id = b.id
    LEFT JOIN #TerminalFARC AS t
        ON t.id = b.id
    -- Motor BASE: mesma selecao que ja produzia os chamados corretos
    -- (rotina -> intervalo; hibrido status-lead em casos especificos; senao v10).
    LEFT JOIN #MotorBase_FARC_P4 AS rb
        ON rb.id = b.id
    OUTER APPLY (
        SELECT qtd_janelas_a2b = COUNT(*)
        FROM #JanelasA2B AS j
        WHERE j.id = b.id
    ) AS qj
),
Final AS (
    SELECT
        c.*,
        CASE
            WHEN c.tempo_atendimento_seg IS NULL OR c.meta_resolucao_seg IS NULL THEN NULL
            WHEN c.tempo_atendimento_seg > c.meta_resolucao_seg THEN c.tempo_atendimento_seg - c.meta_resolucao_seg
            ELSE 0
        END AS atendimento_excedido_seg
    FROM BaseCalc AS c
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

    CASE WHEN f.tempo_atendimento_seg IS NULL THEN NULL ELSE CONCAT(
        CONVERT(varchar(20), f.tempo_atendimento_seg / 3600), N':',
        RIGHT(N'00' + CONVERT(varchar(2), (f.tempo_atendimento_seg % 3600) / 60), 2), N':',
        RIGHT(N'00' + CONVERT(varchar(2), f.tempo_atendimento_seg % 60), 2)
    ) END AS [Tempo de Atendimento],

    CASE WHEN f.atendimento_excedido_seg IS NULL THEN NULL ELSE CONCAT(
        CONVERT(varchar(20), f.atendimento_excedido_seg / 3600), N':',
        RIGHT(N'00' + CONVERT(varchar(2), (f.atendimento_excedido_seg % 3600) / 60), 2), N':',
        RIGHT(N'00' + CONVERT(varchar(2), f.atendimento_excedido_seg % 60), 2)
    ) END AS [Tempo Atendimento Excedido],

    CASE
        WHEN f.atendimento_excedido_seg IS NULL THEN N'N/A'
        WHEN f.atendimento_excedido_seg > 0 THEN N'Não Atende'
        ELSE N'Atende'
    END AS [Meta Atendimento],
    f.indicador_reabertura AS [Indicador Reabertura],
    N'-' AS [Acordo Prazo],
    N'-' AS [Acordo Qualidade],
    N'-' AS [Justificativa],

    -- [nHR_FARC] PROPORCIONAL, com casas decimais: fração de hora NÃO vira hora
    -- inteira. Mesmo padrão decimal já adotado no nHR do FAIA Decision
    -- (decision/queries/consulta_faia.sql): CONVERT(decimal(18,2), excedido/3600.0).
    -- O CEILING anterior transformava 5400 s (1h30) em 2; agora resulta 1.50.
    CASE WHEN f.atendimento_excedido_seg IS NULL THEN NULL ELSE
        CONVERT(decimal(18, 2), f.atendimento_excedido_seg / 3600.0)
    END AS [nHR_FARC],

    -- [FARC] = nHR proporcional x fator 0,3 (fator contratual do A2B/Protect4).
    -- Calculado a partir do quociente cheio, não do nHR já arredondado a 2 casas.
    CASE WHEN f.atendimento_excedido_seg IS NULL THEN NULL ELSE
        CONVERT(decimal(18, 2), (f.atendimento_excedido_seg / 3600.0) * 0.3)
    END AS [FARC]
FROM Final AS f
ORDER BY
    f.data_fechamento_br ASC,
    f.ref_num ASC
OPTION (RECOMPILE);

-- Diagnóstico opcional: quebra os intervalos ativos usados no FARC.
IF @MostrarDiagnostico = 1
BEGIN
    -- Janelas de posse A2B (uma linha por janela; reposse aparece como várias).
    SELECT
        b.ref_num AS SDM,
        DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, j.win_inicio_epoch, @Epoch)) AS JanelaInicioBR,
        DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, j.win_fim_epoch, @Epoch))    AS JanelaFimBR,
        DATEDIFF(SECOND,
            DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, j.win_inicio_epoch, @Epoch)),
            DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, j.win_fim_epoch, @Epoch))) AS SegundosJanela
    FROM #JanelasA2B AS j
    JOIN #BaseEscopo_FARC_P4 AS b
        ON b.id = j.id
    ORDER BY b.ref_num, j.win_inicio_epoch;

    -- Peças ativas realmente contadas (interseção segmento ativo x janela A2B).
    SELECT
        b.ref_num AS SDM,
        p.inicio_br AS PecaInicioBR,
        p.fim_br AS PecaFimBR,
        sl.tipo_resolucao AS TipoResolucao,
        CASE WHEN sl.tipo_resolucao = 'CORRIDA'
             THEN DATEDIFF(SECOND, p.inicio_br, p.fim_br) ELSE NULL END AS SegundosCorridosPeca
    FROM #PecasAtivasA2B AS p
    JOIN #BaseEscopo_FARC_P4 AS b
        ON b.id = p.id
    LEFT JOIN #SLA_FARC_P4 AS sl
        ON sl.prioridade = b.prioridade_nivel
    ORDER BY b.ref_num, p.inicio_br;

    -- AUDITORIA por chamado: motor base, motor reposse, delta, qtd de janelas
    -- A2B e a regra final efetivamente escolhida (mesma logica do calculo final).
    SELECT
        b.ref_num AS SDM,
        b.categoria_sym AS Categoria,
        b.summary_txt AS Resumo,
        b.data_fechamento_br AS DataFechamento,
        ISNULL(qj.qtd_janelas_a2b, 0) AS QtdJanelasA2B,
        rb.regra_base AS MotorBase,
        rb.tempo_base_seg AS SegundosBase,
        taj.tempo_ativo_janelas_a2b_seg AS SegundosAtivoA2B,
        CASE
            WHEN rb.regra_base <> N'ROTINA_INTERVALO_ABERTURA_FECHAMENTO'
             AND ISNULL(taj.tempo_ativo_janelas_a2b_seg, 0) > ISNULL(rb.tempo_base_seg, 0)
             AND ISNULL(taj.tempo_ativo_janelas_a2b_seg, 0) > 0
                THEN ISNULL(taj.tempo_ativo_janelas_a2b_seg, 0) - ISNULL(rb.tempo_base_seg, 0)
            ELSE 0
        END AS DeltaAtivoSeg,
        CASE
            WHEN rb.regra_base <> N'ROTINA_INTERVALO_ABERTURA_FECHAMENTO'
             AND ISNULL(taj.tempo_ativo_janelas_a2b_seg, 0) > ISNULL(rb.tempo_base_seg, 0)
             AND ISNULL(taj.tempo_ativo_janelas_a2b_seg, 0) > 0
                THEN CASE WHEN ISNULL(qj.qtd_janelas_a2b, 0) > 1
                          THEN N'REPOSSE_A2B_MULTIPLAS_JANELAS'
                          ELSE N'ATIVO_A2B_FILA_INICIAL' END
            ELSE rb.regra_base
        END AS RegraFinalEscolhida,
        CASE
            WHEN rb.regra_base = N'ROTINA_INTERVALO_ABERTURA_FECHAMENTO'
                THEN rb.tempo_base_seg
            WHEN ISNULL(taj.tempo_ativo_janelas_a2b_seg, 0) > ISNULL(rb.tempo_base_seg, 0)
             AND ISNULL(taj.tempo_ativo_janelas_a2b_seg, 0) > 0
                THEN taj.tempo_ativo_janelas_a2b_seg
            ELSE rb.tempo_base_seg
        END AS SegundosFinal,
        tsl.tempo_atendimento_status_lead_seg AS SegundosStatusLead,
        tr.tempo_atendimento_rotina_seg AS SegundosRotina
    FROM #BaseEscopo_FARC_P4 AS b
    LEFT JOIN #TempoAtivoJanelasA2B AS taj
        ON taj.id = b.id
    LEFT JOIN #TempoAtendimentoStatusLead AS tsl
        ON tsl.id = b.id
    LEFT JOIN #TempoAtendimentoRotina AS tr
        ON tr.id = b.id
    OUTER APPLY (
        SELECT qtd_janelas_a2b = COUNT(*)
        FROM #JanelasA2B AS j
        WHERE j.id = b.id
    ) AS qj
    LEFT JOIN #MotorBase_FARC_P4 AS rb
        ON rb.id = b.id
    ORDER BY b.data_fechamento_br ASC, b.ref_num ASC;END;

-- As colunas [nHR_FARC] e [FARC] ficam no SELECT final para manter o layout esperado pelo relatório.