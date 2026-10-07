# Leitura e validacao do arquivo de feriados (config/feriados.csv).
#
# Usado por executar_consulta.ps1, gerar_powerbi_m.ps1 e verificar_feriados.ps1.
# As regras sao as mesmas do codigo M do Power BI (powerbi/*.m):
#   - colunas obrigatorias: Data, Descricao, Escopo; separador virgula ou ';';
#   - Data: AAAA-MM-DD (data unica) ou MM-DD (feriado fixo, vale todo ano);
#   - Escopo: TODOS, ou projetos separados por ';' (VIRTUAL, DECISION, A2B);
#   - qualquer linha invalida interrompe tudo, com o numero da linha;
#   - data repetida no mesmo projeto entra uma vez so (vale a primeira descricao);
#   - projeto sem nenhum feriado e erro: nunca se calcula com zero feriados.

$ProjetosFeriados = @('VIRTUAL', 'DECISION', 'A2B')

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
    if ($porPontoVirgula -contains 'Data' -and $porPontoVirgula -contains 'Escopo') { $separador = ';' }
    $cabecalho = @($linhasTexto[0].Split($separador) | ForEach-Object { $_.Trim().Trim('"') })
    $faltando = @('Data', 'Descricao', 'Escopo' | Where-Object { $cabecalho -notcontains $_ })
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
        $escopoTxt = ("" + $r.Escopo).Trim()
        if ($data -eq '' -and $desc -eq '' -and $escopoTxt -eq '') { continue }

        $dt = [datetime]::MinValue
        $norm = $null
        if ($data -match '^\d{4}-\d{2}-\d{2}$' -and [datetime]::TryParseExact($data, 'yyyy-MM-dd', $inv, $estilo, [ref]$dt)) {
            $norm = $dt.ToString('yyyy-MM-dd', $inv)
        } elseif ($data -match '^\d{2}-\d{2}$' -and [datetime]::TryParseExact("2000-$data", 'yyyy-MM-dd', $inv, $estilo, [ref]$dt)) {
            $norm = $dt.ToString('MM-dd', $inv)
        } else {
            $erros.Add("linha ${linha}: Data invalida '$data' (use AAAA-MM-DD ou MM-DD)")
        }

        $itens = @($escopoTxt.ToUpperInvariant().Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        $invalidos = @($itens | Where-Object { $_ -ne 'TODOS' -and $ProjetosFeriados -notcontains $_ })
        if ($itens.Count -eq 0 -or $invalidos.Count -gt 0 -or ($itens -contains 'TODOS' -and $itens.Count -gt 1)) {
            $erros.Add("linha ${linha}: Escopo invalido '$escopoTxt' (use TODOS ou VIRTUAL;DECISION;A2B)")
        }
        if ($null -ne $norm) {
            $saida.Add([pscustomobject]@{ Linha = $linha; Data = $norm; Descricao = $desc; Escopo = $itens })
        }
    }
    if ($erros.Count -gt 0) { throw ("Arquivo de feriados invalido ({0}):`n  {1}" -f $caminho, ($erros -join "`n  ")) }
    if ($saida.Count -eq 0) { throw "Arquivo de feriados sem nenhuma linha: $caminho" }
    return , $saida.ToArray()
}

function Select-FeriadosProjeto {
    param([Parameter(Mandatory = $true)][object[]]$Feriados, [Parameter(Mandatory = $true)][string]$Projeto)
    $p = $Projeto.ToUpperInvariant()
    if ($ProjetosFeriados -notcontains $p) { throw "Projeto desconhecido: $Projeto" }
    $vistos = @{}
    $lista = New-Object System.Collections.Generic.List[object]
    foreach ($f in $Feriados) {
        if (-not ($f.Escopo -contains 'TODOS' -or $f.Escopo -contains $p)) { continue }
        if ($vistos.ContainsKey($f.Data)) {
            Write-Warning ("Feriados: data {0} repetida para {1} (linhas {2} e {3}); vale a primeira." -f $f.Data, $p, $vistos[$f.Data], $f.Linha)
            continue
        }
        $vistos[$f.Data] = $f.Linha
        $lista.Add([pscustomobject]@{ data = $f.Data; descricao = $f.Descricao })
    }
    if ($lista.Count -eq 0) { throw "Nenhum feriado para o projeto $p no arquivo de feriados." }
    return , $lista.ToArray()
}

function ConvertTo-FeriadosJson {
    param([Parameter(Mandatory = $true)][object[]]$Lista)
    return (ConvertTo-Json -InputObject @($Lista) -Compress)
}

function Get-EscopoConsulta {
    # Projeto do arquivo de feriados declarado na propria consulta:
    #   -- FERIADOS-ESCOPO: DECISION
    param([Parameter(Mandatory = $true)][string]$Sql)
    $m = [regex]::Match($Sql, '(?m)^--\s*FERIADOS-ESCOPO:\s*([A-Za-z0-9]+)\s*$')
    if (-not $m.Success) { throw 'A consulta nao declara a linha "-- FERIADOS-ESCOPO: <PROJETO>".' }
    return $m.Groups[1].Value.ToUpperInvariant()
}
