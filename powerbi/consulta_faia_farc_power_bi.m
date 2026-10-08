// =============================================================================
// Power BI - consulta do relatorio (unica), com feriados do SharePoint
// Fonte SQL: queries/consulta_faia_farc_painel.sql
//
// GERADO por tools/gerar_powerbi_m.ps1 a partir de queries/consulta_faia_farc_painel.sql.
// Nao edite este arquivo: altere o SQL-fonte e gere de novo.
//
// Uso (uma vez): Power Query > Pagina Inicial > Nova Fonte > Consulta Nula >
// Editor Avancado > colar este arquivo inteiro. Credenciais: SharePoint com
// Conta organizacional; SQL Server como hoje.
//
// Feriados: a cada atualizacao o arquivo feriados.txt e lido de novo no
// SharePoint (SharePoint.Files, site fixo), localizado pela pasta e pelo nome
// tirados de SharePointFeriadosLink, logo abaixo de "let". Ele e o mesmo para
// Virtual TI, Decision e A2B
// (calendario do TCU). Qualquer problema (arquivo nao encontrado na pasta, mais
// de um arquivo, codificacao invalida, data invalida ou repetida, secao
// desconhecida, arquivo sem datas) FALHA a atualizacao com mensagem; o
// relatorio nunca e calculado com zero feriados.
//
// Privacidade: SharePoint e SQL Server como Organizacional. Tudo fica num
// unico passo (Fonte) para o firewall de privacidade avaliar as duas fontes na
// mesma particao; nao separe os passos, senao volta o erro Formula.Firewall.
// =============================================================================
let
    // ============================================================================
    // CONFIGURACAO - SHAREPOINT (calendario de feriados)
    // Unico valor a editar: o link do feriados.txt copiado do SharePoint
    // (Copiar link, ou o endereco com o arquivo aberto). O link NAO e aberto:
    // dele saem so a pasta e o nome do arquivo. A leitura e feita por
    // SharePoint.Files no site https://tcucloud.sharepoint.com/sites/EstgioSidatTCU, com Conta organizacional;
    // link de outro site e erro.
    // ============================================================================
    SharePointFeriadosLink = "https://tcucloud.sharepoint.com/:t:/r/sites/EstgioSidatTCU/Documentos%20Compartilhados/Atividades%20Avulsas/Indicadores%20e%20Relat%C3%B3rios%20de%20Servi%C3%A7os/Documentos%20e%20Relat%C3%B3rios/feriados.txt?d=w3744a75ddc284a38890b5d9c4af44be3&csf=1&web=1&e=hwfUQM",

    Fonte =
        let
            // Servidor e banco da consulta SQL: os mesmos da fonte atual do
            // relatorio (conferir no PBIX; estao fixos no fim, em Sql.Database).

            // ---- Leitura do arquivo de feriados (feriados.txt) -------------
            // Mesmas regras de tools/feriados.ps1: so contam linhas que tem
            // apenas uma data; DD-MM na secao "## Feriados Fixos" e DD-MM-AAAA
            // nas secoes com ano; titulos, linhas vazias e paragrafos sao
            // ignorados. Saida para o SQL: MM-DD e AAAA-MM-DD.
            Falha = (mensagem as text) => error Error.Record("Feriados", mensagem),

            // ---- Localizacao do arquivo no SharePoint ------------------------
            // Site de conexao FIXO: o primeiro argumento de SharePoint.Files e
            // literal (requisito da atualizacao agendada no Power BI Service).
            SiteConexao = "https://tcucloud.sharepoint.com/sites/EstgioSidatTCU",
            ArquivosSite = SharePoint.Files("https://tcucloud.sharepoint.com/sites/EstgioSidatTCU", [ApiVersion = 15]),

            // Pasta e nome saem de SharePointFeriadosLink, que nunca e aberto.
            // Uri.Parts separa o caminho (sem "?..."), mas nao decodifica %XX:
            // DecodificarUrl junta os bytes de cada %XX e le tudo como UTF-8.
            DecodificarUrl = (s as text) as text =>
                let
                    Pedacos = Text.Split(s, "%"),
                    Bytes = List.Transform(List.Positions(Pedacos), (i) =>
                        let p = Pedacos{i}, h = Text.Upper(Text.Start(p, 2)) in
                        if i = 0 then Text.ToBinary(p, TextEncoding.Utf8)
                        else if Text.Length(h) = 2 and Text.Length(Text.Select(h, {"0".."9", "A".."F"})) = 2 then
                            Binary.Combine({Binary.FromText(h, BinaryEncoding.Hex), Text.ToBinary(Text.Range(p, 2), TextEncoding.Utf8)})
                        else Falha("SharePointFeriadosLink tem um codigo %XX invalido.")),
                    Texto = Text.FromBinary(Binary.Combine(Bytes), TextEncoding.Utf8)
                in
                    if Text.Contains(Texto, "#(FFFD)") then Falha("SharePointFeriadosLink tem caracteres codificados invalidos.") else Texto,
            NormPasta = (p as text) as text =>
                let t = Text.Lower(Text.Replace(Text.Trim(p), "%20", " ")) in
                if Text.EndsWith(t, "/") then t else t & "/",
            LocalDoLink =
                let
                    Partes = try Uri.Parts(Text.Trim(SharePointFeriadosLink)) otherwise null,
                    SiteParte = Uri.Parts(SiteConexao),
                    Segs0 = if Partes = null or Partes[Host] = "" then
                                Falha("SharePointFeriadosLink nao e um endereco valido. Copie o link do feriados.txt no SharePoint.")
                            else List.Select(Text.Split(DecodificarUrl(Partes[Path]), "/"), each _ <> ""),
                    // Prefixo de compartilhamento "/:t:/r/" (t = tipo do arquivo, r = caminho).
                    Compart = List.Count(Segs0) > 0 and Text.StartsWith(Segs0{0}, ":") and Text.EndsWith(Segs0{0}, ":"),
                    Segs =
                        if Compart and (List.Count(Segs0) < 2 or Text.Lower(Segs0{1}) <> "r") then
                            Falha("SharePointFeriadosLink e um link de compartilhamento sem o caminho do arquivo (formato /" & Segs0{0}
                                & "/" & (if List.Count(Segs0) > 1 then Segs0{1} else "") & "/...). Esse formato nao permite saber a pasta;"
                                & " use o link com /:t:/r/sites/... ou o endereco do arquivo aberto no SharePoint.")
                        else if Compart then List.Skip(Segs0, 2) else Segs0,
                    SiteDoLink = Text.Lower(Partes[Scheme] & "://" & Partes[Host] & "/"
                        & Text.Combine(List.FirstN(Segs, 2), "/")),
                    SiteEsperado = Text.Lower(SiteParte[Scheme] & "://" & SiteParte[Host] & SiteParte[Path])
                in
                    if List.Count(Segs) < 4 then
                        Falha("SharePointFeriadosLink nao traz o caminho completo do arquivo (site, biblioteca, pastas e nome).")
                    else if SiteDoLink <> SiteEsperado then
                        Falha("SharePointFeriadosLink aponta para outro site (" & SiteDoLink & "). O calendario so e lido do site "
                            & SiteConexao & "; para usar outro site, altere o gerador (tools/gerar_powerbi_m.ps1) e gere o .m de novo.")
                    else [
                        Site = SiteConexao,
                        Pasta = Partes[Scheme] & "://" & Partes[Host] & "/" & Text.Combine(List.RemoveLastN(Segs, 1), "/") & "/",
                        Nome = List.Last(Segs)
                    ],

            // Fica o UNICO arquivo com o nome E a pasta do link; nenhum, ou mais
            // de um, e erro (nunca se escolhe a primeira linha). A pasta e
            // comparada sem diferenca de maiusculas e da barra final.
            MesmoNome = Table.SelectRows(ArquivosSite, each Text.Lower([Name]) = Text.Lower(LocalDoLink[Nome])),
            NaPasta = Table.SelectRows(MesmoNome, each NormPasta([Folder Path]) = NormPasta(LocalDoLink[Pasta])),
            QtdNaPasta = Table.RowCount(NaPasta),
            PastasComONome = Text.Combine(List.Transform(Table.Column(MesmoNome, "Folder Path"), each "[" & _ & "]"), " "),
            Conteudo =
                if QtdNaPasta = 0 then
                    Falha("Arquivo '" & LocalDoLink[Nome] & "' nao encontrado na pasta do link [" & LocalDoLink[Pasta]
                        & "]. Pastas do site com um arquivo desse nome: "
                        & (if PastasComONome = "" then "nenhuma" else PastasComONome) & ".")
                else if QtdNaPasta > 1 then
                    Falha("Ha " & Text.From(QtdNaPasta) & " arquivos '" & LocalDoLink[Nome] & "' na pasta do link ["
                        & LocalDoLink[Pasta] & "]; deve haver exatamente um.")
                else Binary.Buffer(NaPasta{0}[Content]),

            // ---- Interpretacao do arquivo (feriados.txt) ---------------------
            Utf16 = List.Contains({#binary({255, 254}), #binary({254, 255})}, Binary.Range(Conteudo, 0, 2)),
            TextoBruto =
                if Utf16 then Falha("Arquivo de feriados com codificacao invalida (salve em UTF-8, nao UTF-16).")
                else Text.Replace(Text.FromBinary(Conteudo, TextEncoding.Utf8), "#(FEFF)", ""),
            Texto =
                if Text.Contains(TextoBruto, "#(FFFD)") or Text.Contains(TextoBruto, "#(0000)") then
                    Falha("Arquivo de feriados com codificacao invalida (salve em UTF-8).")
                else if Text.Trim(TextoBruto) = "" then Falha("Arquivo de feriados vazio.")
                else TextoBruto,
            SemAcento = (s as text) as text => List.Accumulate(
                {{"#(00E1)", "a"}, {"#(00E0)", "a"}, {"#(00E2)", "a"}, {"#(00E3)", "a"}, {"#(00E9)", "e"}, {"#(00EA)", "e"},
                 {"#(00ED)", "i"}, {"#(00F3)", "o"}, {"#(00F4)", "o"}, {"#(00F5)", "o"}, {"#(00FA)", "u"}, {"#(00E7)", "c"}},
                s, (acc, par) => Text.Replace(acc, par{0}, par{1})),
            NomeSecao = (s as text) as text =>
                Text.Combine(List.Select(Text.SplitAny(SemAcento(Text.Lower(Text.Trim(s))), " #(tab)"), each _ <> ""), " "),
            Secoes = [
                #"feriados fixos" = "Feriado fixo",
                #"feriados moveis/diferenciados" = "Feriado m#(00F3)vel/diferenciado",
                #"pontos facultativos" = "Ponto facultativo"
            ],
            SoDigitos = (s as text) => Text.Length(s) > 0 and Text.Length(Text.Select(s, {"0".."9"})) = Text.Length(s),
            Dois = (n as number) => Text.PadStart(Text.From(n), 2, "0"),
            EhFixo = (s as text) => Text.Length(s) = 5 and Text.At(s, 2) = "-" and SoDigitos(Text.Start(s, 2) & Text.End(s, 2)),
            EhDatada = (s as text) => Text.Length(s) = 10 and Text.At(s, 2) = "-" and Text.At(s, 5) = "-"
                and SoDigitos(Text.Start(s, 2) & Text.Middle(s, 3, 2) & Text.End(s, 4)),
            PareceData = (s as text) => Text.Length(s) > 0 and SoDigitos(Text.Start(s, 1))
                and Text.Select(s, {"0".."9", "-", "/", ".", " ", "#(tab)"}) = s,
            Erro = (e as record, n as number, msg as text) => e & [erros = e[erros] & {"linha " & Text.From(n) & ": " & msg}],
            Item = (e as record, n as number, original as text, data as text) =>
                let anterior = List.Select(e[itens], each _[data] = data) in
                if List.IsEmpty(anterior) then e & [itens = e[itens] & {[data = data, descricao = Record.Field(Secoes, e[secao]), linha = n]}]
                else Erro(e, n, "data '" & original & "' repetida (ja na linha " & Text.From(anterior{0}[linha]) & ")"),
            Linhas = List.Buffer(Lines.FromText(Texto)),
            Estado = List.Accumulate(List.Positions(Linhas), [secao = null, itens = {}, erros = {}], (e, i) =>
                let
                    n = i + 1,
                    t = Text.Trim(Linhas{i}),
                    titulo = if Text.StartsWith(t, "##") and Text.Trim(Text.Range(t, 2)) <> "" then NomeSecao(Text.Range(t, 2)) else null
                in
                    if titulo <> null then
                        (if Record.HasFields(Secoes, titulo) then e & [secao = titulo]
                         else Erro(e & [secao = null], n, "secao desconhecida '" & t & "'"))
                    else if EhFixo(t) then
                        (if e[secao] <> "feriados fixos" then Erro(e, n, "feriado fixo '" & t & "' fora da secao '## Feriados Fixos'")
                         else
                            let d = try #date(2000, Number.From(Text.End(t, 2)), Number.From(Text.Start(t, 2))) otherwise null in
                            if d = null then Erro(e, n, "data invalida '" & t & "' (use DD-MM)")
                            else Item(e, n, t, Dois(Date.Month(d)) & "-" & Dois(Date.Day(d))))
                    else if EhDatada(t) then
                        (if e[secao] = null or e[secao] = "feriados fixos" then
                            Erro(e, n, "data '" & t & "' fora das secoes de datas com ano")
                         else
                            let d = try #date(Number.From(Text.End(t, 4)), Number.From(Text.Middle(t, 3, 2)), Number.From(Text.Start(t, 2))) otherwise null in
                            if d = null then Erro(e, n, "data invalida '" & t & "' (use DD-MM-AAAA)")
                            else Item(e, n, t, Text.PadStart(Text.From(Date.Year(d)), 4, "0") & "-" & Dois(Date.Month(d)) & "-" & Dois(Date.Day(d))))
                    else if PareceData(t) then Erro(e, n, "formato invalido '" & t & "' (use DD-MM ou DD-MM-AAAA)")
                    else e),
            // Forca a validacao de TODAS as linhas antes de chamar o SQL.
            Validas =
                if not List.IsEmpty(Estado[erros]) then Falha("Arquivo de feriados invalido: " & Text.Combine(Estado[erros], "; "))
                else if List.IsEmpty(Estado[itens]) then Falha("Arquivo de feriados sem nenhuma data.")
                else Estado[itens],
            ParaSql = List.Transform(Validas, each [data = _[data], descricao = _[descricao]]),
            FeriadosJson = Text.FromBinary(Json.FromValue(ParaSql), TextEncoding.Utf8),

            // ---- Consulta SQL (queries/consulta_faia_farc_painel.sql) ----------------------------
            SqlTexto = "-- =============================================================================
-- PARAMETRO EDITAVEL  (no Power BI: Editor Avancado da consulta, no inicio do
-- texto SqlTexto; no repositorio: altere aqui e gere de novo powerbi/consulta_faia_farc_power_bi.m)
--
-- Este arquivo e a CONSULTA DE REFERENCIA DO PAINEL: a fonte do .m e a copia
-- executavel dele para testes e regressao. Ele nao se cola no Power BI; a
-- unica consulta do Power BI e powerbi/consulta_faia_farc_power_bi.m, gerada
-- por tools/gerar_powerbi_m.ps1 -Consulta queries/consulta_faia_farc_painel.sql
-- -Saida powerbi/consulta_faia_farc_power_bi.m.
--
--   Quantidade de ciclos COMPLETOS carregados. Padrao: 12.
--   Cada ciclo vai do dia 24 de um mes ate o dia 23 do mes seguinte (regra da
--   A2B/Protect4). O ciclo em andamento nunca entra.
--
--   E o unico numero que precisa mudar para aumentar ou reduzir o periodo.
--   Nenhuma regra de negocio depende dele. Detalhes no bloco [S.0].
-- =============================================================================
DECLARE @PBI_QuantidadeCiclos int = 12;

/*
================================================================================
CONSULTA CONSOLIDADA FAIA + FARC - A2B/PROTECT4  (fonte do Power BI)
================================================================================

Uso:
  - Power BI Desktop
  - Conector: SQL Server
  - Banco de dados: mdb
  - Modo: Importacao
  - NAO colar este arquivo em ""Instrucao SQL"": a consulta do relatorio e
    powerbi/consulta_faia_farc_power_bi.m (Consulta Nula > Editor Avancado), que le os
    feriados do SharePoint e envia o parametro @Feriados a este SQL.
  - ""Adicionar colunas de relacao"": desmarcado

Periodo:
  - Retorna os ultimos @PBI_QuantidadeCiclos ciclos COMPLETOS da Protect4
    (padrao 12; ate 2026-09-18 eram seis, fixos no codigo).
  - Cada ciclo comeca no dia 24 e termina no dia 23 do mes seguinte.
  - O ciclo atualmente em andamento NAO entra.
  - O periodo SELECIONA os chamados (por close_date). Ele NAO recorta os
    intervalos calculados: cada indicador percorre a linha do tempo do proprio
    chamado, mesmo quando parte dela ocorreu antes do inicio da janela.

Saida:
  - UMA linha por chamado (SDM).
  - Ordem: colunas comuns do chamado -> colunas do FAIA -> colunas do FARC.
  - Nao existe segundo bloco de colunas comuns no fim do resultado.
  - Um unico result set. Nenhum bloco de diagnostico.

Referencias tecnicas dos calculos (nao substituidas por este arquivo):
  - queries/consulta_faia_a2b_protect4.sql
  - queries/consulta_farc_a2b_protect4.sql
  - powerbi/powerbi-query.md

A consulta nao cria view, tabela ou procedure permanente. Usa apenas tabelas
temporarias da sessao, todas com o prefixo #PBI_, #FAIA_ ou #FARC_, que nao
colidem com as temporarias das consultas individuais da Protect4 nem com as da
Decision. Nao existe GO neste arquivo.

--------------------------------------------------------------------------------
ONDE ESTA CONSULTA E EXECUTADA
--------------------------------------------------------------------------------
Este arquivo e T-SQL puro. Nao e Power Query M, nao e DAX e nao esta encapsulado
em Value.NativeQuery. O Power BI apenas ENVIA este texto ao SQL Server pelo
conector nativo e IMPORTA o result set final: quem compila, otimiza e executa e
o SQL Server, nao o Power BI.

Consequencia pratica: em condicoes equivalentes (mesmo banco, mesmas permissoes,
arquivo inteiro em um unico lote) o script tem de rodar tambem no SSMS. Diferenca
de comportamento entre o Power BI e o SSMS indica diferenca de CONTEXTO, e o
contexto que mais importa aqui e o BANCO DE DADOS ATUAL.

O conector do Power BI recebe o banco (mdb) na propria conexao, entao a consulta
sempre roda no banco certo por la. O SSMS, nao: uma janela nova abre no banco
padrao do login, que normalmente e o master. Como todas as referencias deste
arquivo sao de duas partes (dbo.call_req, dbo.act_log, dbo.cr_stat, dbo.pri,
dbo.prob_ctg, dbo.ca_contact, dbo.audit_log, dbo.View_Audit_Group), elas se
resolvem no banco ATUAL. Fora do mdb, o lote inteiro falha na compilacao com
Msg 208 (Invalid object name) e nenhuma linha e produzida.

Por isso o USE mdb abaixo. Ele torna o script independente do cliente, e e o
mesmo padrao ja adotado pelas outras tres consultas do repositorio
(consulta_faia_a2b_protect4.sql, consulta_farc_a2b_protect4.sql e
decision/queries/consulta_faia_farc.sql). No Power BI e inofensivo: a conexao ja
aponta para mdb, entao o USE nao muda nada.

--------------------------------------------------------------------------------
ESTRUTURAS COMPARTILHADAS ENTRE FAIA E FARC (secao [S])
--------------------------------------------------------------------------------
As duas metades partiam das MESMAS tabelas, calculadas duas vezes. Foram unidas
por terem origem, semantica, tipo, granularidade e regra identicas:

  #PBI_CRPeriodo   - dbo.call_req era lido DUAS vezes com o mesmo filtro.
  #PBI_Base        - o enriquecimento (cr_stat, prob_ctg, pri, ca_contact x2)
                     rodava DUAS vezes sobre o mesmo conjunto.
  #PBI_EscopoBase  - o conjunto ""grupo A2B + tipo I/R/P + status terminal"" era
                     materializado duas vezes (#FAIA_Candidatos e #FARC_EscopoIds
                     usam predicado identico).
  #PBI_LogEscopo   - dbo.act_log era lido 11 vezes (9 na metade FAIA, direto na
                     tabela base, e 1 na metade FARC + reuso). Agora e lido UMA
                     vez, para os chamados do escopo, e as duas metades leem
                     desta copia.
  #PBI_SLA         - as duas tabelas de SLA por severidade eram identicas.
  #PBI_FeriadosFixos / #PBI_FeriadosPorData - ver a nota de correcao abaixo.

Permaneceram SEPARADAS (regra diferente em cada indicador): inicio de contagem,
captura, posse/reposse, terminal, rotinas, motores de tempo e os resultados
#FAIA_Resultado / #FARC_Resultado. Nenhuma regra de um indicador foi aplicada ao
outro.

#FAIA_Nums e #FARC_Nums continuam separadas de proposito: o dimensionamento do
FARC depende de #FARC_PecasAtivasA2B, que so existe no fim da metade FARC. Unir
as duas exigiria antecipar esse calculo, com risco real e ganho desprezivel
(a tabela de numeros vem de sys.all_objects).

--------------------------------------------------------------------------------
CORRECAO FUNCIONAL: calendario de feriados unico
--------------------------------------------------------------------------------
As duas metades traziam calendarios DIFERENTES:
  - a metade FAIA nao tinha 2025-12-24 nem 2025-12-31;
  - a metade FARC tinha as duas datas.
Dentro de uma unica consulta consolidada isso significa calcular o FAIA e o FARC
do MESMO chamado com calendarios distintos. As duas datas sao pontos facultativos
reais do TCU e a ausencia no lado FAIA e uma omissao ja registrada no historico do
projeto. Aqui as tabelas foram unificadas pela UNIAO, isto e, incluindo
2025-12-24 e 2025-12-31 para os dois indicadores.

Efeito: so muda o resultado de chamado cuja janela comercial toque essas duas
datas. Como a janela e movel, isso ocorre quando o periodo alcanca
Dezembro/2025. Registrado em project-context/A2B-HISTORICO-CONTEXTO-MESTRE.md.
As consultas individuais em queries/ NAO foram alteradas: enquanto o
FAIA individual nao receber essas duas datas, ele pode divergir desta consulta
nesse cenario especifico.
================================================================================
*/

USE mdb;
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#FAIA_Resultado') IS NOT NULL DROP TABLE #FAIA_Resultado;
IF OBJECT_ID('tempdb..#FARC_Resultado') IS NOT NULL DROP TABLE #FARC_Resultado;

--------------------------------------------------------------------------------
-- [S.0] PARAMETROS COMPARTILHADOS
--
-- Uma unica definicao de fornecedor, periodo, fuso e janela comercial, usada
-- pelas duas metades. Antes existiam dois conjuntos (@FAIA_* e @FARC_*) que
-- calculavam exatamente o mesmo periodo.
--------------------------------------------------------------------------------
DECLARE @PBI_FornecedorNome  nvarchar(100) = N'A2B/Protect4';
DECLARE @PBI_FornecedorGrupo varbinary(16) = 0xCE4FDD26D5053545BF4A11332BB07485;

-- Janela dinamica: ultimos @PBI_QuantidadeCiclos ciclos completos da Protect4.
-- Cada ciclo vai do dia 24 de um mes ate o dia 23 do mes seguinte.
-- O ciclo atualmente em andamento e excluido.
--
-- @PBI_QuantidadeCiclos e declarado na PRIMEIRA linha util do arquivo, para
-- ficar visivel no inicio do texto SqlTexto da consulta M. Voltar N meses
-- a partir de um dia 24 cai sempre em outro dia 24, entao a janela comeca
-- exatamente no inicio de um ciclo, qualquer que seja N.
DECLARE @PBI_HojeBrasil date =
    CONVERT(date, DATEADD(HOUR, -3, SYSUTCDATETIME()));

DECLARE @PBI_InicioCicloAtual date =
    CASE
        WHEN DAY(@PBI_HojeBrasil) >= 24
            THEN DATEFROMPARTS(YEAR(@PBI_HojeBrasil), MONTH(@PBI_HojeBrasil), 24)
        ELSE DATEADD(
                 MONTH,
                 -1,
                 DATEFROMPARTS(YEAR(@PBI_HojeBrasil), MONTH(@PBI_HojeBrasil), 24)
             )
    END;

DECLARE @PBI_FimBrasilExclusivo datetime2(0) =
    CONVERT(datetime2(0), @PBI_InicioCicloAtual);

DECLARE @PBI_InicioBrasil datetime2(0) =
    DATEADD(MONTH, -@PBI_QuantidadeCiclos, @PBI_FimBrasilExclusivo);

-- Conversao para UTC/GMT usado pelo SDM em pdmtime/epoch.
DECLARE @PBI_HorasBrasilParaUTC int = 3;
DECLARE @PBI_Epoch datetime2(0) = '1970-01-01 00:00:00';
DECLARE @PBI_FromUTC datetime2(0) =
    DATEADD(HOUR, @PBI_HorasBrasilParaUTC, @PBI_InicioBrasil);
DECLARE @PBI_ToUTCExclusivo datetime2(0) =
    DATEADD(HOUR, @PBI_HorasBrasilParaUTC, @PBI_FimBrasilExclusivo);
DECLARE @PBI_FromEpoch int =
    DATEDIFF(SECOND, @PBI_Epoch, @PBI_FromUTC);
DECLARE @PBI_ToEpochExclusivo int =
    DATEDIFF(SECOND, @PBI_Epoch, @PBI_ToUTCExclusivo);

-- Janela comercial usada nos SLAs do tipo COMERCIAL.
DECLARE @PBI_HoraInicioComercial int = 8;
DECLARE @PBI_HoraFimComercial    int = 20;

--------------------------------------------------------------------------------
-- [S.1] SLA por severidade (compartilhado)
--
-- Conforme SLA por Severidade.png. As duas metades usavam tabelas identicas.
-- P1: inicio 15 min corridos; resolucao 12h corrida
-- P2: inicio 60 min corridos; resolucao 24h corrida
-- P3/P4: inicio 240 min comerciais; resolucao 36h comercial
-- P5: inicio 720 min comerciais; resolucao 360h comercial
--
-- A tabela e indexada apenas por severidade: Problema (P) usa a mesma meta do
-- Incidente e da Solicitacao de mesma severidade.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#PBI_SLA') IS NOT NULL DROP TABLE #PBI_SLA;
CREATE TABLE #PBI_SLA (
    prioridade            tinyint     NOT NULL PRIMARY KEY,
    meta_inicio_seg       int         NOT NULL,
    tipo_inicio           varchar(10) NOT NULL, -- CORRIDA | COMERCIAL
    meta_resolucao_seg    int         NOT NULL,
    tipo_resolucao        varchar(10) NOT NULL  -- CORRIDA | COMERCIAL
);

INSERT INTO #PBI_SLA(prioridade, meta_inicio_seg, tipo_inicio, meta_resolucao_seg, tipo_resolucao)
VALUES
    (1,  15 * 60,       'CORRIDA',    12 * 60 * 60,       'CORRIDA'),
    (2,  60 * 60,       'CORRIDA',    24 * 60 * 60,       'CORRIDA'),
    (3, 240 * 60,       'COMERCIAL',  36 * 60 * 60,       'COMERCIAL'),
    (4, 240 * 60,       'COMERCIAL',  36 * 60 * 60,       'COMERCIAL'),
    (5, 720 * 60,       'COMERCIAL', 360 * 60 * 60,       'COMERCIAL');

--------------------------------------------------------------------------------
-- [S.2] Feriados e pontos facultativos (compartilhado)
--
-- A lista de feriados NAO fica mais neste arquivo. Ela vem do arquivo de
-- feriados (docs/feriados.txt; no Power BI, a copia no SharePoint), o mesmo
-- calendario do TCU para Virtual TI, Decision e A2B, pelo parametro @Feriados
-- (JSON):
--   [{""data"":""12-25"",""descricao"":""Natal""},{""data"":""2026-04-03"",""descricao"":""...""}]
--   MM-DD      = feriado fixo, vale todo ano;
--   AAAA-MM-DD = data unica (feriado movel ou ponto facultativo).
-- Quem preenche @Feriados: tools/executar_consulta.ps1 (consultas de queries/)
-- e o codigo M de powerbi/*.m (Power BI). Sem @Feriados a consulta nem compila;
-- lista vazia, JSON ou data invalida param com erro: nunca se calcula com zero
-- feriados. Data repetida entra uma vez.
--
-- Regra de contagem (inalterada):
--   - CORRIDA: conta 24h, sem desconto de feriado/facultativo.
--   - COMERCIAL: conta somente segunda a sexta, 08:00-20:00, zerando os dias
--     listados como feriado/facultativo.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#PBI_FeriadosEntrada') IS NOT NULL DROP TABLE #PBI_FeriadosEntrada;
CREATE TABLE #PBI_FeriadosEntrada (data nvarchar(100) NULL, descricao nvarchar(200) NULL);
IF ISJSON(@Feriados) = 1
    INSERT INTO #PBI_FeriadosEntrada (data, descricao)
    SELECT LTRIM(RTRIM(j.data)), LTRIM(RTRIM(j.descricao))
    FROM OPENJSON(@Feriados) WITH (data nvarchar(100) '$.data', descricao nvarchar(200) '$.descricao') AS j;
IF ISNULL(ISJSON(@Feriados), 0) = 0 OR NOT EXISTS (SELECT 1 FROM #PBI_FeriadosEntrada)
BEGIN
    ;THROW 50001, N'Feriados: @Feriados vazio ou invalido. Execute pelo tools/executar_consulta.ps1 (queries/) ou pelo Power BI (powerbi/*.m).', 1;
END;
IF EXISTS (
    SELECT 1
    FROM #PBI_FeriadosEntrada AS f
    WHERE f.data IS NULL
       OR NOT (   (LEN(f.data) = 10 AND f.data LIKE N'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND TRY_CONVERT(date, f.data, 23) IS NOT NULL)
               OR (LEN(f.data) = 5  AND f.data LIKE N'[0-9][0-9]-[0-9][0-9]' AND TRY_CONVERT(date, N'2000-' + f.data, 23) IS NOT NULL))
)
BEGIN
    ;THROW 50002, N'Feriados: @Feriados tem data fora do formato AAAA-MM-DD ou MM-DD.', 1;
END;

IF OBJECT_ID('tempdb..#PBI_FeriadosFixos') IS NOT NULL DROP TABLE #PBI_FeriadosFixos;
CREATE TABLE #PBI_FeriadosFixos (
    mes_dia   char(5)        NOT NULL PRIMARY KEY, -- MM-DD
    descricao nvarchar(200)  NOT NULL
);
INSERT INTO #PBI_FeriadosFixos (mes_dia, descricao)
SELECT f.data, MIN(COALESCE(NULLIF(f.descricao, N''), N'Feriado'))
FROM #PBI_FeriadosEntrada AS f
WHERE LEN(f.data) = 5
GROUP BY f.data;

IF OBJECT_ID('tempdb..#PBI_FeriadosPorData') IS NOT NULL DROP TABLE #PBI_FeriadosPorData;
CREATE TABLE #PBI_FeriadosPorData (
    data      date           NOT NULL PRIMARY KEY,
    descricao nvarchar(200)  NOT NULL
);
INSERT INTO #PBI_FeriadosPorData (data, descricao)
SELECT CONVERT(date, f.data, 23), MIN(COALESCE(NULLIF(f.descricao, N''), N'Feriado'))
FROM #PBI_FeriadosEntrada AS f
WHERE LEN(f.data) = 10
GROUP BY CONVERT(date, f.data, 23);

--------------------------------------------------------------------------------
-- [S.3] Pre-filtro por periodo de fechamento (compartilhado)
-- dbo.call_req e lido UMA vez. Antes era lido duas, com o mesmo filtro.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#PBI_CRPeriodo') IS NOT NULL DROP TABLE #PBI_CRPeriodo;

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
INTO #PBI_CRPeriodo
FROM dbo.call_req AS r
WHERE r.close_date IS NOT NULL
  AND r.close_date >= @PBI_FromEpoch
  AND r.close_date <  @PBI_ToEpochExclusivo;

CREATE UNIQUE CLUSTERED INDEX IX_PBI_CRPeriodo_id ON #PBI_CRPeriodo(id);
CREATE INDEX IX_PBI_CRPeriodo_persid ON #PBI_CRPeriodo(persid);
CREATE INDEX IX_PBI_CRPeriodo_group ON #PBI_CRPeriodo(group_id);

--------------------------------------------------------------------------------
-- [S.4] Base enriquecida (compartilhada)
-- O enriquecimento com cr_stat, prob_ctg, pri e ca_contact (duas vezes) rodava
-- duas vezes sobre o mesmo conjunto. Agora roda uma vez.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#PBI_Base') IS NOT NULL DROP TABLE #PBI_Base;

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
INTO #PBI_Base
FROM #PBI_CRPeriodo AS r
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

CREATE UNIQUE CLUSTERED INDEX IX_PBI_Base_id ON #PBI_Base(id);
CREATE INDEX IX_PBI_Base_persid ON #PBI_Base(persid);
CREATE INDEX IX_PBI_Base_group ON #PBI_Base(group_id);

--------------------------------------------------------------------------------
-- [S.5] Conjunto base do escopo (compartilhado)
--
-- Predicado identico ao que #FAIA_Candidatos e #FARC_EscopoIds ja aplicavam:
-- grupo atual A2B/Protect4 + tipo I/R/P + status TERMINAL (por codigo, nunca por
-- texto). Serve para materializar o log uma unica vez em [S.6].
--
-- A restricao ADICIONAL do FAIA (encerrar no grupo A2B) continua sendo aplicada
-- adiante, em #FAIA_EscopoIds. Por isso o escopo do FAIA e um SUBCONJUNTO do
-- escopo do FARC, e o resultado final usa FULL OUTER JOIN.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#PBI_EscopoBase') IS NOT NULL DROP TABLE #PBI_EscopoBase;

SELECT
    b.id,
    b.persid
INTO #PBI_EscopoBase
FROM #PBI_Base AS b
WHERE b.group_id = @PBI_FornecedorGrupo
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

CREATE UNIQUE CLUSTERED INDEX IX_PBI_EscopoBase_id ON #PBI_EscopoBase(id);
CREATE INDEX IX_PBI_EscopoBase_persid ON #PBI_EscopoBase(persid);

--------------------------------------------------------------------------------
-- [S.6] Materializacao do log do escopo (compartilhada - PERFORMANCE)
--
-- dbo.act_log e a maior tabela do SDM. Antes ela era varrida 11 vezes: 9 vezes
-- na metade FAIA, direto na tabela base, e mais uma na metade FARC, que ja
-- reutilizava a propria copia. Aqui e lida UMA vez, somente para os chamados do
-- escopo, e as DUAS metades leem desta copia.
--
-- Mesmas colunas e mesmos tipos das leituras originais, mais texto_log
-- pre-concatenado. Como nao ha filtro de tipo nem de data, a copia e equivalente
-- a dbo.act_log restrita aos chamados do escopo: nenhuma passada muda de regra,
-- inclusive a contagem bruta de logs do FAIA.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#PBI_LogEscopo') IS NOT NULL DROP TABLE #PBI_LogEscopo;

SELECT
    src.id AS log_id,  -- desempate de eventos no mesmo segundo (ver nota junto aos LEAD)
    src.call_req_id,
    src.system_time,
    src.description,
    src.action_desc,
    src.[type],
    src.time_spent,
    src.analyst,
    CONVERT(nvarchar(max), ISNULL(src.description, N'')) + N' ' +
    CONVERT(nvarchar(max), ISNULL(src.action_desc,  N'')) AS texto_log
INTO #PBI_LogEscopo
FROM dbo.act_log AS src
WHERE src.call_req_id IN (SELECT e.persid FROM #PBI_EscopoBase AS e);

CREATE INDEX IX_PBI_LogEscopo_cr_time ON #PBI_LogEscopo(call_req_id, system_time);
CREATE INDEX IX_PBI_LogEscopo_cr_type ON #PBI_LogEscopo(call_req_id, [type]);


--------------------------------------------------------------------------------
-- PARTE 1: FAIA  (motor do primeiro atendimento - preservado)
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- [3] Candidatos do fornecedor pelo GRUPO atual
--
-- Critério único de fornecedor: grupo atual do chamado = A2B/Protect4.
-- A categoria NÃO é mais usada como filtro em nenhuma etapa.
-- A confirmação de que o chamado ENCERROU no grupo é feita na etapa [5].
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#FAIA_Candidatos') IS NOT NULL DROP TABLE #FAIA_Candidatos;

SELECT b.*
INTO #FAIA_Candidatos
FROM #PBI_Base AS b
WHERE b.group_id = @PBI_FornecedorGrupo
  -- Tipos apurados: I = Incidente, R = Solicitação, P = Problema.
  -- 'P' foi incluído para alinhar o escopo do FAIA ao do FARC Protect4, que já
  -- usava IN ('I','R','P'). Sem hardcode por SDM: o critério é o tipo real do
  -- chamado em call_req.type. Nenhuma etapa posterior filtra por tipo, e a #PBI_SLA
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

CREATE UNIQUE CLUSTERED INDEX IX_Candidatos_id ON #FAIA_Candidatos(id);
CREATE INDEX IX_Candidatos_persid ON #FAIA_Candidatos(persid);

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
IF OBJECT_ID('tempdb..#FAIA_TransfGrupo_FAIA_P4') IS NOT NULL DROP TABLE #FAIA_TransfGrupo_FAIA_P4;

SELECT
    b.id,
    COUNT(*)                                                       AS qtd_transf_grupo,
    MAX(al.system_time)                                            AS ultima_transf_grupo_epoch,
    MIN(CASE WHEN flag.eh_entrada_a2b = 1 THEN al.system_time END) AS primeira_entrada_a2b_epoch,
    MAX(CASE WHEN flag.eh_entrada_a2b = 1 THEN al.system_time END) AS ultima_entrada_a2b_epoch
INTO #FAIA_TransfGrupo_FAIA_P4
FROM #FAIA_Candidatos AS b
JOIN #PBI_LogEscopo AS al
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

CREATE UNIQUE CLUSTERED INDEX IX_TransfGrupo_id ON #FAIA_TransfGrupo_FAIA_P4(id);

--------------------------------------------------------------------------------
-- [5] Escopo final: chamados que ENCERRARAM no grupo A2B/Protect4
--
-- Além de estar no grupo A2B/Protect4 (já garantido em #FAIA_Candidatos), o chamado
-- precisa TERMINAR no grupo A2B. Isso vale quando:
--   (a) o chamado nasceu no grupo e nunca sofreu transferência de grupo; ou
--   (b) a ÚLTIMA transferência de grupo de todas, até o fechamento, foi uma
--       entrada em 'Fornecedores - A2B' (não houve saída do grupo depois).
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#FAIA_EscopoIds') IS NOT NULL DROP TABLE #FAIA_EscopoIds;
CREATE TABLE #FAIA_EscopoIds (
    id int NOT NULL PRIMARY KEY,
    FonteFornecedor nvarchar(120) NOT NULL
);

INSERT INTO #FAIA_EscopoIds(id, FonteFornecedor)
SELECT
    c.id,
    CASE
        WHEN tg.id IS NULL
            THEN N'Nasceu e permaneceu no grupo A2B/Protect4 (sem transferência de grupo)'
        ELSE N'Encerrou no grupo A2B/Protect4 (última transferência de grupo foi para Fornecedores - A2B)'
    END AS FonteFornecedor
FROM #FAIA_Candidatos AS c
LEFT JOIN #FAIA_TransfGrupo_FAIA_P4 AS tg
    ON tg.id = c.id
WHERE
    -- (a) nasceu no grupo e nunca foi transferido; group_id = A2B já garantido em #FAIA_Candidatos
    tg.id IS NULL
    -- (b) a última transferência de grupo de todas foi uma entrada em Fornecedores - A2B
    OR (
        tg.ultima_entrada_a2b_epoch IS NOT NULL
        AND tg.ultima_entrada_a2b_epoch = tg.ultima_transf_grupo_epoch
    );


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
IF OBJECT_ID('tempdb..#FAIA_InicioContagemA2B') IS NOT NULL DROP TABLE #FAIA_InicioContagemA2B;

CREATE TABLE #FAIA_InicioContagemA2B (
    id int NOT NULL PRIMARY KEY,
    inicio_contagem_epoch int NULL,
    fonte_inicio_contagem nvarchar(120) NOT NULL
);

INSERT INTO #FAIA_InicioContagemA2B (id, inicio_contagem_epoch, fonte_inicio_contagem)
SELECT
    e.id,
    COALESCE(tg.primeira_entrada_a2b_epoch, b.open_date) AS inicio_contagem_epoch,
    CASE
        WHEN tg.primeira_entrada_a2b_epoch IS NOT NULL THEN N'Transferência para Fornecedores - A2B'
        WHEN b.open_date IS NOT NULL THEN N'Fallback: chamado nasceu no grupo A2B/Protect4'
        ELSE N'Sem início de contagem identificado'
    END AS fonte_inicio_contagem
FROM #FAIA_EscopoIds AS e
JOIN #PBI_Base AS b
    ON b.id = e.id
LEFT JOIN #FAIA_TransfGrupo_FAIA_P4 AS tg
    ON tg.id = b.id;

IF OBJECT_ID('tempdb..#FAIA_CapturaStatus') IS NOT NULL DROP TABLE #FAIA_CapturaStatus;

SELECT
    b.id,
    MIN(al.system_time) AS captura_status_epoch
INTO #FAIA_CapturaStatus
FROM #FAIA_EscopoIds AS e
JOIN #PBI_Base AS b
    ON b.id = e.id
JOIN #FAIA_InicioContagemA2B AS ic
    ON ic.id = b.id
JOIN #PBI_LogEscopo AS al
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

CREATE UNIQUE CLUSTERED INDEX IX_CapturaStatus_id ON #FAIA_CapturaStatus(id);

-- Fallback de captura, também por GRUPO (sem depender de membro):
-- primeira atividade registrada após a entrada no grupo A2B/Protect4, exceto as
-- próprias transferências de grupo (type 'TR'), que não representam atendimento.
IF OBJECT_ID('tempdb..#FAIA_CapturaAtividade') IS NOT NULL DROP TABLE #FAIA_CapturaAtividade;

SELECT
    b.id,
    MIN(al.system_time) AS primeira_atividade_epoch
INTO #FAIA_CapturaAtividade
FROM #FAIA_EscopoIds AS e
JOIN #PBI_Base AS b
    ON b.id = e.id
JOIN #FAIA_InicioContagemA2B AS ic
    ON ic.id = b.id
JOIN #PBI_LogEscopo AS al
    ON al.call_req_id = b.persid
WHERE al.system_time IS NOT NULL
  AND ic.inicio_contagem_epoch IS NOT NULL
  AND al.system_time >= ic.inicio_contagem_epoch
  AND ISNULL(al.type, N'') <> 'TR'
GROUP BY b.id;

CREATE UNIQUE CLUSTERED INDEX IX_CapturaAtividade_id ON #FAIA_CapturaAtividade(id);

IF OBJECT_ID('tempdb..#FAIA_Captura') IS NOT NULL DROP TABLE #FAIA_Captura;

SELECT
    e.id,
    COALESCE(cs.captura_status_epoch, caf.primeira_atividade_epoch) AS captura_epoch,
    CASE
        WHEN cs.captura_status_epoch IS NOT NULL THEN N'ST para Em andamento após entrada no grupo A2B/Protect4'
        WHEN caf.primeira_atividade_epoch IS NOT NULL THEN N'Fallback: primeira atividade após entrada no grupo A2B/Protect4'
        ELSE N'Sem captura identificada'
    END AS fonte_captura
INTO #FAIA_Captura
FROM #FAIA_EscopoIds AS e
LEFT JOIN #FAIA_CapturaStatus AS cs
    ON cs.id = e.id
LEFT JOIN #FAIA_CapturaAtividade AS caf
    ON caf.id = e.id;

CREATE UNIQUE CLUSTERED INDEX IX_Captura_id ON #FAIA_Captura(id);

IF OBJECT_ID('tempdb..#FAIA_Reabertura') IS NOT NULL DROP TABLE #FAIA_Reabertura;

SELECT DISTINCT
    b.id,
    CAST(1 AS bit) AS houve_reabertura
INTO #FAIA_Reabertura
FROM #FAIA_EscopoIds AS e
JOIN #PBI_Base AS b
    ON b.id = e.id
JOIN #PBI_LogEscopo AS al
    ON al.call_req_id = b.persid
WHERE
    CONVERT(nvarchar(max), ISNULL(al.type, N'')) COLLATE Latin1_General_CI_AI LIKE N'%reab%'
    OR CONVERT(nvarchar(max), ISNULL(al.description, N'')) COLLATE Latin1_General_CI_AI LIKE N'%reabert%'
    OR CONVERT(nvarchar(max), ISNULL(al.action_desc, N'')) COLLATE Latin1_General_CI_AI LIKE N'%reabert%';

CREATE UNIQUE CLUSTERED INDEX IX_Reabertura_id ON #FAIA_Reabertura(id);

--------------------------------------------------------------------------------
-- [7] Base final com datas em horário do Brasil
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#FAIA_BaseEscopo') IS NOT NULL DROP TABLE #FAIA_BaseEscopo;

SELECT
    b.*,
    e.FonteFornecedor,
    ic.inicio_contagem_epoch,
    ic.fonte_inicio_contagem,
    COALESCE(c.captura_epoch, ic.inicio_contagem_epoch) AS captura_epoch,
    CASE WHEN ic.inicio_contagem_epoch IS NULL THEN NULL
         ELSE DATEADD(HOUR, -@PBI_HorasBrasilParaUTC, DATEADD(SECOND, ic.inicio_contagem_epoch, @PBI_Epoch))
    END AS data_abertura_br,
    CASE WHEN COALESCE(c.captura_epoch, ic.inicio_contagem_epoch) IS NULL THEN NULL
         ELSE DATEADD(HOUR, -@PBI_HorasBrasilParaUTC, DATEADD(SECOND, COALESCE(c.captura_epoch, ic.inicio_contagem_epoch), @PBI_Epoch))
    END AS data_captura_br,
    CASE WHEN b.close_date IS NULL THEN NULL
         ELSE DATEADD(HOUR, -@PBI_HorasBrasilParaUTC, DATEADD(SECOND, b.close_date, @PBI_Epoch))
    END AS data_fechamento_br,
    CASE WHEN r.houve_reabertura = 1 THEN N'Sim' ELSE N'Não' END AS indicador_reabertura
INTO #FAIA_BaseEscopo
FROM #FAIA_EscopoIds AS e
JOIN #PBI_Base AS b
    ON b.id = e.id
LEFT JOIN #FAIA_InicioContagemA2B AS ic
    ON ic.id = b.id
LEFT JOIN #FAIA_Captura AS c
    ON c.id = b.id
LEFT JOIN #FAIA_Reabertura AS r
    ON r.id = b.id;

CREATE UNIQUE CLUSTERED INDEX IX_BaseEscopo_id ON #FAIA_BaseEscopo(id);

--------------------------------------------------------------------------------
-- [8] Números para cálculo de horas comerciais 08:00-20:00, segunda a sexta
--------------------------------------------------------------------------------
DECLARE @FAIA_MaxDiasFAIA int =
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
    FROM #FAIA_BaseEscopo
);

IF OBJECT_ID('tempdb..#FAIA_Nums') IS NOT NULL DROP TABLE #FAIA_Nums;
CREATE TABLE #FAIA_Nums (n int NOT NULL PRIMARY KEY);

INSERT INTO #FAIA_Nums(n)
SELECT TOP (@FAIA_MaxDiasFAIA + 1)
       ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1
FROM sys.all_objects a
CROSS JOIN sys.all_objects b;

--------------------------------------------------------------------------------
-- [8.1] Quantidade de logs por chamado (coluna auxiliar de conferência)
--
-- Conta TODOS os registros de #PBI_LogEscopo do chamado, sem filtro por tipo:
-- INIT, ST, TR, SOLN, CL, LOG, FLD, SRVY_SENT, ATTACHTDOC e quaisquer outros.
-- Regra: 1 registro em #PBI_LogEscopo = 1 log. Não é a contagem dos logs que
-- participam do cálculo do FAIA; é o total bruto, para conferência.
--
-- A agregação é feita AQUI, por chamado, justamente para que o SELECT final não
-- precise fazer JOIN direto com #PBI_LogEscopo — o que multiplicaria a linha do
-- chamado pela quantidade de logs. O GROUP BY b.id mais o índice UNIQUE abaixo
-- garantem, estruturalmente, no máximo uma linha por chamado.
--
-- LEFT JOIN + COUNT(al.call_req_id): chamado sem nenhum log conta 0, não NULL
-- (COUNT de coluna ignora os NULL gerados pelo LEFT JOIN sem correspondência).
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#FAIA_QtdLogs') IS NOT NULL DROP TABLE #FAIA_QtdLogs;

SELECT
    b.id,
    COUNT_BIG(al.call_req_id) AS quantidade_logs
INTO #FAIA_QtdLogs
FROM #FAIA_EscopoIds AS e
JOIN #PBI_Base AS b
    ON b.id = e.id
LEFT JOIN #PBI_LogEscopo AS al
    ON al.call_req_id = b.persid
GROUP BY b.id;

CREATE UNIQUE CLUSTERED INDEX IX_QtdLogs_id ON #FAIA_QtdLogs(id);

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
    FROM #FAIA_BaseEscopo AS b
    LEFT JOIN #PBI_SLA AS sl
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
                FROM #FAIA_Nums AS n
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
                        WHEN EXISTS (SELECT 1 FROM #PBI_FeriadosFixos fx WHERE fx.mes_dia = d.mes_dia)
                          OR EXISTS (SELECT 1 FROM #PBI_FeriadosPorData fd WHERE fd.data = d.dt_date)
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
            -- Janela COMERCIAL: @PBI_HoraInicioComercial a @PBI_HoraFimComercial
            CROSS APPLY (
                SELECT
                    ini_calc = CASE WHEN b.data_abertura_br > DATEADD(HOUR, @PBI_HoraInicioComercial, CAST(d.dt_date AS datetime2(0)))
                                    THEN b.data_abertura_br ELSE DATEADD(HOUR, @PBI_HoraInicioComercial, CAST(d.dt_date AS datetime2(0))) END,
                    fim_calc = CASE WHEN b.data_captura_br  < DATEADD(HOUR, @PBI_HoraFimComercial,    CAST(d.dt_date AS datetime2(0)))
                                    THEN b.data_captura_br  ELSE DATEADD(HOUR, @PBI_HoraFimComercial,  CAST(d.dt_date AS datetime2(0))) END
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
    -- Chave interna do chamado. Usada apenas para associar FAIA e FARC no
    -- resultado final; nao e exposta ao Power BI.
    f.id AS [__id],
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
    -- Os timestamps são os já convertidos para horário do Brasil em #FAIA_BaseEscopo
    -- (data_abertura_br / data_captura_br): NÃO há segunda conversão de fuso.
    --------------------------------------------------------------------------
    CONVERT(varchar(8), f.data_abertura_br, 108) AS [Hora da Abertura],

    -- Mesmo marco de captura usado no cálculo de [Tempo Primeiro Atendimento]:
    -- a coluna data_captura_br de #FAIA_BaseEscopo. Não existe segunda definição de
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

    -- Total bruto de registros em #PBI_LogEscopo, já agregado por chamado em [8.1].
    -- O ISNULL cobre apenas o caso teórico de o chamado não constar de #FAIA_QtdLogs;
    -- chamados sem log já saem de lá com 0.
    ISNULL(ql.quantidade_logs, 0) AS [Quantidade de Logs],

    -- Versoes NUMERICAS dos tempos, em segundos. As colunas HH:MM:SS acima sao
    -- texto e servem para leitura; estas servem para medidas, filtros numericos
    -- e agregacoes no Power BI. Mesmo valor, sem reconversao.
    f.tempo_primeiro_seg    AS [Tempo Primeiro Atendimento (s)],
    f.primeiro_excedido_seg AS [Primeiro Atendimento Excedido (s)]
INTO #FAIA_Resultado
FROM Final AS f
LEFT JOIN #FAIA_QtdLogs AS ql
    ON ql.id = f.id;

CREATE UNIQUE CLUSTERED INDEX IX_FAIA_Resultado_id ON #FAIA_Resultado([__id]);

-- As colunas [nHR_FAIA] e [FAIA] ficam no SELECT final para manter o layout esperado pelo relatório.
-- As cinco colunas auxiliares ([Hora da Abertura], [Hora da Captura], [Dia da
-- Semana da Abertura], [Dia da Semana da Captura] e [Quantidade de Logs]) vêm
-- depois delas, no fim do SELECT, e existem somente nesta consulta FAIA Protect4.


--------------------------------------------------------------------------------
-- PARTE 2: FARC  (motor de atendimento/resolucao - preservado)
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- [3] Escopo do fornecedor
--
-- Regra oficial: chamado pertence ao fornecedor quando o grupo atual do chamado
-- é o grupo A2B/Protect4. Não use categoria como filtro principal.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#FARC_EscopoIds') IS NOT NULL DROP TABLE #FARC_EscopoIds;
CREATE TABLE #FARC_EscopoIds (
    id int NOT NULL PRIMARY KEY,
    FonteFornecedor nvarchar(50) NOT NULL
);

INSERT INTO #FARC_EscopoIds(id, FonteFornecedor)
SELECT b.id, N'Grupo atual A2B/Protect4'
FROM #PBI_Base AS b
WHERE b.group_id = @PBI_FornecedorGrupo
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
IF OBJECT_ID('tempdb..#FARC_EntradaGrupo') IS NOT NULL DROP TABLE #FARC_EntradaGrupo;
IF OBJECT_ID('tempdb..#FARC_EntradaGrupoCandidato') IS NOT NULL DROP TABLE #FARC_EntradaGrupoCandidato;

--------------------------------------------------------------------------------
-- [4.1] Entrada efetiva no grupo A2B/Protect4
--
-- Correção real aplicada após reanálise dos chamados 1693946, 1693751,
-- 1694180, 1692381 e 1691161.
--
-- O erro da versão anterior foi tentar descobrir a entrada no fornecedor apenas
-- por texto livre do act_log.description/action_desc. Nos logs exportados, o
-- marco correto é a mudança de GRUPO; porém a linha exportada aparece apenas
-- como ""Transferir"", sem expor no XLS o detalhe do destino. Por isso o texto do
-- act_log pode não bater, e a consulta cai no open_date ou em uma transferência
-- anterior.
--
-- Nesta versão, a ordem de confiança é:
--   1) View_Audit_Group, quando existir: fonte própria de histórico de grupo.
--   2) audit_log direto, quando existir: attr_name de grupo e attr_after_val do
--      grupo do fornecedor.
--   3) act_log textual: apenas fallback, com filtro estrito de transferência de
--      GRUPO, sem aceitar qualquer ""A2B"" genérico.
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
CREATE TABLE #FARC_EntradaGrupoCandidato (
    id                   int NOT NULL,
    entrada_grupo_epoch  int NOT NULL,
    prioridade_fonte     tinyint NOT NULL,
    fonte_entrada        nvarchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
    detalhe_entrada      nvarchar(4000) COLLATE DATABASE_DEFAULT NULL
);

DECLARE @PBI_FornecedorGrupoHex nvarchar(100) = CONVERT(nvarchar(100), @PBI_FornecedorGrupo, 1);
DECLARE @PBI_FornecedorGrupoHexSem0x nvarchar(100) = CASE
    WHEN CONVERT(nvarchar(100), @PBI_FornecedorGrupo, 1) LIKE N'0x%'
        THEN SUBSTRING(CONVERT(nvarchar(100), @PBI_FornecedorGrupo, 1), 3, 200)
    ELSE CONVERT(nvarchar(100), @PBI_FornecedorGrupo, 1)
END;

--------------------------------------------------------------------------------
-- Fonte 1: View_Audit_Group
-- CA SDM fornece esta view avançada para histórico de permanência por grupo.
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.View_Audit_Group', N'V') IS NOT NULL
BEGIN
    DECLARE @FARC_sqlViewAuditGroup nvarchar(max) = N'
        INSERT INTO #FARC_EntradaGrupoCandidato
            (id, entrada_grupo_epoch, prioridade_fonte, fonte_entrada, detalhe_entrada)
        SELECT
            b.id,
            TRY_CONVERT(int, vag.from_time) AS entrada_grupo_epoch,
            CONVERT(tinyint, 10) AS prioridade_fonte,
            N''View_Audit_Group'' AS fonte_entrada,
            CONCAT(N''to_val='', CONVERT(nvarchar(4000), vag.to_val)) AS detalhe_entrada
        FROM #FARC_EscopoIds AS e
        JOIN #PBI_Base AS b
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
              OR UPPER(tv.to_val_txt) LIKE N''%'' + UPPER(@PBI_FornecedorGrupoHex) + N''%''
              OR UPPER(tv.to_val_txt) LIKE N''%'' + UPPER(@PBI_FornecedorGrupoHexSem0x) + N''%''
          );';

    EXEC sp_executesql
        @FARC_sqlViewAuditGroup,
        N'@PBI_FornecedorGrupoHex nvarchar(100), @PBI_FornecedorGrupoHexSem0x nvarchar(100)',
        @PBI_FornecedorGrupoHex = @PBI_FornecedorGrupoHex,
        @PBI_FornecedorGrupoHexSem0x = @PBI_FornecedorGrupoHexSem0x;
END;

--------------------------------------------------------------------------------
-- Fonte 2: audit_log direto
-- Usado se a view não existir ou não trouxer linhas; compara alteração do campo
-- de grupo com o destino do fornecedor.
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.audit_log', N'U') IS NOT NULL
BEGIN
    DECLARE @FARC_sqlAuditLogGrupo nvarchar(max) = N'
        INSERT INTO #FARC_EntradaGrupoCandidato
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
        FROM #FARC_EscopoIds AS e
        JOIN #PBI_Base AS b
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
              OR UPPER(av.after_val_txt) LIKE N''%'' + UPPER(@PBI_FornecedorGrupoHex) + N''%''
              OR UPPER(av.after_val_txt) LIKE N''%'' + UPPER(@PBI_FornecedorGrupoHexSem0x) + N''%''
          );';

    EXEC sp_executesql
        @FARC_sqlAuditLogGrupo,
        N'@PBI_FornecedorGrupoHex nvarchar(100), @PBI_FornecedorGrupoHexSem0x nvarchar(100)',
        @PBI_FornecedorGrupoHex = @PBI_FornecedorGrupoHex,
        @PBI_FornecedorGrupoHexSem0x = @PBI_FornecedorGrupoHexSem0x;
END;

--------------------------------------------------------------------------------
-- Fonte 3: act_log textual estrito
-- Fallback. Não usa ""para%A2B%"" genérico, pois isso captura transferências que
-- não são de grupo. Só entra quando o texto indicar explicitamente GRUPO.
--------------------------------------------------------------------------------
INSERT INTO #FARC_EntradaGrupoCandidato
    (id, entrada_grupo_epoch, prioridade_fonte, fonte_entrada, detalhe_entrada)
SELECT
    b.id,
    al.system_time AS entrada_grupo_epoch,
    CONVERT(tinyint, 5) AS prioridade_fonte,
    N'act_log.TR textual exato' AS fonte_entrada,
    LEFT(txt.texto_log, 4000) AS detalhe_entrada
FROM #FARC_EscopoIds AS e
JOIN #PBI_Base AS b
    ON b.id = e.id
JOIN #PBI_LogEscopo AS al
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
     OR UPPER(CONVERT(nvarchar(max), txt.texto_log)) LIKE N'%' + UPPER(@PBI_FornecedorGrupoHex) + N'%'
     OR UPPER(CONVERT(nvarchar(max), txt.texto_log)) LIKE N'%' + UPPER(@PBI_FornecedorGrupoHexSem0x) + N'%'
  )
  AND (
        txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%para%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%to%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%Novo valor%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%New Value%'
     OR txt.texto_log COLLATE Latin1_General_CI_AI LIKE N'%->%'
  );

CREATE INDEX IX_EntradaGrupoCandidato_id_epoch
    ON #FARC_EntradaGrupoCandidato(id, prioridade_fonte, entrada_grupo_epoch);

;WITH EscolhaEntrada AS (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY c.id
            ORDER BY c.prioridade_fonte ASC, c.entrada_grupo_epoch DESC
        ) AS rn
    FROM #FARC_EntradaGrupoCandidato AS c
)
SELECT
    id,
    entrada_grupo_epoch,
    fonte_entrada,
    detalhe_entrada
INTO #FARC_EntradaGrupo
FROM EscolhaEntrada
WHERE rn = 1;

CREATE UNIQUE CLUSTERED INDEX IX_EntradaGrupo_id ON #FARC_EntradaGrupo(id);

IF OBJECT_ID('tempdb..#FARC_InicioContagemA2B_FARC_P4') IS NOT NULL DROP TABLE #FARC_InicioContagemA2B_FARC_P4;

CREATE TABLE #FARC_InicioContagemA2B_FARC_P4 (
    id int NOT NULL PRIMARY KEY,
    inicio_contagem_epoch int NULL,
    fonte_inicio_contagem nvarchar(200) NOT NULL,
    detalhe_inicio_contagem nvarchar(4000) COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #FARC_InicioContagemA2B_FARC_P4 (id, inicio_contagem_epoch, fonte_inicio_contagem, detalhe_inicio_contagem)
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
FROM #FARC_EscopoIds AS e
JOIN #PBI_Base AS b
    ON b.id = e.id
LEFT JOIN #FARC_EntradaGrupo AS eg
    ON eg.id = b.id;

IF OBJECT_ID('tempdb..#FARC_CapturaStatus') IS NOT NULL DROP TABLE #FARC_CapturaStatus;

SELECT
    b.id,
    MIN(al.system_time) AS captura_status_epoch
INTO #FARC_CapturaStatus
FROM #FARC_EscopoIds AS e
JOIN #PBI_Base AS b
    ON b.id = e.id
JOIN #FARC_InicioContagemA2B_FARC_P4 AS ic
    ON ic.id = b.id
JOIN #PBI_LogEscopo AS al
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
  -- Captura = primeira ida PARA ""Em andamento"" depois da entrada na A2B.
  -- Não filtra por membro atual do grupo, porque o histórico precisa refletir
  -- o evento do chamado, não a composição atual do grupo.
  -- Importante: não basta o texto conter ""Em andamento"", pois linhas como
  -- ""Em andamento -> Agendado"" ou ""Em andamento -> Aguarda atendimento""
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

CREATE UNIQUE CLUSTERED INDEX IX_CapturaStatus_id ON #FARC_CapturaStatus(id);

-- (Removido: #FARC_CapturaAtividadeFornecedor. Era calculado e nunca usado no cálculo
--  final; eliminá-lo tira uma leitura inteira do act_log sem mudar resultado.)

IF OBJECT_ID('tempdb..#FARC_Captura') IS NOT NULL DROP TABLE #FARC_Captura;

SELECT
    e.id,
    COALESCE(cs.captura_status_epoch, ic.inicio_contagem_epoch) AS captura_epoch,
    CASE
        WHEN cs.captura_status_epoch IS NOT NULL THEN N'ST com destino exato para Em andamento'
        WHEN ic.inicio_contagem_epoch IS NOT NULL THEN N'Fallback: Data Abertura FARC; não houve ST posterior para Em andamento'
        ELSE N'Sem captura identificada'
    END AS fonte_captura
INTO #FARC_Captura
FROM #FARC_EscopoIds AS e
LEFT JOIN #FARC_InicioContagemA2B_FARC_P4 AS ic
    ON ic.id = e.id
LEFT JOIN #FARC_CapturaStatus AS cs
    ON cs.id = e.id;

CREATE UNIQUE CLUSTERED INDEX IX_Captura_id ON #FARC_Captura(id);

IF OBJECT_ID('tempdb..#FARC_Reabertura') IS NOT NULL DROP TABLE #FARC_Reabertura;

SELECT DISTINCT
    b.id,
    CAST(1 AS bit) AS houve_reabertura
INTO #FARC_Reabertura
FROM #FARC_EscopoIds AS e
JOIN #PBI_Base AS b
    ON b.id = e.id
JOIN #PBI_LogEscopo AS al
    ON al.call_req_id = b.persid
WHERE
    CONVERT(nvarchar(max), ISNULL(al.type, N'')) COLLATE Latin1_General_CI_AI LIKE N'%reab%'
    OR CONVERT(nvarchar(max), ISNULL(al.description, N'')) COLLATE Latin1_General_CI_AI LIKE N'%reabert%'
    OR CONVERT(nvarchar(max), ISNULL(al.action_desc, N'')) COLLATE Latin1_General_CI_AI LIKE N'%reabert%';

CREATE UNIQUE CLUSTERED INDEX IX_Reabertura_id ON #FARC_Reabertura(id);

--------------------------------------------------------------------------------
-- [5] Base final com datas em horário do Brasil
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#FARC_BaseEscopo_FARC_P4') IS NOT NULL DROP TABLE #FARC_BaseEscopo_FARC_P4;

SELECT
    b.*,
    e.FonteFornecedor,
    ic.inicio_contagem_epoch,
    ic.fonte_inicio_contagem,
    ic.detalhe_inicio_contagem,
    COALESCE(c.captura_epoch, ic.inicio_contagem_epoch) AS captura_epoch,
    CASE WHEN ic.inicio_contagem_epoch IS NULL THEN NULL
         ELSE DATEADD(HOUR, -@PBI_HorasBrasilParaUTC, DATEADD(SECOND, ic.inicio_contagem_epoch, @PBI_Epoch))
    END AS data_abertura_br,
    CASE WHEN COALESCE(c.captura_epoch, ic.inicio_contagem_epoch) IS NULL THEN NULL
         ELSE DATEADD(HOUR, -@PBI_HorasBrasilParaUTC, DATEADD(SECOND, COALESCE(c.captura_epoch, ic.inicio_contagem_epoch), @PBI_Epoch))
    END AS data_captura_br,
    CASE WHEN b.close_date IS NULL THEN NULL
         ELSE DATEADD(HOUR, -@PBI_HorasBrasilParaUTC, DATEADD(SECOND, b.close_date, @PBI_Epoch))
    END AS data_fechamento_br,
    CASE WHEN r.houve_reabertura = 1 THEN N'Sim' ELSE N'Não' END AS indicador_reabertura
INTO #FARC_BaseEscopo_FARC_P4
FROM #FARC_EscopoIds AS e
JOIN #PBI_Base AS b
    ON b.id = e.id
LEFT JOIN #FARC_InicioContagemA2B_FARC_P4 AS ic
    ON ic.id = b.id
LEFT JOIN #FARC_Captura AS c
    ON c.id = b.id
LEFT JOIN #FARC_Reabertura AS r
    ON r.id = b.id;

CREATE UNIQUE CLUSTERED INDEX IX_BaseEscopo_id ON #FARC_BaseEscopo_FARC_P4(id);

--------------------------------------------------------------------------------
-- [6] Fonte de tempo para FARC - regra BO por SLA ativo
--------------------------------------------------------------------------------
-- Regra ajustada para bater com o BO observado no chamado 1693751:
--
--   1) Data Abertura FARC continua sendo a entrada no grupo Fornecedores - A2B.
--   2) Data Captura é a primeira ida PARA ""Em andamento"" depois da entrada na A2B.
--   3) Tempo de Atendimento FARC é tempo decorrido ATIVO, não time_spent.
--   4) O relógio ativo começa em ""Em andamento"" e pausa/termina quando o chamado
--      entra em Agendado, Aguarda atendimento, Em homologação, resolução ou fechamento.
--   5) Quando o chamado sai de Agendado e volta para ""Em andamento"", o relógio retoma.
--   6) A contagem dos trechos ativos respeita a severidade:
--        P1/P2 = corrida
--        P3/P4/P5 = comercial, segunda a sexta, 08:00-20:00.
--
-- Observação: act_log.time_spent não compõe mais o FARC. Ele é mantido apenas
-- para auditoria/comparação.
--------------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#FARC_TerminalFARC') IS NOT NULL DROP TABLE #FARC_TerminalFARC;

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
INTO #FARC_TerminalFARC
FROM #FARC_BaseEscopo_FARC_P4 AS b;

CREATE UNIQUE CLUSTERED INDEX IX_TerminalFARC_id ON #FARC_TerminalFARC(id);

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
-- Extrai do texto ""... Grupo de '<origem>' para '<destino>' ..."" mesmo quando
-- vem combinado com ""Transferir Responsável de '...' para '...'"": ancora em
-- 'Grupo de' e lê os dois primeiros valores entre aspas após esse ponto.
IF OBJECT_ID('tempdb..#FARC_GrupoRaw') IS NOT NULL DROP TABLE #FARC_GrupoRaw;
IF OBJECT_ID('tempdb..#FARC_GrupoEventos') IS NOT NULL DROP TABLE #FARC_GrupoEventos;

-- Passo 1: materializa o texto a partir da ancora 'Grupo de' numa coluna CURTA
-- e BOUNDED (nvarchar(400)). Isso quebra a arvore de expressao e evita o erro
-- ""expression services limit"" (Msg 8632) que ocorre ao encadear muitos
-- CHARINDEX/SUBSTRING sobre nvarchar(max) num unico SELECT.
SELECT
    b.id,
    al.system_time AS ev_epoch,
    al.log_id,
    CONVERT(nvarchar(400), SUBSTRING(t.txt, a.anchor + 8, 400)) AS resto
INTO #FARC_GrupoRaw
FROM #FARC_BaseEscopo_FARC_P4 AS b
JOIN #PBI_LogEscopo AS al
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

CREATE INDEX IX_GrupoRaw_id_epoch ON #FARC_GrupoRaw(id, ev_epoch);

-- Passo 2: parsing dos dois primeiros valores entre aspas (origem e destino)
-- sobre a coluna curta 'resto'. Cada operacao e barata.
SELECT
    g.id,
    g.ev_epoch,
    g.log_id,
    CASE WHEN dest.destino LIKE N'%A2B%' THEN 1 ELSE 0 END AS destino_a2b,
    CASE WHEN orig.origem  LIKE N'%A2B%' THEN 1 ELSE 0 END AS origem_a2b
INTO #FARC_GrupoEventos
FROM #FARC_GrupoRaw AS g
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

CREATE INDEX IX_GrupoEventos_id_epoch ON #FARC_GrupoEventos(id, ev_epoch);

-- [6.3.2] Estado de grupo inicial do chamado (na criação).
-- Se houve mudança de grupo, o estado inicial é a ORIGEM da primeira mudança.
-- Se não houve nenhuma mudança de grupo e a categoria é A2B, nasceu no A2B.
IF OBJECT_ID('tempdb..#FARC_GrupoInicial') IS NOT NULL DROP TABLE #FARC_GrupoInicial;
SELECT
    b.id,
    b.open_date AS t_inicial,
    CASE
        WHEN ge1.origem_a2b IS NOT NULL THEN ge1.origem_a2b
        WHEN b.categoria_sym COLLATE Latin1_General_CI_AI LIKE N'A2B.%' THEN 1
        ELSE 0
    END AS inicial_a2b
INTO #FARC_GrupoInicial
FROM #FARC_BaseEscopo_FARC_P4 AS b
OUTER APPLY (
    SELECT TOP (1) g.origem_a2b
    FROM #FARC_GrupoEventos AS g
    WHERE g.id = b.id
    -- log_id so decide quando segundo e destino_a2b empatam; ver DESEMPATE POR act_log.id
    ORDER BY g.ev_epoch ASC, g.destino_a2b DESC, g.log_id ASC
) AS ge1;

CREATE UNIQUE CLUSTERED INDEX IX_GrupoInicial_id ON #FARC_GrupoInicial(id);

-- [6.3.3] Janelas de posse A2B: ilhas em que o grupo vigente é A2B.
-- A linha de tempo de grupo = estado inicial (open_date) + cada mudança de grupo.
-- O grupo de cada trecho vale até a próxima mudança (ou até o terminal).
-- Mantém só os trechos A2B, recortados no terminal. Trechos da timeline já são
-- disjuntos, então não há sobreposição/duplicidade.
IF OBJECT_ID('tempdb..#FARC_JanelasA2B') IS NOT NULL DROP TABLE #FARC_JanelasA2B;
;WITH timeline AS (
    SELECT id, t_inicial AS t, inicial_a2b AS is_a2b, CONVERT(tinyint, 0) AS ord, CONVERT(int, 0) AS log_id
    FROM #FARC_GrupoInicial
    UNION ALL
    SELECT id, ev_epoch AS t, destino_a2b AS is_a2b, CONVERT(tinyint, 1) AS ord, log_id
    FROM #FARC_GrupoEventos
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
INTO #FARC_JanelasA2B
FROM ordered AS o
JOIN #FARC_TerminalFARC AS tf
    ON tf.id = o.id
WHERE o.is_a2b = 1
  AND tf.terminal_epoch IS NOT NULL
  AND o.t < tf.terminal_epoch
  AND (CASE WHEN COALESCE(o.next_t, tf.terminal_epoch) > tf.terminal_epoch
            THEN tf.terminal_epoch ELSE COALESCE(o.next_t, tf.terminal_epoch) END) > o.t;

CREATE INDEX IX_JanelasA2B_id ON #FARC_JanelasA2B(id, win_inicio_epoch);

-- [6.3.4] Eventos de STATUS com origem e destino, marcando os ativos.
-- Ativo = destino 'Em andamento' ou 'Aberto, aguarda atendimento'.
-- Atenção: 'Aberto, aguarda atendimento' (fila inicial) é ativo; 'Aguarda
-- atendimento' (espera pós-trabalho) NÃO é. O padrão usa o prefixo 'Aberto'.
IF OBJECT_ID('tempdb..#FARC_StatusRaw') IS NOT NULL DROP TABLE #FARC_StatusRaw;
IF OBJECT_ID('tempdb..#FARC_StatusEvA2B') IS NOT NULL DROP TABLE #FARC_StatusEvA2B;

-- Passo 1: materializa, a partir da ancora 'alterado de'/'changed from', uma
-- coluna CURTA e BOUNDED com origem e destino. Evita o erro Msg 8632
-- (expression services limit) que ocorria ao encadear muitos CHARINDEX/SUBSTRING
-- sobre nvarchar(max) num unico SELECT (era a causa do erro na linha do #FARC_StatusEvA2B).
SELECT
    b.id,
    al.system_time AS ev_epoch,
    al.log_id,
    CONVERT(nvarchar(400), SUBSTRING(t.txt, a.anchor, 400)) AS resto
INTO #FARC_StatusRaw
FROM #FARC_BaseEscopo_FARC_P4 AS b
JOIN #PBI_LogEscopo AS al
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
  -- So registros de status do proprio chamado. REL_TICKET traz o status de uma
  -- mudanca relacionada (""Requisicao de mudanca: ... alterado de 'RDM' para
  -- 'Aprovada'"") e nao pode virar status do chamado.
  AND al.[type] IN ('ST', 'RE', 'RO', 'CL', 'CLREQ')
  AND (b.close_date IS NULL OR al.system_time <= b.close_date);

CREATE INDEX IX_StatusRaw_id_epoch ON #FARC_StatusRaw(id, ev_epoch);

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
    -- viaja com o chamado e conta ao entrar na A2B) e, abaixo, se e 'Em andamento'.
    -- As duas marcas decidem, em [6.3.6], o que conta quando o status ativo ja
    -- vinha de antes da entrada na A2B.
    CASE WHEN dest.destino COLLATE Latin1_General_CI_AI LIKE N'Aberto%aguarda%atendimento%'
         THEN 1 ELSE 0 END AS destino_aberto,
    CASE WHEN orig.origem COLLATE Latin1_General_CI_AI LIKE N'Aberto%aguarda%atendimento%'
         THEN 1 ELSE 0 END AS origem_aberto,
    CASE WHEN dest.destino COLLATE Latin1_General_CI_AI IN (N'Em andamento', N'In Progress')
         THEN 1 ELSE 0 END AS destino_andamento,
    CASE WHEN orig.origem COLLATE Latin1_General_CI_AI IN (N'Em andamento', N'In Progress')
         THEN 1 ELSE 0 END AS origem_andamento
INTO #FARC_StatusEvA2B
FROM #FARC_StatusRaw AS s
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
IF OBJECT_ID('tempdb..#FARC_SolnReaberturaA2B') IS NOT NULL DROP TABLE #FARC_SolnReaberturaA2B;
SELECT
    b.id,
    al.system_time AS ev_epoch,
    al.log_id
INTO #FARC_SolnReaberturaA2B
FROM #FARC_BaseEscopo_FARC_P4 AS b
JOIN #PBI_LogEscopo AS al
    ON al.call_req_id = b.persid
CROSS APPLY (
    SELECT TOP (1) s.resto
    FROM #FARC_StatusRaw AS s
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
INSERT INTO #FARC_StatusEvA2B (id, ev_epoch, log_id, destino_ativo, origem_ativo, destino_aberto, origem_aberto, destino_andamento, origem_andamento)
SELECT sr.id, sr.ev_epoch, sr.log_id, 0, 1, 0, 1, 0, 0
FROM #FARC_SolnReaberturaA2B AS sr;

CREATE INDEX IX_StatusEvA2B_id_epoch ON #FARC_StatusEvA2B(id, ev_epoch);

-- [6.3.5] Segmentos de status ATIVOS (em epoch), recortados no terminal.
-- Inclui o segmento inicial [open_date, primeiro evento de status] cujo status é
-- a ORIGEM do primeiro evento (status de criação). Para chamados sem nenhum
-- evento de status, o segmento é [open_date, terminal] com o status de criação
-- 'Aberto, aguarda atendimento' (ativo).
IF OBJECT_ID('tempdb..#FARC_SegAtivoA2B') IS NOT NULL DROP TABLE #FARC_SegAtivoA2B;
;WITH ev AS (
    SELECT
        -- DESEMPATE POR act_log.id (2026-09-18). O SDM grava o tempo em SEGUNDOS
        -- inteiros e a automacao registra rajadas de mudanca de status no mesmo
        -- segundo. Ordenar so pelo segundo deixava a ordem da rajada a criterio do
        -- SQL Server, e o FARC variava de uma execucao para outra. act_log.id e a
        -- sequencia de gravacao: na ordem (segundo, id) a cadeia origem->destino fica
        -- consistente em 16.114 de 16.115 pares medidos.
        id, ev_epoch, destino_ativo, destino_aberto, destino_andamento,
        LEAD(ev_epoch) OVER (PARTITION BY id ORDER BY ev_epoch, log_id) AS prox
    FROM #FARC_StatusEvA2B
),
prim AS (
    SELECT id, MIN(ev_epoch) AS primeiro_epoch FROM #FARC_StatusEvA2B GROUP BY id
),
prim_orig AS (
    SELECT se.id, se.origem_ativo, se.origem_aberto, se.origem_andamento
    FROM #FARC_StatusEvA2B AS se
    JOIN prim AS p ON p.id = se.id AND p.primeiro_epoch = se.ev_epoch
),
seg AS (
    -- segmentos a partir de cada evento (status de destino vale até o próximo)
    SELECT e.id, e.ev_epoch AS ini, COALESCE(e.prox, tf.terminal_epoch) AS fim,
           e.destino_ativo AS ativo, e.destino_aberto AS aberto_fila, e.destino_andamento AS em_andamento
    FROM ev AS e
    JOIN #FARC_TerminalFARC AS tf ON tf.id = e.id

    UNION ALL

    -- segmento inicial (criação -> primeiro evento), status = origem do 1o evento
    SELECT b.id, b.open_date AS ini, p.primeiro_epoch AS fim,
           MAX(po.origem_ativo) AS ativo, MAX(po.origem_aberto) AS aberto_fila, MAX(po.origem_andamento) AS em_andamento
    FROM #FARC_BaseEscopo_FARC_P4 AS b
    JOIN prim AS p ON p.id = b.id
    JOIN prim_orig AS po ON po.id = b.id
    WHERE b.open_date IS NOT NULL
    GROUP BY b.id, b.open_date, p.primeiro_epoch

    UNION ALL

    -- chamados sem nenhum evento de status: status de criação o tempo todo.
    -- Criação = 'Aberto, aguarda atendimento' (fila), logo aberto_fila = 1.
    SELECT b.id, b.open_date AS ini, tf.terminal_epoch AS fim, CONVERT(int, 1) AS ativo,
           CONVERT(int, 1) AS aberto_fila, CONVERT(int, 0) AS em_andamento
    FROM #FARC_BaseEscopo_FARC_P4 AS b
    JOIN #FARC_TerminalFARC AS tf ON tf.id = b.id
    WHERE b.open_date IS NOT NULL
      AND tf.terminal_epoch IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM #FARC_StatusEvA2B AS se WHERE se.id = b.id)
)
SELECT
    s.id,
    s.ini,
    CASE WHEN s.fim > tf.terminal_epoch THEN tf.terminal_epoch ELSE s.fim END AS fim,
    s.aberto_fila,
    s.em_andamento
INTO #FARC_SegAtivoA2B
FROM seg AS s
JOIN #FARC_TerminalFARC AS tf ON tf.id = s.id
WHERE s.ativo = 1
  AND tf.terminal_epoch IS NOT NULL
  AND (CASE WHEN s.fim > tf.terminal_epoch THEN tf.terminal_epoch ELSE s.fim END) > s.ini;

CREATE INDEX IX_SegAtivoA2B_id ON #FARC_SegAtivoA2B(id, ini);

-- [6.3.5b] Piso do Inicial/Criacao.
-- O BO desconta o ""Tempo Gasto"" lancado no evento de criacao (Inicial). Esse
-- tempo representa o processamento/fila inicial que o BO nao conta como
-- atendimento. Aqui materializamos o piso = open_date + tempo_gasto_do_Inicial.
-- A contagem ativa nunca comeca antes desse piso. Para chamados que entraram na
-- A2B por transferencia, o piso fica antes da janela A2B e nao tem efeito; so
-- afeta os que nasceram na A2B (janela comeca na criacao), cortando o pedaco
-- inicial exatamente como o BO. init_gasto = maior time_spent entre os eventos
-- de act_log no instante da criacao (system_time = open_date).
IF OBJECT_ID('tempdb..#FARC_PisoInicial') IS NOT NULL DROP TABLE #FARC_PisoInicial;
SELECT
    b.id,
    b.open_date + ISNULL(ig.init_gasto_seg, 0) AS piso_inicial_epoch
INTO #FARC_PisoInicial
FROM #FARC_BaseEscopo_FARC_P4 AS b
OUTER APPLY (
    SELECT init_gasto_seg = MAX(TRY_CONVERT(int, al.time_spent))
    FROM #PBI_LogEscopo AS al
    WHERE al.call_req_id = b.persid
      AND al.system_time = b.open_date
) AS ig
WHERE b.open_date IS NOT NULL;

CREATE UNIQUE CLUSTERED INDEX IX_PisoInicial_id ON #FARC_PisoInicial(id);

-- [6.3.6] Interseção dos segmentos ativos com as janelas de posse A2B, em
-- horário do Brasil. Cada peça é um trecho realmente contado.
IF OBJECT_ID('tempdb..#FARC_PecasAtivasA2B') IS NOT NULL DROP TABLE #FARC_PecasAtivasA2B;
SELECT
    s.id,
    DATEADD(HOUR, -@PBI_HorasBrasilParaUTC, DATEADD(SECOND, ov.ini_ep, @PBI_Epoch)) AS inicio_br,
    DATEADD(HOUR, -@PBI_HorasBrasilParaUTC, DATEADD(SECOND, ov.fim_ep, @PBI_Epoch)) AS fim_br
INTO #FARC_PecasAtivasA2B
FROM #FARC_SegAtivoA2B AS s
JOIN #FARC_JanelasA2B AS j
    ON j.id = s.id
LEFT JOIN #FARC_PisoInicial AS pi
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
  -- Status ativo que ja vinha de ANTES da entrada na A2B (s.ini < win_inicio):
  --   - a FILA 'Aberto, aguarda atendimento' (aberto_fila = 1) conta;
  --   - o 'Em andamento' herdado (em_andamento = 1) conta;
  --   - o 'Reaberto' herdado nao conta.
  -- Em todos os casos a peca comeca em ov.ini_ep = MAX(inicio do segmento,
  -- entrada na A2B) e termina em MIN(fim do segmento, saida da A2B): nada antes
  -- da entrada nem depois da saida e contado, e as pausas e o terminal ja
  -- cortaram o segmento. Status ativo iniciado dentro da janela conta sempre.
  AND (s.aberto_fila = 1 OR s.em_andamento = 1 OR s.ini >= j.win_inicio_epoch);

CREATE INDEX IX_PecasAtivasA2B_id ON #FARC_PecasAtivasA2B(id);

--------------------------------------------------------------------------------
-- [7] Números para cálculo de horas comerciais 08:00-20:00, segunda a sexta
--------------------------------------------------------------------------------
DECLARE @FARC_MaxDiasFARC int =
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
        FROM #FARC_BaseEscopo_FARC_P4 AS b

        UNION ALL

        SELECT
            dias = CASE
                WHEN p.inicio_br IS NOT NULL
                 AND p.fim_br IS NOT NULL
                 AND p.fim_br >= p.inicio_br
                THEN DATEDIFF(DAY, CAST(p.inicio_br AS date), CAST(p.fim_br AS date))
                ELSE 0
            END
        FROM #FARC_PecasAtivasA2B AS p
    ) AS q
);

IF OBJECT_ID('tempdb..#FARC_Nums') IS NOT NULL DROP TABLE #FARC_Nums;
CREATE TABLE #FARC_Nums (n int NOT NULL PRIMARY KEY);

INSERT INTO #FARC_Nums(n)
SELECT TOP (@FARC_MaxDiasFARC + 1)
       ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1
FROM sys.all_objects a
CROSS JOIN sys.all_objects b;

--------------------------------------------------------------------------------
-- [7.1] MOTOR PRINCIPAL (cont.): soma das peças ativas por janela A2B com regra
--       corrida (P1/P2) ou comercial 08:00-20:00 seg-sex (P3/P4/P5).
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#FARC_TempoAtivoJanelasA2B') IS NOT NULL DROP TABLE #FARC_TempoAtivoJanelasA2B;

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
INTO #FARC_TempoAtivoJanelasA2B
FROM #FARC_BaseEscopo_FARC_P4 AS b
LEFT JOIN #PBI_SLA AS sl
    ON sl.prioridade = b.prioridade_nivel
LEFT JOIN #FARC_TerminalFARC AS t
    ON t.id = b.id
LEFT JOIN #FARC_PecasAtivasA2B AS p
    ON p.id = b.id
OUTER APPLY (
    SELECT segundos_comerciais = COALESCE(SUM(x.segundos_dia), 0)
    FROM (
        SELECT segundos_dia = CASE WHEN janela.fim_calc > janela.ini_calc
                    THEN DATEDIFF(SECOND, janela.ini_calc, janela.fim_calc) ELSE 0 END
        FROM (
            SELECT DATEADD(DAY, n.n, CAST(p.inicio_br AS date)) AS dt
            FROM #FARC_Nums AS n
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
          AND NOT EXISTS (SELECT 1 FROM #PBI_FeriadosFixos ff
                          WHERE ff.mes_dia = RIGHT(CONVERT(char(10), dias.dt, 120), 5))
          AND NOT EXISTS (SELECT 1 FROM #PBI_FeriadosPorData fp
                          WHERE fp.data = CAST(dias.dt AS date))
    ) AS x
) AS bh
GROUP BY b.id, t.terminal_epoch;

CREATE UNIQUE CLUSTERED INDEX IX_TempoAtivoJanelasA2B_id ON #FARC_TempoAtivoJanelasA2B(id);

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
IF OBJECT_ID('tempdb..#FARC_TempoAtendimentoRotina') IS NOT NULL DROP TABLE #FARC_TempoAtendimentoRotina;

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
INTO #FARC_TempoAtendimentoRotina
FROM #FARC_BaseEscopo_FARC_P4 AS b
LEFT JOIN #PBI_SLA AS sl
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
            FROM #FARC_Nums AS n
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
          AND NOT EXISTS (SELECT 1 FROM #PBI_FeriadosFixos ff
                          WHERE ff.mes_dia = RIGHT(CONVERT(char(10), dias.dt, 120), 5))
          AND NOT EXISTS (SELECT 1 FROM #PBI_FeriadosPorData fp
                          WHERE fp.data = CAST(dias.dt AS date))
    ) AS x
) AS bh;

CREATE UNIQUE CLUSTERED INDEX IX_TempoAtendimentoRotina_id ON #FARC_TempoAtendimentoRotina(id);

--------------------------------------------------------------------------------
-- [8B] Motor legado por mudança de status via LEAD
--------------------------------------------------------------------------------
-- Este e o motor base dos chamados nao-rotina (motor unico). Caracteristicas:
--   - considera todos os eventos de status em sequência;
--   - conta cada trecho cujo status de destino é ""Em andamento"" até o próximo
--     evento de status;
--   - usa tempo corrido no trecho, sem recorte comercial;
--   - recorta no intervalo [Data Abertura FARC, fechamento].
--
-- No calculo final ele e combinado (max) com o tempo ativo nas janelas A2B.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#FARC_StatusEventosLead') IS NOT NULL DROP TABLE #FARC_StatusEventosLead;

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
    FROM #FARC_BaseEscopo_FARC_P4 AS b
    JOIN #PBI_LogEscopo AS al
        ON al.call_req_id = b.persid
    WHERE al.system_time IS NOT NULL
      AND al.[type] IN ('ST', 'RE', 'RO', 'CL', 'CLREQ') -- so status do proprio chamado (sem REL_TICKET)
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
    FROM #FARC_SolnReaberturaA2B AS sr
    JOIN #FARC_BaseEscopo_FARC_P4 AS b
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
INTO #FARC_StatusEventosLead
FROM ev;

CREATE INDEX IX_StatusEventosLead_id_epoch ON #FARC_StatusEventosLead(id, ev_epoch);

-- Intervalos em 'Em andamento' (motor LEAD) em horario do Brasil, recortados a
-- [inicio_contagem, fechamento]. Materializados para permitir a janela comercial.
IF OBJECT_ID('tempdb..#FARC_IntervalosLead') IS NOT NULL DROP TABLE #FARC_IntervalosLead;
SELECT
    b.id,
    DATEADD(HOUR, -@PBI_HorasBrasilParaUTC, DATEADD(SECOND, ov.ini_ep, @PBI_Epoch)) AS inicio_br,
    DATEADD(HOUR, -@PBI_HorasBrasilParaUTC, DATEADD(SECOND, ov.fim_ep, @PBI_Epoch)) AS fim_br
INTO #FARC_IntervalosLead
FROM #FARC_BaseEscopo_FARC_P4 AS b
JOIN #FARC_StatusEventosLead AS se
    ON se.id = b.id
CROSS APPLY (
    SELECT
        ini = CASE WHEN se.ev_epoch > b.inicio_contagem_epoch
                   THEN se.ev_epoch ELSE b.inicio_contagem_epoch END,
        fim = CASE WHEN ISNULL(se.prox_epoch, b.close_date) < b.close_date
                   THEN ISNULL(se.prox_epoch, b.close_date) ELSE b.close_date END
) AS clip
JOIN #FARC_JanelasA2B AS j
    ON j.id = b.id
CROSS APPLY (
    -- Recorte por janela: so conta o 'Em andamento' que cai DENTRO de uma janela
    -- de posse A2B, igual ao #FARC_PecasAtivasA2B. 'Em andamento' sob outro grupo
    -- (fora das janelas) nao entra no Tempo de Atendimento da A2B.
    SELECT
        ini_ep = CASE WHEN clip.ini > j.win_inicio_epoch THEN clip.ini ELSE j.win_inicio_epoch END,
        fim_ep = CASE WHEN clip.fim < j.win_fim_epoch    THEN clip.fim    ELSE j.win_fim_epoch    END
) AS ov
WHERE se.is_em_andamento = 1
  AND b.inicio_contagem_epoch IS NOT NULL
  AND b.close_date IS NOT NULL
  AND ov.fim_ep > ov.ini_ep;
CREATE INDEX IX_IntervalosLead_id ON #FARC_IntervalosLead(id);

-- Soma do motor LEAD com a MESMA regra do v10: corrido para P1/P2 e recorte
-- comercial 08:00-20:00 seg-sex para P3/P4/P5. Antes era sempre corrido, o que
-- superestimava incidentes comerciais com trechos fora da janela (ex. 1680955:
-- corrido 0:32:03 vs BO 0:26:20, que e o recorte comercial).
IF OBJECT_ID('tempdb..#FARC_TempoAtendimentoStatusLead') IS NOT NULL DROP TABLE #FARC_TempoAtendimentoStatusLead;
SELECT
    b.id,
    COALESCE(SUM(CASE
        WHEN sl.tipo_resolucao = 'CORRIDA'
            THEN DATEDIFF(SECOND, il.inicio_br, il.fim_br)
        WHEN sl.tipo_resolucao = 'COMERCIAL'
            THEN COALESCE(bh.segundos_comerciais, 0)
        ELSE DATEDIFF(SECOND, il.inicio_br, il.fim_br)
    END), 0) AS tempo_atendimento_status_lead_seg
INTO #FARC_TempoAtendimentoStatusLead
FROM #FARC_BaseEscopo_FARC_P4 AS b
LEFT JOIN #PBI_SLA AS sl
    ON sl.prioridade = b.prioridade_nivel
LEFT JOIN #FARC_IntervalosLead AS il
    ON il.id = b.id
OUTER APPLY (
    SELECT segundos_comerciais = COALESCE(SUM(x.segundos_dia), 0)
    FROM (
        SELECT segundos_dia = CASE WHEN janela.fim_calc > janela.ini_calc
                    THEN DATEDIFF(SECOND, janela.ini_calc, janela.fim_calc) ELSE 0 END
        FROM (
            SELECT DATEADD(DAY, n.n, CAST(il.inicio_br AS date)) AS dt
            FROM #FARC_Nums AS n
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
          AND NOT EXISTS (SELECT 1 FROM #PBI_FeriadosFixos ff
                          WHERE ff.mes_dia = RIGHT(CONVERT(char(10), dias.dt, 120), 5))
          AND NOT EXISTS (SELECT 1 FROM #PBI_FeriadosPorData fp
                          WHERE fp.data = CAST(dias.dt AS date))
    ) AS x
) AS bh
GROUP BY b.id;

CREATE UNIQUE CLUSTERED INDEX IX_TempoAtendimentoStatusLead_id ON #FARC_TempoAtendimentoStatusLead(id);

--------------------------------------------------------------------------------
-- [8C] #FARC_MotorBase_FARC_P4 - motor BASE por chamado (motor unico)
--
--   ROTINA  -> categorias de rotina (passagem de turno / job summary): intervalo
--              Data Abertura FARC -> Fechamento.
--   CONTIDO -> demais: tempo em 'Em andamento'. No calculo final ele e combinado
--              (max) com o tempo ativo nas janelas A2B, que cobre a fila inicial
--              e a reposse. O antigo motor v10 foi removido.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#FARC_MotorBase_FARC_P4') IS NOT NULL DROP TABLE #FARC_MotorBase_FARC_P4;

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
INTO #FARC_MotorBase_FARC_P4
FROM #FARC_BaseEscopo_FARC_P4 AS b
LEFT JOIN #FARC_TempoAtendimentoStatusLead AS tsl ON tsl.id = b.id
LEFT JOIN #FARC_TempoAtendimentoRotina     AS tr  ON tr.id  = b.id;

CREATE UNIQUE CLUSTERED INDEX IX_MotorBase_id ON #FARC_MotorBase_FARC_P4(id);

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
             ELSE DATEADD(HOUR, -@PBI_HorasBrasilParaUTC, DATEADD(SECOND, t.terminal_epoch, @PBI_Epoch))
        END AS data_terminal_br
    FROM #FARC_BaseEscopo_FARC_P4 AS b
    LEFT JOIN #PBI_SLA AS sl
        ON sl.prioridade = b.prioridade_nivel
    LEFT JOIN #FARC_TempoAtendimentoStatusLead AS tsl
        ON tsl.id = b.id
    LEFT JOIN #FARC_TempoAtendimentoRotina AS tr
        ON tr.id = b.id
    LEFT JOIN #FARC_TempoAtivoJanelasA2B AS taj
        ON taj.id = b.id
    LEFT JOIN #FARC_TerminalFARC AS t
        ON t.id = b.id
    -- Motor BASE: mesma selecao que ja produzia os chamados corretos
    -- (rotina -> intervalo; hibrido status-lead em casos especificos; senao v10).
    LEFT JOIN #FARC_MotorBase_FARC_P4 AS rb
        ON rb.id = b.id
    OUTER APPLY (
        SELECT qtd_janelas_a2b = COUNT(*)
        FROM #FARC_JanelasA2B AS j
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
    -- Chave interna do chamado. Usada apenas para associar FAIA e FARC no
    -- resultado final; nao e exposta ao Power BI.
    f.id AS [__id],
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
    END AS [FARC],

    -- Versoes NUMERICAS dos tempos, em segundos (ver nota equivalente no FAIA).
    f.tempo_atendimento_seg    AS [Tempo de Atendimento (s)],
    f.atendimento_excedido_seg AS [Tempo Atendimento Excedido (s)]
INTO #FARC_Resultado
FROM Final AS f;

CREATE UNIQUE CLUSTERED INDEX IX_FARC_Resultado_id ON #FARC_Resultado([__id]);

--------------------------------------------------------------------------------
-- [R] RESULTADO CONSOLIDADO - unico result set
--
-- LINHAS: uma por chamado. A associacao usa a CHAVE INTERNA call_req.id
-- (coluna [__id]), e nao o texto do SDM. As duas tabelas de resultado tem indice
-- UNICO por [__id], portanto o JOIN nao pode multiplicar chamados.
--
-- FULL OUTER JOIN: o escopo do FAIA exige que o chamado ENCERRE no grupo A2B; o
-- do FARC nao. Logo o FAIA e um subconjunto do FARC e um chamado pode existir so
-- do lado FARC. O FULL OUTER JOIN preserva os dois lados sem depender dessa
-- relacao continuar valida. INNER JOIN eliminaria chamados validos.
-- As colunas comuns usam COALESCE para funcionar em qualquer um dos dois casos.
--
-- ORDEM: comuns -> FAIA -> FARC. Nao ha segundo bloco de colunas comuns no fim.
-- Todos os aliases sao unicos.
--
-- TIPOS: datas saem como datetime2; nHR/FAIA/FARC como decimal(18,2);
-- [Quantidade de Logs] como bigint; e cada tempo sai em DUAS formas:
-- o texto HH:MM:SS, para leitura, e o valor em SEGUNDOS, para uso em medidas do
-- Power BI. Nenhuma coluna que precise ser agregada existe apenas como texto.
--
-- Sem ORDER BY: o Power BI nao depende da ordem fisica devolvida pelo banco e a
-- ordenacao de todo o conjunto era custo puro.
--------------------------------------------------------------------------------
SELECT
    -- ===================== COLUNAS COMUNS DO CHAMADO =========================
    COALESCE(faia.[SDM], farc.[SDM]) AS [SDM],
    COALESCE(faia.[Tipo Chamado], farc.[Tipo Chamado]) AS [Tipo Chamado],
    COALESCE(faia.[Severidade], farc.[Severidade]) AS [Severidade],
    COALESCE(faia.[Status], farc.[Status]) AS [Status],
    COALESCE(faia.[Categoria], farc.[Categoria]) AS [Categoria],
    COALESCE(faia.[Responsável Abertura], farc.[Responsável Abertura]) AS [Responsável Abertura],
    COALESCE(faia.[Responsável Atendimento], farc.[Responsável Atendimento]) AS [Responsável Atendimento],
    COALESCE(faia.[Resumo], farc.[Resumo]) AS [Resumo],
    COALESCE(faia.[Data Abertura], farc.[Data Abertura]) AS [Data Abertura],
    COALESCE(faia.[Data Captura], farc.[Data Captura]) AS [Data Captura],
    COALESCE(faia.[Data de Fechamento], farc.[Data de Fechamento]) AS [Data de Fechamento],

    -- Dia da semana deterministico: 1900-01-01 foi uma segunda-feira. Nao depende
    -- de SET LANGUAGE nem de SET DATEFIRST da sessao.
    CASE DATEDIFF(
        DAY,
        '19000101',
        CAST(COALESCE(faia.[Data de Fechamento], farc.[Data de Fechamento]) AS date)
    ) % 7
        WHEN 0 THEN N'Segunda-feira'
        WHEN 1 THEN N'Terça-feira'
        WHEN 2 THEN N'Quarta-feira'
        WHEN 3 THEN N'Quinta-feira'
        WHEN 4 THEN N'Sexta-feira'
        WHEN 5 THEN N'Sábado'
        WHEN 6 THEN N'Domingo'
        ELSE NULL
    END AS [Dia da Semana do Fechamento],

    COALESCE(faia.[Indicador Reabertura], farc.[Indicador Reabertura]) AS [Indicador Reabertura],
    COALESCE(faia.[Acordo Prazo], farc.[Acordo Prazo]) AS [Acordo Prazo],
    COALESCE(faia.[Acordo Qualidade], farc.[Acordo Qualidade]) AS [Acordo Qualidade],
    COALESCE(faia.[Justificativa], farc.[Justificativa]) AS [Justificativa],

    -- ============================ COLUNAS DO FAIA ============================
    -- Mede o PRIMEIRO ATENDIMENTO: da entrada na posse do grupo A2B ate a
    -- primeira ida do status para 'Em andamento'.
    faia.[Tempo Primeiro Atendimento]        AS [Tempo Primeiro Atendimento],
    faia.[Tempo Primeiro Atendimento (s)]    AS [Tempo Primeiro Atendimento (s)],
    faia.[Primeiro Atendimento Excedido]     AS [Primeiro Atendimento Excedido],
    faia.[Primeiro Atendimento Excedido (s)] AS [Primeiro Atendimento Excedido (s)],
    faia.[Meta Primeiro Atendimento]         AS [Meta Primeiro Atendimento],
    faia.[nHR_FAIA]                          AS [nHR_FAIA],
    faia.[FAIA]                              AS [FAIA],

    -- Auxiliares de conferencia, especificas do FAIA. Ficam NULL para chamado que
    -- exista somente no lado FARC (nao encerrou no grupo A2B).
    faia.[Hora da Abertura]           AS [Hora da Abertura],
    faia.[Hora da Captura]            AS [Hora da Captura],
    faia.[Dia da Semana da Abertura]  AS [Dia da Semana da Abertura],
    faia.[Dia da Semana da Captura]   AS [Dia da Semana da Captura],
    faia.[Quantidade de Logs]         AS [Quantidade de Logs],

    -- ============================ COLUNAS DO FARC ============================
    -- Mede o ATENDIMENTO/RESOLUCAO: tempo ativo somado em todas as janelas de
    -- posse do grupo A2B, ate o terminal de resolucao.
    farc.[Tempo de Atendimento]           AS [Tempo de Atendimento],
    farc.[Tempo de Atendimento (s)]       AS [Tempo de Atendimento (s)],
    farc.[Tempo Atendimento Excedido]     AS [Tempo Atendimento Excedido],
    farc.[Tempo Atendimento Excedido (s)] AS [Tempo Atendimento Excedido (s)],
    farc.[Meta Atendimento]               AS [Meta Atendimento],
    farc.[nHR_FARC]                       AS [nHR_FARC],
    farc.[FARC]                           AS [FARC]
FROM #FAIA_Resultado AS faia
FULL OUTER JOIN #FARC_Resultado AS farc
    ON farc.[__id] = faia.[__id];
",
            Resultado = Value.NativeQuery(Sql.Database("bdados-14r", "mdb"), SqlTexto, [Feriados = FeriadosJson], [EnableFolding = false])
        in
            Resultado
in
    Fonte