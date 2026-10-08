<#
.SYNOPSIS
    Gera a consulta do Power BI (powerbi/*.m, Power Query M) a partir do SQL-fonte.

.DESCRIPTION
    O .m e a UNICA consulta do Power BI de cada relatorio: e ele que se cola no
    Editor Avancado. O SQL-fonte (em queries/) e a consulta de referencia,
    usada tambem para testes; ele nao se cola no Power BI.

    O calculo do Horario TCU acontece no SQL Server, que nao le o SharePoint.
    O codigo M gerado:
      1. le o calendario feriados.txt no SharePoint pelo conector
         SharePoint.Files (Conta organizacional), no site FIXO deste gerador
         ($SiteConexao). A unica configuracao do .m e SharePointFeriadosLink,
         o link do arquivo copiado do SharePoint: dele saem a pasta e o nome,
         e fica o UNICO arquivo com esse nome nessa pasta (nenhum ou mais de
         um e erro). O link nunca e aberto;
      2. valida cada linha com as regras de tools/feriados.ps1 e falha a
         atualizacao com mensagem clara em qualquer problema;
      3. envia a lista ao SQL como PARAMETRO @Feriados (JSON), sem concatenar
         texto do arquivo no SQL;
      4. executa a consulta (Value.NativeQuery) e devolve o mesmo resultado.

    Periodo: se o SQL-fonte tiver um bloco entre "-- >>> PERIODO POWER BI" e
    "-- <<< PERIODO POWER BI" (comentado com /* */), o gerador troca por ele o
    bloco entre "-- >>> PERIODO REFERENCIA" e "-- <<< PERIODO REFERENCIA".
    Assim a consulta de referencia e a do Power BI saem do mesmo arquivo e so o
    periodo muda. Sem esses marcadores, o SQL-fonte entra inteiro.

    Estrutura: a leitura do SharePoint e o SQL ficam num UNICO passo ("Fonte").
    A primeira versao tinha um passo por etapa, e o firewall de privacidade do
    Power Query (Formula.Firewall) recusava a combinacao do SharePoint com o
    SQL mesmo com as duas fontes como Organizacional. Num passo so, as duas
    fontes ficam na mesma particao. SharePointFeriadosLink e so texto e fica
    num passo proprio, no topo, para ser facil de trocar.

    Power BI Service: o primeiro argumento de SharePoint.Files e um LITERAL
    (o site), nunca montado a partir do link, para que o servico reconheca a
    fonte de dados sem avalia-la (fonte dinamica impede a atualizacao
    agendada). O link so filtra o resultado. Link de outro site e erro, em
    vez de trocar a fonte.

    Localizacao do arquivo: SharePoint.Files devolve TODOS os arquivos do site,
    e o mesmo nome feriados.txt existe em mais de uma pasta (ha copias dentro
    dos repositorios sincronizados). Por isso a selecao exige o nome E a pasta
    ([Folder Path]); a pasta e comparada sem diferenca de maiusculas e da barra
    final. Do link: Uri.Parts separa o caminho (sem o que vem depois de "?"),
    o prefixo de compartilhamento "/:t:/r" e descartado e os %XX sao
    decodificados em UTF-8 (Uri.Parts nao decodifica; testado). Link sem o
    caminho do arquivo (/:t:/s/<id>) e erro: nao se adivinha a pasta. O link
    nunca e aberto com Web.Contents: com ele o Power BI recusava a credencial
    organizacional.

    O SQL entra no M como texto literal. Altere sempre o SQL-fonte e gere de
    novo; tools/verificar_feriados.ps1 acusa .m desatualizado.

.EXAMPLE
    .\tools\gerar_powerbi_m.ps1 -Consulta .\queries\consulta_faia_farc_painel.sql -Saida .\powerbi\consulta_faia_farc_power_bi.m
#>
param(
    [Parameter(Mandatory = $true)][string]$Consulta,
    [string]$Saida,
    [switch]$SomenteTexto
)
$ErrorActionPreference = 'Stop'

# SharePoint do calendario. $SiteConexao entra LITERAL no SharePoint.Files do
# .m (ver Power BI Service, acima); $LinkFeriados e o valor inicial de
# SharePointFeriadosLink.
$SiteConexao = 'https://tcucloud.sharepoint.com/sites/EstgioSidatTCU'
$LinkFeriados = 'https://tcucloud.sharepoint.com/:t:/r/sites/EstgioSidatTCU/Documentos%20Compartilhados/Atividades%20Avulsas/Indicadores%20e%20Relat%C3%B3rios%20de%20Servi%C3%A7os/Documentos%20e%20Relat%C3%B3rios/feriados.txt?d=w3744a75ddc284a38890b5d9c4af44be3&csf=1&web=1&e=hwfUQM'

$caminho = (Resolve-Path -LiteralPath $Consulta).Path
$repo = Split-Path -Parent (Split-Path -Parent $caminho)
$fonteRel = $caminho.Substring($repo.Length + 1).Replace('\', '/')
if (-not $Saida -and -not $SomenteTexto) { throw 'Informe -Saida (ex.: .\powerbi\<consulta>_power_bi.m).' }
$sql = [System.IO.File]::ReadAllText($caminho, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
if ($Saida -and -not [System.IO.Path]::IsPathRooted($Saida)) { $Saida = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Saida)) }

# Periodo do Power BI (ver .DESCRIPTION).
$blocoPbi = [regex]::Match($sql, '(?ms)^-- >>> PERIODO POWER BI.*?^-- <<< PERIODO POWER BI[^\n]*\n')
if ($blocoPbi.Success) {
    $blocoRef = [regex]::Match($sql, '(?ms)^-- >>> PERIODO REFERENCIA.*?^-- <<< PERIODO REFERENCIA[^\n]*\n')
    if (-not $blocoRef.Success) { throw "SQL-fonte com bloco PERIODO POWER BI e sem bloco PERIODO REFERENCIA: $caminho" }
    $pbi = (@($blocoPbi.Value -split "`n" | Where-Object { $_.Trim() -ne '/*' -and $_.Trim() -ne '*/' })) -join "`n"
    $sql = $sql.Replace($blocoRef.Value, '').Replace($blocoPbi.Value, $pbi)
}

# Literal M: aspas duplas viram "" e "#(" vira "#(#)(" (inicio de escape no M).
$literal = $sql.Replace('"', '""').Replace('#(', '#(#)(')

$m = @"
// =============================================================================
// Power BI - consulta do relatorio (unica), com feriados do SharePoint
// Fonte SQL: $fonteRel
//
// GERADO por tools/gerar_powerbi_m.ps1 a partir de $fonteRel.
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
    // SharePoint.Files no site $SiteConexao, com Conta organizacional;
    // link de outro site e erro.
    // ============================================================================
    SharePointFeriadosLink = "$LinkFeriados",

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
            SiteConexao = "$SiteConexao",
            ArquivosSite = SharePoint.Files("$SiteConexao", [ApiVersion = 15]),

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
            // Formato novo: "Feriados Fixos" e "Feriados moveis/diferenciados e
            // pontos facultativos". Formato antigo (retrocompatibilidade): as
            // duas ultimas separadas. Misturar os formatos, ou repetir uma
            // secao, e erro.
            Secoes = [
                #"feriados fixos" = "Feriado fixo",
                #"feriados moveis/diferenciados e pontos facultativos" = "Feriado m#(00F3)vel/diferenciado ou ponto facultativo",
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
            Estado = List.Accumulate(List.Positions(Linhas), [secao = null, itens = {}, erros = {}, vistas = []], (e, i) =>
                let
                    n = i + 1,
                    t = Text.Trim(Linhas{i}),
                    titulo = if Text.StartsWith(t, "##") and Text.Trim(Text.Range(t, 2)) <> "" then NomeSecao(Text.Range(t, 2)) else null
                in
                    if titulo <> null then
                        (if not Record.HasFields(Secoes, titulo) then Erro(e & [secao = null], n, "secao desconhecida '" & t & "'")
                         else if Record.HasFields(e[vistas], titulo) then
                            Erro(e & [secao = titulo], n, "secao repetida '" & t & "' (ja na linha " & Text.From(Record.Field(e[vistas], titulo)) & ")")
                         else e & [secao = titulo, vistas = e[vistas] & Record.AddField([], titulo, n)])
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
            Mistura = Record.HasFields(Estado[vistas], "feriados moveis/diferenciados e pontos facultativos")
                and (Record.HasFields(Estado[vistas], "feriados moveis/diferenciados") or Record.HasFields(Estado[vistas], "pontos facultativos")),
            ErrosFinais = Estado[erros] & (if Mistura then {"secoes do formato novo e do antigo no mesmo arquivo: use so '## Feriados moveis/diferenciados e pontos facultativos' (ou, no formato antigo, '## Feriados moveis/diferenciados' e '## Pontos Facultativos')"} else {}),
            // Forca a validacao de TODAS as linhas antes de chamar o SQL.
            Validas =
                if not List.IsEmpty(ErrosFinais) then Falha("Arquivo de feriados invalido: " & Text.Combine(ErrosFinais, "; "))
                else if List.IsEmpty(Estado[itens]) then Falha("Arquivo de feriados sem nenhuma data.")
                else Estado[itens],
            ParaSql = List.Transform(Validas, each [data = _[data], descricao = _[descricao]]),
            FeriadosJson = Text.FromBinary(Json.FromValue(ParaSql), TextEncoding.Utf8),

            // ---- Consulta SQL ($fonteRel) ----------------------------
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
