<#
.SYNOPSIS
    Gera o codigo Power Query M (powerbi/*.m) a partir da consulta SQL do Power BI.

.DESCRIPTION
    O calculo de horas comerciais acontece no SQL Server, que nao le o
    SharePoint. O codigo M gerado:
      1. le o arquivo de feriados no SharePoint (Web.Contents);
      2. valida cada linha (Data AAAA-MM-DD ou MM-DD, Escopo conhecido) e
         falha a atualizacao com mensagem clara em qualquer problema;
      3. filtra pelo projeto declarado na consulta ("-- FERIADOS-ESCOPO:");
      4. envia a lista ao SQL como PARAMETRO @Feriados (JSON), sem concatenar
         texto do arquivo no SQL;
      5. executa a consulta (Value.NativeQuery) e devolve o mesmo resultado.

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
$Ferramentas = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Ferramentas 'feriados.ps1')

$caminho = (Resolve-Path -LiteralPath $Consulta).Path
$sql = [System.IO.File]::ReadAllText($caminho, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
$projeto = Get-EscopoConsulta -Sql $sql
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
// UrlArquivoFeriados com o link direto do arquivo feriados.csv no SharePoint.
//
// Feriados: a cada atualizacao o arquivo e lido de novo. Qualquer problema
// (link nao preenchido, arquivo inacessivel, coluna ausente, data ou escopo
// invalido, nenhum feriado para o projeto) FALHA a atualizacao com mensagem;
// o relatorio nunca e calculado com zero feriados.
// =============================================================================
let
    // ---- CONFIGURACAO (preencher uma unica vez) ----------------------------
    // Link direto do arquivo, por exemplo:
    //   https://<empresa>.sharepoint.com/sites/<site>/Shared%20Documents/<pasta>/feriados.csv
    // Servidor e banco da consulta SQL: os mesmos da fonte atual do relatorio
    // (conferir no PBIX antes de trocar; estao fixos na linha "Fonte", no fim).
    UrlArquivoFeriados = "INSERIR_URL_DO_ARQUIVO_FERIADOS_NO_SHAREPOINT",
    Projeto = "$projeto",

    // ---- Leitura do arquivo de feriados ------------------------------------
    Falha = (mensagem as text) => error Error.Record("Feriados", mensagem),
    Conteudo =
        if Text.Contains(UrlArquivoFeriados, "INSERIR_") then
            Falha("Preencha UrlArquivoFeriados com o link do arquivo feriados.csv no SharePoint.")
        else Binary.Buffer(Web.Contents(UrlArquivoFeriados)),
    Texto = Text.Replace(Text.FromBinary(Conteudo, TextEncoding.Utf8), "#(FEFF)", ""),
    // Separador: virgula, ou ponto e virgula (Excel em portugues), pelo cabecalho.
    PrimeiraLinha = List.First(Lines.FromText(Texto), ""),
    Separador = if List.ContainsAll(List.Transform(Text.Split(PrimeiraLinha, ";"), each Text.Trim(Text.Trim(_), """")), {"Data", "Escopo"}) then ";" else ",",
    Csv = Csv.Document(Texto, [Delimiter = Separador, QuoteStyle = QuoteStyle.Csv]),
    ComCabecalho = Table.PromoteHeaders(Csv, [PromoteAllScalars = true]),
    NomesLimpos = Table.TransformColumnNames(ComCabecalho, each Text.Trim(Text.Replace(_, "#(FEFF)", ""))),
    ColunasFaltando = List.Difference({"Data", "Descricao", "Escopo"}, Table.ColumnNames(NomesLimpos)),
    Tabela =
        if List.IsEmpty(ColunasFaltando) then Table.SelectColumns(NomesLimpos, {"Data", "Descricao", "Escopo"})
        else Falha("Coluna(s) ausente(s) no arquivo de feriados: " & Text.Combine(ColunasFaltando, ", ")),
    ComLinha = Table.AddIndexColumn(Tabela, "Linha", 2, 1),

    // ---- Validacao (mesmas regras de tools/feriados.ps1) -------------------
    Txt = (v) => if v = null then "" else Text.Trim(Text.From(v)),
    SoDigitos = (t as text) => Text.Length(t) > 0 and Text.Length(Text.Select(t, {"0".."9"})) = Text.Length(t),
    Dois = (n as number) => Text.PadStart(Text.From(n), 2, "0"),
    NormalizaData = (t as text, linha as number) as text =>
        let
            completa =
                if Text.Length(t) = 10 and Text.At(t, 4) = "-" and Text.At(t, 7) = "-"
                   and SoDigitos(Text.Start(t, 4) & Text.Middle(t, 5, 2) & Text.End(t, 2))
                then try #date(Number.From(Text.Start(t, 4)), Number.From(Text.Middle(t, 5, 2)), Number.From(Text.End(t, 2))) otherwise null
                else null,
            anual =
                if Text.Length(t) = 5 and Text.At(t, 2) = "-" and SoDigitos(Text.Start(t, 2) & Text.End(t, 2))
                then try #date(2000, Number.From(Text.Start(t, 2)), Number.From(Text.End(t, 2))) otherwise null
                else null,
            r =
                if completa <> null then Text.From(Date.Year(completa)) & "-" & Dois(Date.Month(completa)) & "-" & Dois(Date.Day(completa))
                else if anual <> null then Dois(Date.Month(anual)) & "-" & Dois(Date.Day(anual))
                else null
        in
            if r = null then Falha("Data invalida na linha " & Text.From(linha) & ": '" & t & "'. Use AAAA-MM-DD ou MM-DD.") else r,
    EscoposValidos = {"TODOS", "VIRTUAL", "DECISION", "A2B"},
    LeEscopo = (t as text, linha as number) as list =>
        let
            itens = List.Select(List.Transform(Text.Split(Text.Upper(t), ";"), Text.Trim), each _ <> ""),
            ok = not List.IsEmpty(itens)
                 and List.IsEmpty(List.Difference(itens, EscoposValidos))
                 and (not List.Contains(itens, "TODOS") or List.Count(itens) = 1)
        in
            if ok then itens else Falha("Escopo invalido na linha " & Text.From(linha) & ": '" & t & "'. Use TODOS ou VIRTUAL;DECISION;A2B."),
    Preenchidas = Table.SelectRows(ComLinha, each Txt([Data]) <> "" or Txt([Descricao]) <> "" or Txt([Escopo]) <> ""),
    Itens = List.Buffer(List.Transform(Table.ToRecords(Preenchidas), each
        [data = NormalizaData(Txt(_[Data]), _[Linha]), descricao = Txt(_[Descricao]), escopo = LeEscopo(Txt(_[Escopo]), _[Linha])])),
    // Forca a validacao de TODAS as linhas, inclusive as de outros projetos.
    Verificacao = Text.Combine(List.Transform(Itens, each _[data] & "|" & Text.Combine(_[escopo], ";")), ","),
    DoProjeto = List.Select(Itens, each List.Contains(_[escopo], "TODOS") or List.Contains(_[escopo], Projeto)),
    // Data repetida no projeto entra uma vez so (vale a primeira descricao).
    Datas = List.Distinct(List.Transform(DoProjeto, each _[data])),
    ParaSql = List.Transform(Datas, (d) => [data = d, descricao = List.First(List.Select(DoProjeto, each _[data] = d))[descricao]]),
    FeriadosJson =
        if Verificacao = "" or List.IsEmpty(ParaSql) then Falha("Nenhum feriado para o projeto " & Projeto & " no arquivo de feriados.")
        else Text.FromBinary(Json.FromValue(ParaSql), TextEncoding.Utf8),

    // ---- Consulta SQL (powerbi/$nomeSql) ------------------------------------
    SqlTexto = "$literal",
    Fonte = Value.NativeQuery(Sql.Database("bdados-14r", "mdb"), SqlTexto, [Feriados = FeriadosJson], [EnableFolding = false])
in
    Fonte
"@

if ($SomenteTexto) { return $m }
[System.IO.File]::WriteAllText($Saida, $m.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Gerado: $Saida"
