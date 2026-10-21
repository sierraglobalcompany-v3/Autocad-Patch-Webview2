# F17: real Windows hosted read-only before/after/evaluate integration smoke.
# This runner has NO AutoCAD and does NOT certify any live product or real QA.
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
    throw 'F17 Windows smoke can only run in ephemeral GitHub-hosted Windows.'
}
$root=Split-Path -Parent $PSScriptRoot
$tool=Join-Path $root 'tools\Invoke-ParcheCADF17.ps1'
$psExe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$session=Join-Path ([IO.Path]::GetTempPath()) ('PCAD-F17-SMOKE-'+[guid]::NewGuid().ToString('N'))
try{
    & $psExe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File $tool -Mode Before -SessionDirectory $session
    if($LASTEXITCODE -ne 0){throw 'F17 Before on clean hosted Windows failed.'}
    $before=@(Get-ChildItem -LiteralPath (Join-Path $session 'before') -Recurse -File -Filter diagnostico.json -ErrorAction Stop)
    if($before.Count -ne 1){throw 'F17 Before failed to generate exactly one report.'}
    # F0 GeneratedAt has seconds precision: separate captures by >=2 seconds.
    Start-Sleep -Seconds 2
    & $psExe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File $tool -Mode After -SessionDirectory $session
    if($LASTEXITCODE -ne 0){throw 'F17 After on clean hosted Windows failed.'}
    $after=@(Get-ChildItem -LiteralPath (Join-Path $session 'after') -Recurse -File -Filter diagnostico.json -ErrorAction Stop)
    if($after.Count -ne 1){throw 'F17 After failed to generate exactly one report.'}
    if((Get-FileHash -LiteralPath $before[0].FullName -Algorithm SHA256).Hash -ceq
       (Get-FileHash -LiteralPath $after[0].FullName -Algorithm SHA256).Hash){
        throw 'F17 Windows smoke unexpectedly reused its diagnostic report.'
    }
    & $psExe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File $tool -Mode Evaluate -SessionDirectory $session
    if($LASTEXITCODE -ne 0){throw 'F17 Evaluate on clean hosted Windows failed.'}
    $assessment=Get-Content -LiteralPath (Join-Path $session 'evaluacion\RC12_EVALUACION.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $matrix=Get-Content -LiteralPath (Join-Path $session 'evaluacion\F17_MATRIZ_EVIDENCIA.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if($assessment.Decision -cne 'BLOCKED' -or $assessment.ProductionCertified -ne $false -or
       $matrix.Decision -cne 'BLOCKED' -or $matrix.ProductionCertified -ne $false -or
       $matrix.EvidenceReviewed -ne $false -or $matrix.SameMachineVerified -ne $false -or
       !$matrix.TimestampOrderVerified -or !$matrix.ContentsDistinctVerified -or
       @($matrix.Gates).Count -ne 10){
        throw 'F17 real-Windows smoke incorrectly approved RC1 or lost an acceptance gate.'
    }
    Write-Host 'PASS F17 Windows smoke: Before -> After -> Evaluate; 10 gates, LAB-only, RC1 BLOCKED.' -ForegroundColor Green
}finally{
    if(Test-Path -LiteralPath $session -PathType Container){
        Remove-Item -LiteralPath $session -Recurse -Force -ErrorAction Stop
    }
}
