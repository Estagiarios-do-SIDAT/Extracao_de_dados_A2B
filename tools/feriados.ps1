# Leitura e validacao do arquivo de feriados (config/feriados.csv).
#
# Usado por executar_consulta.ps1, gerar_powerbi_m.ps1 e verificar_feriados.ps1.
# Um unico calendario (o do TCU) para Virtual, Decision e A2B. As regras sao as
# mesmas do codigo M do Power BI (powerbi/*.m):
#   - colunas obrigatorias: Data, Descricao, Fonte; separador virgula ou ';';
#   - Data: MM-DD (feriado nacional fixo, vale todo ano) ou AAAA-MM-DD (data
#     unica do ano: feriado movel ou ponto facultativo da Portaria do TCU);
#   - qualquer Data invalida interrompe tudo, com o numero da linha;
#   - data repetida entra uma vez so (vale a primeira descricao);
#   - arquivo sem nenhum feriado e erro: nunca se calcula com zero feriados.
# A coluna Fonte (Portaria do TCU) e conferida so por verificar_feriados.ps1:
# ela documenta a origem e nao entra no calculo.

function Read-ArquivoFeriados {
    param([Parameter(Mandatory = $true)][string]$Arquivo)
    if (-not (Test-Path -LiteralPath $Arquivo -PathType Leaf)) {
        throw "Arquivo de feriados nao encontrado: $Arquivo"
    }
    $caminho = (Resolve-Path -LiteralPath $Arquivo).Path
    $texto = [System.IO.File]::ReadAllText($caminho, (New-Object System.Text.UTF8Encoding($false)))
    $texto = $texto.TrimStart([char]0xFEFF)
    $linhasTexto = $texto -split "`r?`n"
    if ($linhasTexto.Count -lt 1 -or $linhasTexto[0].Trim() -eq '') { throw "Arquivo de feriados vazio: $caminho" }
    # Separador: virgula, ou ponto e virgula (Excel em portugues), pelo cabecalho.
    $separador = ','
    $porPontoVirgula = @($linhasTexto[0].Split(';') | ForEach-Object { $_.Trim().Trim('"') })
    if ($porPontoVirgula -contains 'Data' -and $porPontoVirgula -contains 'Fonte') { $separador = ';' }
    $cabecalho = @($linhasTexto[0].Split($separador) | ForEach-Object { $_.Trim().Trim('"') })
    $faltando = @('Data', 'Descricao', 'Fonte' | Where-Object { $cabecalho -notcontains $_ })
    if ($faltando.Count -gt 0) { throw ("Coluna(s) ausente(s) no arquivo de feriados: {0}" -f ($faltando -join ', ')) }

    $registros = @($texto | ConvertFrom-Csv -Delimiter $separador)
    $erros = New-Object System.Collections.Generic.List[string]
    $saida = New-Object System.Collections.Generic.List[object]
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $estilo = [System.Globalization.DateTimeStyles]::None
    for ($i = 0; $i -lt $registros.Count; $i++) {
        $r = $registros[$i]
        $linha = $i + 2
        $data = ("" + $r.Data).Trim()
        $desc = ("" + $r.Descricao).Trim()
        $fonte = ("" + $r.Fonte).Trim()
        if ($data -eq '' -and $desc -eq '' -and $fonte -eq '') { continue }

        $dt = [datetime]::MinValue
        $norm = $null
        if ($data -match '^\d{4}-\d{2}-\d{2}$' -and [datetime]::TryParseExact($data, 'yyyy-MM-dd', $inv, $estilo, [ref]$dt)) {
            $norm = $dt.ToString('yyyy-MM-dd', $inv)
        } elseif ($data -match '^\d{2}-\d{2}$' -and [datetime]::TryParseExact("2000-$data", 'yyyy-MM-dd', $inv, $estilo, [ref]$dt)) {
            $norm = $dt.ToString('MM-dd', $inv)
        } else {
            $erros.Add("linha ${linha}: Data invalida '$data' (use MM-DD ou AAAA-MM-DD)")
        }
        if ($null -ne $norm) {
            $saida.Add([pscustomobject]@{ Linha = $linha; Data = $norm; Descricao = $desc; Fonte = $fonte })
        }
    }
    if ($erros.Count -gt 0) { throw ("Arquivo de feriados invalido ({0}):`n  {1}" -f $caminho, ($erros -join "`n  ")) }
    if ($saida.Count -eq 0) { throw "Arquivo de feriados sem nenhuma linha: $caminho" }
    return , $saida.ToArray()
}

function Get-ListaFeriados {
    # Lista enviada ao SQL: uma entrada por data (a repetida entra uma vez).
    param([Parameter(Mandatory = $true)][object[]]$Feriados)
    $vistos = @{}
    $lista = New-Object System.Collections.Generic.List[object]
    foreach ($f in $Feriados) {
        if ($vistos.ContainsKey($f.Data)) {
            Write-Warning ("Feriados: data {0} repetida (linhas {1} e {2}); vale a primeira." -f $f.Data, $vistos[$f.Data], $f.Linha)
            continue
        }
        $vistos[$f.Data] = $f.Linha
        $lista.Add([pscustomobject]@{ data = $f.Data; descricao = $f.Descricao })
    }
    return , $lista.ToArray()
}

function ConvertTo-FeriadosJson {
    param([Parameter(Mandatory = $true)][object[]]$Lista)
    return (ConvertTo-Json -InputObject @($Lista) -Compress)
}
