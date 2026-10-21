# F12: compare two existing diagnostic JSON reports; strictly READ-ONLY.
# Does not invoke Apply/Rollback, download files, turn off AV or open AutoCAD.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Before,
    [Parameter(Mandatory=$true)][string]$After,
    [string]$OutputDirectory=''
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\ParcheCAD.RCGates.ps1')
if(!(Test-Path -LiteralPath $Before -PathType Leaf) -or
   !(Test-Path -LiteralPath $After -PathType Leaf)){
    throw 'F12 requiere los dos diagnostico.json existentes (antes y despues).'
}
$maxBytes=12MB
if((Get-Item -LiteralPath $Before -ErrorAction Stop).Length -gt $maxBytes -or
   (Get-Item -LiteralPath $After -ErrorAction Stop).Length -gt $maxBytes){
    throw 'Informe excesivo; revisar manualmente en entorno aislado.'
}
$beforeObj=Get-Content -LiteralPath $Before -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$afterObj=Get-Content -LiteralPath $After -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$assessment=Get-PCADRC12Assessment -Before $beforeObj -After $afterObj
Write-Host ('F12 estado de certificacion: '+$assessment.Decision) -ForegroundColor Yellow
foreach($gate in $assessment.Gates){
    Write-Host ('  {0}: {1} / {2}' -f $gate.Gate,$gate.Status,$gate.Reason)
}
if($OutputDirectory){
    if(!(Test-Path -LiteralPath $OutputDirectory -PathType Container)){
        $null=New-Item -ItemType Directory -Path $OutputDirectory -Force -ErrorAction Stop
    }
    $jsonFile=Join-Path $OutputDirectory 'RC12_EVALUACION.json'
    $txtFile=Join-Path $OutputDirectory 'RC12_RESUMEN.txt'
    $encoding=New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($jsonFile,($assessment | ConvertTo-Json -Depth 10),$encoding)
    $lines=@(
        'ParcheCAD 4.0 - EVALUACION F12'
        ('Decision: '+$assessment.Decision)
        'Este informe NO prueba bloqueo completo Autodesk, WebView2 exclusivo, UAC o reinicio.'
        'No usar para autorizar RC1/Release.'
        ''
    )
    $lines+=@($assessment.Gates | ForEach-Object {('{0}: {1} - {2}' -f $_.Gate,$_.Status,$_.Reason)})
    [IO.File]::WriteAllLines($txtFile,[string[]]$lines,$encoding)
    Write-Host 'Informes F12 guardados localmente, sin IP ni rutas privadas.'
}
# A blocked RC gate is a normal and expected assessment, not a parser error.
# Exit 0 indicates successful READ-ONLY evaluation, NOT RC1 approval.
exit 0
