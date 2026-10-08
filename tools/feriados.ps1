# Leitura e validacao do arquivo de feriados (docs/feriados.txt).
#
# Usado por executar_consulta.ps1, gerar_powerbi_m.ps1 e verificar_feriados.ps1.
# Um unico calendario (o do TCU) para Virtual TI, Decision e A2B. As regras sao as
# mesmas do codigo M do Power BI (powerbi/*.m):
#   - texto UTF-8 com DUAS secoes: "## Feriados Fixos" e
#     "## Feriados moveis/diferenciados e pontos facultativos"; o texto antes
#     da primeira secao e livre (explicacao);
#   - formato antigo (retrocompatibilidade, ate o arquivo do SharePoint ser
#     trocado): no lugar da segunda secao, "## Feriados moveis/diferenciados"
#     e "## Pontos Facultativos". Misturar os dois formatos, ou repetir uma
#     secao, e erro;
#   - so contam as linhas que tem APENAS uma data:
#       DD-MM       feriado fixo (vale todo ano), na secao "## Feriados Fixos";
#       DD-MM-AAAA  data de um ano, na(s) outra(s) secao(oes);
#     titulos, linhas vazias e paragrafos sao ignorados;
#   - linha que parece data mas esta fora do formato (2026-04-03, 3-4-2026,
#     03/04/2026), data inexistente (31-02-2026), data fora da secao certa,
#     secao desconhecida, data repetida, arquivo ausente, vazio ou com
#     codificacao invalida interrompem tudo, com o numero da linha;
#   - arquivo sem nenhuma data e erro: nunca se calcula com zero feriados.
# Saida normalizada para o SQL (parametro @Feriados, JSON): MM-DD para fixos e
# AAAA-MM-DD para datas com ano, com a secao como descricao.

# Secoes aceitas (nome comparado sem acento e sem diferenca de maiusculas) e a
# descricao enviada ao SQL para as datas de cada uma.
$script:SecoesFeriados = [ordered]@{
    'feriados fixos'                = 'Feriado fixo'
    'feriados moveis/diferenciados' = ('Feriado m{0}vel/diferenciado' -f [char]0x00F3)
    'pontos facultativos'           = 'Ponto facultativo'
    'feriados moveis/diferenciados e pontos facultativos' = ('Feriado m{0}vel/diferenciado ou ponto facultativo' -f [char]0x00F3)
}
# Formato novo x antigo: a secao unica de datas com ano nao convive com as duas
# secoes antigas.
$script:SecaoNovaFeriados = 'feriados moveis/diferenciados e pontos facultativos'
$script:SecoesAntigasFeriados = @('feriados moveis/diferenciados', 'pontos facultativos')

function ConvertTo-NomeSecao([string]$Texto) {
    $d = $Texto.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $d.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
    }
    return ($sb.ToString() -replace '\s+', ' ').Trim().ToLowerInvariant()
}

function Read-ArquivoFeriados {
    param([Parameter(Mandatory = $true)][string]$Arquivo)
    if (-not (Test-Path -LiteralPath $Arquivo -PathType Leaf)) {
        throw "Arquivo de feriados nao encontrado: $Arquivo"
    }
    $caminho = (Resolve-Path -LiteralPath $Arquivo).Path
    $bytes = [System.IO.File]::ReadAllBytes($caminho)
    if ($bytes.Length -eq 0) { throw "Arquivo de feriados vazio: $caminho" }
    try {
        $texto = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes)
    } catch {
        throw "Arquivo de feriados com codificacao invalida (salve em UTF-8): $caminho"
    }
    $texto = $texto.TrimStart([char]0xFEFF)
    if ($texto.Contains([char]0)) { throw "Arquivo de feriados com codificacao invalida (salve em UTF-8, nao UTF-16): $caminho" }
    if ($texto.Trim() -eq '') { throw "Arquivo de feriados vazio: $caminho" }

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $estilo = [System.Globalization.DateTimeStyles]::None
    $erros = New-Object System.Collections.Generic.List[string]
    $saida = New-Object System.Collections.Generic.List[object]
    $vistos = @{}
    $secoesVistas = @{}
    $secao = $null
    $linhas = $texto -split "`r?`n"
    for ($i = 0; $i -lt $linhas.Count; $i++) {
        $n = $i + 1
        $t = $linhas[$i].Trim()
        if ($t -match '^##\s*(.+?)\s*$') {
            $nome = ConvertTo-NomeSecao $Matches[1]
            if ($script:SecoesFeriados.Contains($nome)) {
                if ($secoesVistas.ContainsKey($nome)) { $erros.Add("linha ${n}: secao repetida '$t' (ja na linha $($secoesVistas[$nome]))") }
                else { $secoesVistas[$nome] = $n }
                $secao = $nome
            }
            else { $erros.Add("linha ${n}: secao desconhecida '$t'") ; $secao = $null }
            continue
        }
        $dt = [datetime]::MinValue
        $norm = $null
        if ($t -match '^\d{2}-\d{2}$') {
            if ($secao -ne 'feriados fixos') { $erros.Add("linha ${n}: feriado fixo '$t' fora da secao '## Feriados Fixos'"); continue }
            if (-not [datetime]::TryParseExact("$t-2000", 'dd-MM-yyyy', $inv, $estilo, [ref]$dt)) { $erros.Add("linha ${n}: data invalida '$t' (use DD-MM)"); continue }
            $norm = $dt.ToString('MM-dd', $inv)
        } elseif ($t -match '^\d{2}-\d{2}-\d{4}$') {
            if ($null -eq $secao -or $secao -eq 'feriados fixos') { $erros.Add("linha ${n}: data '$t' fora das secoes de datas com ano"); continue }
            if (-not [datetime]::TryParseExact($t, 'dd-MM-yyyy', $inv, $estilo, [ref]$dt)) { $erros.Add("linha ${n}: data invalida '$t' (use DD-MM-AAAA)"); continue }
            $norm = $dt.ToString('yyyy-MM-dd', $inv)
        } elseif ($t -match '^\d[\d\s\-/\.]*$') {
            $erros.Add("linha ${n}: formato invalido '$t' (use DD-MM ou DD-MM-AAAA)"); continue
        } else {
            continue  # titulo, paragrafo ou linha vazia
        }
        if ($vistos.ContainsKey($norm)) { $erros.Add("linha ${n}: data '$t' repetida (ja na linha $($vistos[$norm]))"); continue }
        $vistos[$norm] = $n
        $saida.Add([pscustomobject]@{ Linha = $n; Data = $norm; Original = $t; Secao = $secao; Descricao = $script:SecoesFeriados[$secao] })
    }
    if ($secoesVistas.ContainsKey($script:SecaoNovaFeriados) -and @($script:SecoesAntigasFeriados | Where-Object { $secoesVistas.ContainsKey($_) }).Count -gt 0) {
        $erros.Add("secoes do formato novo e do antigo no mesmo arquivo: use so '## Feriados moveis/diferenciados e pontos facultativos' (ou, no formato antigo, '## Feriados moveis/diferenciados' e '## Pontos Facultativos')")
    }
    if ($erros.Count -gt 0) { throw ("Arquivo de feriados invalido ({0}):`n  {1}" -f $caminho, ($erros -join "`n  ")) }
    if ($saida.Count -eq 0) { throw "Arquivo de feriados sem nenhuma data: $caminho" }
    return , $saida.ToArray()
}

function Get-AvisosFeriados {
    # Redundancias que nao mudam o calculo: data com ano que cai num feriado fixo.
    param([Parameter(Mandatory = $true)][object[]]$Feriados)
    $fixos = @{}
    foreach ($f in $Feriados) { if ($f.Data.Length -eq 5) { $fixos[$f.Data] = $f.Linha } }
    $avisos = New-Object System.Collections.Generic.List[string]
    foreach ($f in $Feriados) {
        if ($f.Data.Length -eq 10 -and $fixos.ContainsKey($f.Data.Substring(5))) {
            $avisos.Add(("linha {0}: {1} coincide com o feriado fixo da linha {2} (redundante, sem dupla contagem)" -f $f.Linha, $f.Original, $fixos[$f.Data.Substring(5)]))
        }
    }
    return , $avisos.ToArray()
}

function Get-ListaFeriados {
    # Lista enviada ao SQL: uma entrada por data (data normalizada e descricao).
    param([Parameter(Mandatory = $true)][object[]]$Feriados)
    $lista = New-Object System.Collections.Generic.List[object]
    foreach ($f in $Feriados) { $lista.Add([pscustomobject]@{ data = $f.Data; descricao = $f.Descricao }) }
    return , $lista.ToArray()
}

function ConvertTo-FeriadosJson {
    param([Parameter(Mandatory = $true)][object[]]$Lista)
    return (ConvertTo-Json -InputObject @($Lista) -Compress)
}
