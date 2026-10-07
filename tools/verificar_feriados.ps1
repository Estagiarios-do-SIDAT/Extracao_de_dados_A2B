<#
.SYNOPSIS
    Valida docs/feriados.txt e confere a sincronia entre os repositorios.

.DESCRIPTION
    1. Valida o arquivo (mesmas regras do Power BI: tools/feriados.ps1) e
       mostra quantos feriados fixos (DD-MM) e datas com ano (DD-MM-AAAA) ele
       tem, por secao e por ano. Avisa redundancias que nao mudam o calculo
       (data com ano que cai num feriado fixo).
    2. Compara docs/feriados.txt e tools/*.ps1 com os dos
       repositorios irmaos (Extracao_de_dados_Virtual, _Decision, _A2B na mesma
       pasta), se existirem: as copias devem ser identicas byte a byte.
       docs/feriados.txt tambem e comparado com a copia do COI
       (Extracao_de_dados_COI/docs/feriados.txt) e com a copia compartilhada
       "Documentos e Relatorios"/feriados.txt da pasta acima, se existirem.
       Essas copias so sao conferidas aqui: nenhuma consulta depende delas.
    3. Confere se cada powerbi/*.m (a consulta do Power BI) corresponde ao
       SQL-fonte indicado no seu cabecalho ("// Fonte SQL: ..."), gerando de
       novo com tools/gerar_powerbi_m.ps1.
    Termina com codigo 1 se algo nao bater.

.EXAMPLE
    .\tools\verificar_feriados.ps1
#>
param([string]$ArquivoFeriados)
$ErrorActionPreference = 'Stop'
$Ferramentas = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Ferramentas 'feriados.ps1')
if (-not $ArquivoFeriados) { $ArquivoFeriados = Join-Path $Ferramentas '..\docs\feriados.txt' }
$falhas = 0
$repo = (Resolve-Path (Join-Path $Ferramentas '..')).Path
$pasta = Split-Path $repo

$feriados = Read-ArquivoFeriados -Arquivo $ArquivoFeriados
$fixos = @($feriados | Where-Object { $_.Data.Length -eq 5 }).Count
$porAno = @($feriados | Where-Object { $_.Data.Length -eq 10 } | Group-Object { $_.Data.Substring(0, 4) } | Sort-Object Name | ForEach-Object { '{0}: {1}' -f $_.Name, $_.Count }) -join ', '
Write-Host ("Arquivo valido: {0} datas ({1} fixas DD-MM, todo ano; datas com ano: {2})" -f $feriados.Count, $fixos, $porAno)
$feriados | Group-Object Secao | ForEach-Object { Write-Host ("  secao '{0}': {1}" -f $_.Name, $_.Count) }
foreach ($a in (Get-AvisosFeriados -Feriados $feriados)) { Write-Host "  AVISO: $a" }

function Get-Hash([string]$f) { (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash }
$compartilhados = @('docs\feriados.txt') + @(Get-ChildItem (Join-Path $repo 'tools') -Filter *.ps1 | ForEach-Object { "tools\$($_.Name)" })
$irmaos = @(Get-ChildItem $pasta -Directory -Filter 'Extracao_de_dados_*' |
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

# Copias so de consulta do calendario (sem uso operacional): COI e a pasta
# compartilhada de documentos. Conferidas se existirem.
$hTxt = Get-Hash (Join-Path $repo 'docs\feriados.txt')
$extras = @(Join-Path $pasta 'Extracao_de_dados_COI\docs\feriados.txt') +
    @(Get-ChildItem $pasta -Directory -Filter 'Documentos e Relat*rios' | ForEach-Object { Join-Path $_.FullName 'feriados.txt' })
foreach ($c in $extras) {
    if (-not (Test-Path -LiteralPath $c)) { continue }
    if ((Get-Hash $c) -ne $hTxt) { Write-Host "  DIFERENTE: $c"; $falhas++ }
    else { Write-Host "  copia igual: $c" }
}

$mArquivos = @(Get-ChildItem (Join-Path $repo 'powerbi') -Filter *.m)
if ($mArquivos.Count -eq 0) { Write-Host '  FALTA: nenhum powerbi/*.m'; $falhas++ }
foreach ($mArq in $mArquivos) {
    $atual = [System.IO.File]::ReadAllText($mArq.FullName, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
    $fonte = [regex]::Match($atual, '(?m)^// Fonte SQL: (.+?)\s*$')
    if (-not $fonte.Success) { Write-Host "  SEM FONTE: $($mArq.Name) (cabecalho '// Fonte SQL:' ausente)"; $falhas++; continue }
    $rel = $fonte.Groups[1].Value
    $sqlFonte = Join-Path $repo $rel.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $sqlFonte)) { Write-Host "  FALTA SQL-fonte de $($mArq.Name): $rel"; $falhas++; continue }
    $esperado = (& (Join-Path $Ferramentas 'gerar_powerbi_m.ps1') -Consulta $sqlFonte -SomenteTexto).Replace("`r`n", "`n")
    if ($atual -ne $esperado) {
        Write-Host "  DESATUALIZADO: $($mArq.Name) (rode tools\gerar_powerbi_m.ps1 -Consulta $rel -Saida powerbi\$($mArq.Name))"; $falhas++
    } else { Write-Host "  em dia: $($mArq.Name) <- $rel" }
}
if ($falhas -gt 0) { Write-Host "Verificacao: $falhas problema(s)."; exit 1 }
Write-Host 'Verificacao: tudo certo.'
