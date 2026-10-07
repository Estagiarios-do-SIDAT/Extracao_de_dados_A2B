<#
.SYNOPSIS
    Gera o codigo Power Query M (powerbi/*.m) a partir da consulta SQL do Power BI.

.DESCRIPTION
    O calculo de horas comerciais acontece no SQL Server, que nao le o
    SharePoint. O codigo M gerado:
      1. le o arquivo de feriados (feriados.txt) no SharePoint (Web.Contents,
         URL direta);
      2. valida cada linha com as regras de tools/feriados.ps1 (DD-MM nos
         Feriados Fixos, DD-MM-AAAA nas secoes com ano; titulos e paragrafos
         ignorados) e falha a atualizacao com mensagem clara em qualquer
         problema;
      3. envia a lista ao SQL como PARAMETRO @Feriados (JSON), sem concatenar
         texto do arquivo no SQL;
      4. executa a consulta (Value.NativeQuery) e devolve o mesmo resultado.

    Estrutura: tudo fica dentro de um UNICO passo ("Fonte"). A primeira versao
    tinha um passo por etapa, e o firewall de privacidade do Power Query
    (Formula.Firewall) recusava a combinacao do SharePoint com o SQL mesmo com
    as duas fontes como Organizacional. Num passo so, as duas fontes ficam na
    mesma particao e o firewall apenas confere se os niveis de privacidade sao
    compativeis (Organizacional + Organizacional). Validado com o motor do
    Power BI Desktop, sem ignorar niveis de privacidade.

    O SQL entra no M como texto literal. Altere sempre o .sql e gere de novo.

.EXAMPLE
    .\tools\gerar_powerbi_m.ps1 -Consulta .\powerbi\consulta_faia_farc_power_bi.sql
#>
param(
    [Parameter(Mandatory = $true)][string]$Consulta,
    [string]$Saida,
    [switch]$SomenteTexto
)
$ErrorActionPreference = 'Stop'

$caminho = (Resolve-Path -LiteralPath $Consulta).Path
$sql = [System.IO.File]::ReadAllText($caminho, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
if (-not $Saida) { $Saida = [System.IO.Path]::ChangeExtension($caminho, '.m') }
$nomeSql = [System.IO.Path]::GetFileName($caminho)

# Literal M: aspas duplas viram "" e "#(" vira "#(#)(" (inicio de escape no M).
$literal = $sql.Replace('"', '""').Replace('#(', '#(#)(')

$m = @"
// =============================================================================
// Power BI - consulta $nomeSql com feriados do SharePoint
//
// GERADO por tools/gerar_powerbi_m.ps1 a partir de powerbi/$nomeSql.
// Nao edite este arquivo: altere o .sql e gere de novo.
//
// Uso (uma vez): Power Query > Pagina Inicial > Nova Fonte > Consulta Nula >
// Editor Avancado > colar este arquivo inteiro. Depois, preencher
// UrlArquivoFeriados com o link direto do arquivo feriados.txt no SharePoint.
//
// Feriados: a cada atualizacao o arquivo e lido de novo. Ele e o mesmo para
// Virtual, Decision e A2B (calendario do TCU). Qualquer problema (link nao
// preenchido, arquivo inacessivel, codificacao invalida, data invalida ou
// repetida, secao desconhecida, arquivo sem datas) FALHA a atualizacao com
// mensagem; o relatorio nunca e calculado com zero feriados.
//
// Privacidade: SharePoint e SQL Server como Organizacional. Tudo fica num
// unico passo (Fonte) para o firewall de privacidade avaliar as duas fontes na
// mesma particao; nao separe os passos, senao volta o erro Formula.Firewall.
// =============================================================================
let
    Fonte =
        let
            // ---- CONFIGURACAO (preencher uma unica vez) ---------------------
            // Link direto do arquivo, por exemplo:
            //   https://<empresa>.sharepoint.com/sites/<site>/Shared%20Documents/<pasta>/feriados.txt
            // Servidor e banco da consulta SQL: os mesmos da fonte atual do
            // relatorio (conferir no PBIX; estao fixos no fim, em Sql.Database).
            UrlArquivoFeriados = "INSERIR_URL_DO_ARQUIVO_FERIADOS_NO_SHAREPOINT",

            // ---- Leitura do arquivo de feriados (feriados.txt) -------------
            // Mesmas regras de tools/feriados.ps1: so contam linhas que tem
            // apenas uma data; DD-MM na secao "## Feriados Fixos" e DD-MM-AAAA
            // nas secoes com ano; titulos, linhas vazias e paragrafos sao
            // ignorados. Saida para o SQL: MM-DD e AAAA-MM-DD.
            Falha = (mensagem as text) => error Error.Record("Feriados", mensagem),
            Conteudo =
                if Text.Contains(UrlArquivoFeriados, "INSERIR_") then
                    Falha("Preencha UrlArquivoFeriados com o link do arquivo feriados.txt no SharePoint.")
                else Binary.Buffer(Web.Contents(UrlArquivoFeriados)),
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
                #"regras" = null,
                #"feriados fixos" = "Feriado fixo",
                #"feriados por data" = "Feriado por data",
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
                        (if e[secao] = null or e[secao] = "regras" or e[secao] = "feriados fixos" then
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

            // ---- Consulta SQL (powerbi/$nomeSql) ----------------------------
            SqlTexto = "$literal",
            Resultado = Value.NativeQuery(Sql.Database("bdados-14r", "mdb"), SqlTexto, [Feriados = FeriadosJson], [EnableFolding = false])
        in
            Resultado
in
    Fonte
"@

if ($SomenteTexto) { return $m }
[System.IO.File]::WriteAllText($Saida, $m.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Gerado: $Saida"
