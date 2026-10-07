<#
.SYNOPSIS
    Executa uma consulta de queries/ com os feriados do arquivo docs/feriados.txt.

.DESCRIPTION
    O SQL Server nao le arquivos do computador do usuario, e a conta usada nas
    consultas nao tem permissao de BULK/OPENROWSET. Por isso os feriados chegam
    a consulta pelo parametro @Feriados (JSON), montado aqui a partir do
    arquivo. O calendario e o mesmo (o do TCU) para Virtual TI, Decision e A2B. E o
    mesmo parametro que o Power BI envia.

    Dois modos:
      -Saida <prefixo>   executa e grava cada resultado em <prefixo>.rsN.csv
      -GerarSql <arq>    nao executa: grava uma copia da consulta com @Feriados
                         ja declarado, para abrir e executar no SSMS.

.EXAMPLE
    .\tools\executar_consulta.ps1 -Consulta .\queries\consulta_faia_farc.sql -Saida C:\temp\decision_marco

.EXAMPLE
    .\tools\executar_consulta.ps1 -Consulta .\queries\consulta_faia_farc.sql -GerarSql C:\temp\decision_ssms.sql
#>
param(
    [Parameter(Mandatory = $true)][string]$Consulta,
    [string]$Saida,
    [string]$GerarSql,
    [string]$ArquivoFeriados,
    [string]$Servidor = 'bdados-14r',
    [string]$Banco = 'mdb',
    [string]$Separador = ';',
    [int]$TimeoutSegundos = 7200
)
$ErrorActionPreference = 'Stop'
$Ferramentas = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Ferramentas 'feriados.ps1')
if (-not $ArquivoFeriados) { $ArquivoFeriados = Join-Path $Ferramentas '..\docs\feriados.txt' }

if (-not $Saida -and -not $GerarSql) { throw 'Informe -Saida (executar) ou -GerarSql (gerar arquivo para o SSMS).' }
$sql = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Consulta).Path, [System.Text.Encoding]::UTF8)
$lista = Get-ListaFeriados -Feriados (Read-ArquivoFeriados -Arquivo $ArquivoFeriados)
$json = ConvertTo-FeriadosJson -Lista $lista
Write-Host ("Feriados: {0} itens ({1})" -f $lista.Count, (Resolve-Path -LiteralPath $ArquivoFeriados).Path)

if ($GerarSql) {
    $cabecalho = @(
        '-- Copia gerada por tools/executar_consulta.ps1 para execucao no SSMS.',
        ('-- Feriados lidos de {0} em {1}.' -f (Resolve-Path -LiteralPath $ArquivoFeriados).Path, (Get-Date -Format 'yyyy-MM-dd HH:mm')),
        '-- Nao versionar: gere de novo sempre que o arquivo de feriados mudar.',
        ("DECLARE @Feriados nvarchar(max) = N'{0}';" -f $json.Replace("'", "''")),
        ''
    ) -join "`r`n"
    [System.IO.File]::WriteAllText($GerarSql, $cabecalho + $sql, (New-Object System.Text.UTF8Encoding($true)))
    Write-Host "Gerado: $GerarSql"
    exit 0
}

$inv = [System.Globalization.CultureInfo]::InvariantCulture
function Format-Valor($v) {
    if ($v -is [byte[]]) { return '0x' + [System.BitConverter]::ToString($v).Replace('-', '') }
    if ($v -is [datetime]) { return $v.ToString('yyyy-MM-dd HH:mm:ss', $inv) }
    if ($v -is [System.IFormattable]) { return $v.ToString($null, $inv) }
    return "$v"
}
function Format-Campo([string]$s) {
    if ($s.IndexOfAny(($Separador + "`"`r`n").ToCharArray()) -ge 0) { return '"' + $s.Replace('"', '""') + '"' }
    return $s
}

$t0 = Get-Date
$cn = New-Object System.Data.SqlClient.SqlConnection ("Server=$Servidor;Database=$Banco;Integrated Security=SSPI;Connect Timeout=15;Application Name=FAIA-FARC executar_consulta")
$cn.Open()
try {
    $cmd = $cn.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.CommandTimeout = $TimeoutSegundos
    $p = $cmd.Parameters.Add('@Feriados', [System.Data.SqlDbType]::NVarChar, -1)
    $p.Value = $json
    $rd = $cmd.ExecuteReader()
    $i = 0
    do {
        if ($rd.FieldCount -eq 0) { continue }
        $i++
        $arq = "$Saida.rs$i.csv"
        $sw = New-Object System.IO.StreamWriter($arq, $false, (New-Object System.Text.UTF8Encoding($true)))
        $sw.WriteLine(((0..($rd.FieldCount - 1) | ForEach-Object { Format-Campo $rd.GetName($_) }) -join $Separador))
        $n = 0
        while ($rd.Read()) {
            $vals = 0..($rd.FieldCount - 1) | ForEach-Object { if ($rd.IsDBNull($_)) { '' } else { Format-Campo (Format-Valor $rd.GetValue($_)) } }
            $sw.WriteLine(($vals -join $Separador))
            $n++
        }
        $sw.Close()
        Write-Host ("  resultado {0}: {1} linhas -> {2}" -f $i, $n, $arq)
    } while ($rd.NextResult())
    $rd.Close()
} finally {
    $cn.Close()
}
Write-Host ("OK em {0}s" -f [int]((Get-Date) - $t0).TotalSeconds)
