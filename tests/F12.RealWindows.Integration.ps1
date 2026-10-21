# F12 end-to-end smoke on ephemeral Windows. Read-only and NO AutoCAD required.
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
    throw 'F12 integration smoke is restricted to GitHub-hosted Windows.'
}
$root=Split-Path -Parent $PSScriptRoot
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('pcad-f12-'+[guid]::NewGuid().ToString('N'))
$preDir=Join-Path $tmp 'diag'
$outDir=Join-Path $tmp 'out'
try{
    $null=New-Item -ItemType Directory -Path $preDir -Force
    $psExe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $psExe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $root 'src\ParcheCAD.Diagnostico.ps1') -OutputDirectory $preDir
    if($LASTEXITCODE -ne 0){throw 'F12 requires valid baseline diagnostics on ephemeral Windows.'}
    $reports=@(Get-ChildItem -LiteralPath $preDir -Recurse -Filter 'diagnostico.json' -File)
    if($reports.Count -ne 1){throw 'F12: exactly one diagnostic report expected.'}
    $path=$reports[0].FullName
    # Two identical snapshots are an integration smoke, NOT proof of any change.
    & $psExe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $root 'tools\Invoke-ParcheCADRC12.ps1') -Before $path -After $path -OutputDirectory $outDir
    if($LASTEXITCODE -ne 0){throw 'F12 evaluation of diagnostic JSON failed.'}
    $file=Join-Path $outDir 'RC12_EVALUACION.json'
    $txt=Join-Path $outDir 'RC12_RESUMEN.txt'
    if(!(Test-Path -LiteralPath $file) -or !(Test-Path -LiteralPath $txt)){throw 'F12: evaluation not exported.'}
    $result=Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    if($result.Decision -cne 'BLOCKED' -or $result.ProductionCertified -ne $false -or
       $result.AllAutodeskTrafficBlockedVerified -ne $false -or
       $result.WebViewIsolatedVerified -ne $false -or @($result.Gates).Count -ne 10){
        throw 'F12: runner falsely certified a release or produced incomplete gate matrix.'
    }
    $raw=Get-Content -LiteralPath $file -Raw
    if($raw -match '"RemoteAddress"' -or $raw -match '(?i)C:\\Users\\'){
        throw 'F12: private paths or network endpoints leaked into output.'
    }
    Write-Host 'PASS F12 integrated: true Windows diagnostic -> read-only gate matrix BLOCKED (not RC1).' -ForegroundColor Green
}finally{
    if(Test-Path -LiteralPath $tmp -PathType Container){Remove-Item -LiteralPath $tmp -Recurse -Force}
}
