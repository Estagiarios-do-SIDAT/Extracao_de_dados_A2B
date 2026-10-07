<#
.SYNOPSIS
    Valida config/feriados.csv e confere a sincronia entre os repositorios.

.DESCRIPTION
    1. Valida o arquivo (mesmas regras do Power BI) e lista, por projeto,
       quantos feriados entram.
    2. Compara config/feriados.csv, docs/feriados.md e tools/*.ps1 com os dos
       repositorios irmaos (Extracao_de_dados_Virtual, _Decision, _A2B na mesma
       pasta), se existirem. As tres copias devem ser identicas.
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
Write-Host ("Arquivo valido: {0} linhas" -f $feriados.Count)
foreach ($p in $ProjetosFeriados) {
    $l = Select-FeriadosProjeto -Feriados $feriados -Projeto $p
    $anuais = @($l | Where-Object { $_.data.Length -eq 5 }).Count
    Write-Host ("  {0,-9} {1,3} feriados ({2} fixos MM-DD, {3} datas unicas)" -f $p, $l.Count, $anuais, ($l.Count - $anuais))
}

function Get-Hash([string]$f) { (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash }
$compartilhados = @('config\feriados.csv', 'docs\feriados.md') +@(Get-ChildItem (Join-Path $repo 'tools') -Filter *.ps1 | ForEach-Object { "tools\$($_.Name)" })
$irmaos = @(Get-ChildItem (Split-Path $repo) -Directory -Filter 'Extracao_de_dados_*' |
    Where-Object { $_.FullName -ne $repo -and @('Extracao_de_dados_Virtual', 'Extracao_de_dados_Decision', 'Extracao_de_dados_A2B') -contains $_.Name })
foreach ($rel in $compartilhados) {
    $h = Get-Hash (Join-Path $repo $rel)
    foreach ($ir in $irmaos) {
        $outro = Join-Path $ir.FullName $rel
        if (-not (Test-Path -LiteralPath $outro)) { Write-Host "  DIFERENTE: $rel nao existe em $($ir.Name)"; $falhas++ }
        elseif ((Get-Hash $outro) -ne $h) { Write-Host "  DIFERENTE: $rel em $($ir.Name)"; $falhas++ }
    }
}
Write-Host ("Sincronia com {0} repositorio(s) irmao(s): {1}" -f $irmaos.Count, $(if ($falhas -eq 0) { 'OK' } else { 'FALHOU' }))

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
