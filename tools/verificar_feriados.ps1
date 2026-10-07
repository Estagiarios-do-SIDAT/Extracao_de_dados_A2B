<#
.SYNOPSIS
    Valida config/feriados.csv e confere a sincronia entre os repositorios.

.DESCRIPTION
    1. Valida o arquivo (mesmas regras do Power BI), exige a coluna Fonte
       (Portaria do TCU) preenchida em todas as linhas e mostra quantos feriados
       fixos (MM-DD) e datas unicas (AAAA-MM-DD) ele tem, por ano.
    2. Compara config/feriados.csv, docs/feriados.md e tools/*.ps1 com os dos
       repositorios irmaos (Extracao_de_dados_Virtual, _Decision, _A2B na mesma
       pasta), se existirem. As tres copias devem ser identicas byte a byte.
    3. Confere se cada powerbi/*.m corresponde ao .sql de mesmo nome
       (gerado por tools/gerar_powerbi_m.ps1).
    Termina com codigo 1 se algo nao bater.

.EXAMPLE
    .\tools\verificar_feriados.ps1
#>
param([string]$ArquivoFeriados)
$ErrorActionPreference = 'Stop'
$Ferramentas = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Ferramentas 'feriados.ps1')
if (-not $ArquivoFeriados) { $ArquivoFeriados = Join-Path $Ferramentas '..\config\feriados.csv' }
$falhas = 0
$repo = (Resolve-Path (Join-Path $Ferramentas '..')).Path

$feriados = Read-ArquivoFeriados -Arquivo $ArquivoFeriados
$lista = Get-ListaFeriados -Feriados $feriados
$semFonte = @($feriados | Where-Object { $_.Fonte -eq '' })
foreach ($f in $semFonte) { Write-Host ("  SEM FONTE: linha {0} ({1})" -f $f.Linha, $f.Data); $falhas++ }
$fixos = @($lista | Where-Object { $_.data.Length -eq 5 }).Count
$porAno = @($lista | Where-Object { $_.data.Length -eq 10 } | Group-Object { $_.data.Substring(0, 4) } | Sort-Object Name | ForEach-Object { '{0}: {1}' -f $_.Name, $_.Count }) -join ', '
Write-Host ("Arquivo valido: {0} feriados ({1} fixos MM-DD, todo ano; datas unicas por ano: {2})" -f $lista.Count, $fixos, $porAno)

function Get-Hash([string]$f) { (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash }
$compartilhados = @('config\feriados.csv', 'docs\feriados.md') + @(Get-ChildItem (Join-Path $repo 'tools') -Filter *.ps1 | ForEach-Object { "tools\$($_.Name)" })
$irmaos = @(Get-ChildItem (Split-Path $repo) -Directory -Filter 'Extracao_de_dados_*' |
    Where-Object { $_.FullName -ne $repo -and @('Extracao_de_dados_Virtual', 'Extracao_de_dados_Decision', 'Extracao_de_dados_A2B') -contains $_.Name })
$antes = $falhas
foreach ($rel in $compartilhados) {
    $h = Get-Hash (Join-Path $repo $rel)
    foreach ($ir in $irmaos) {
        $outro = Join-Path $ir.FullName $rel
        if (-not (Test-Path -LiteralPath $outro)) { Write-Host "  DIFERENTE: $rel nao existe em $($ir.Name)"; $falhas++ }
        elseif ((Get-Hash $outro) -ne $h) { Write-Host "  DIFERENTE: $rel em $($ir.Name)"; $falhas++ }
    }
}
Write-Host ("Sincronia com {0} repositorio(s) irmao(s): {1}" -f $irmaos.Count, $(if ($falhas -eq $antes) { 'OK' } else { 'FALHOU' }))

foreach ($sql in @(Get-ChildItem (Join-Path $repo 'powerbi') -Filter *.sql)) {
    $mArq = [System.IO.Path]::ChangeExtension($sql.FullName, '.m')
    $esperado = (& (Join-Path $Ferramentas 'gerar_powerbi_m.ps1') -Consulta $sql.FullName -SomenteTexto).Replace("`r`n", "`n")
    if (-not (Test-Path -LiteralPath $mArq)) { Write-Host "  FALTA: $([System.IO.Path]::GetFileName($mArq))"; $falhas++ }
    elseif ([System.IO.File]::ReadAllText($mArq, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n") -ne $esperado) {
        Write-Host "  DESATUALIZADO: $([System.IO.Path]::GetFileName($mArq)) (rode tools\gerar_powerbi_m.ps1)"; $falhas++
    } else { Write-Host "  em dia: $([System.IO.Path]::GetFileName($mArq))" }
}
if ($falhas -gt 0) { Write-Host "Verificacao: $falhas problema(s)."; exit 1 }
Write-Host 'Verificacao: tudo certo.'
