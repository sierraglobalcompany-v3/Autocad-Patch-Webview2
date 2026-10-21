# F7: prueba de bloqueo end-to-end en Windows descartable.
# Solo escribe fixture local bajo informes/; NO modifica firewall, tareas ni registro.
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted'){
    throw 'Esta prueba es para GitHub-hosted Windows descartable.'
}
$repo=Split-Path -Parent $PSScriptRoot
$directory=Join-Path $repo 'informes\operaciones'
$null=New-Item -ItemType Directory -Path $directory -Force
$fixture=Join-Path $directory ('PCAD4_'+[guid]::NewGuid().ToString('N')+'.json.pending')
try{
    [IO.File]::WriteAllText($fixture,'incomplete-transaction-fixture')
    $exe=Join-Path $PSHOME 'powershell.exe'
    $diagnostic=Join-Path $repo 'src\ParcheCAD.Diagnostico.ps1'
    $output=& $exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File $diagnostic -NoExport 2>&1 | Out-String
    $code=$LASTEXITCODE
    if($code -ne 2){throw ("Expected partial diagnosis exit=2, got {0}: {1}" -f $code,$output)}
    if($output -notmatch 'Recuperacion o respaldos sin verificar' -or $output -notmatch 'Estado: PARCIAL_NO_VERIFICADO'){
        throw 'Full diagnostic did not propagate incomplete journal to PARTIAL'
    }
    Write-Host 'PASS F7 end-to-end: pending journal triggers PARTIAL (exit 2) without firewall mutation.' -ForegroundColor Green
}finally{
    if(Test-Path -LiteralPath $fixture -PathType Leaf){Remove-Item -LiteralPath $fixture -Force}
}
