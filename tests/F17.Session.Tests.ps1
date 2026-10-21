# F17: offline read-only session and evidence-matrix tests. No Windows modifications.
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$tool=Join-Path $root 'tools\Invoke-ParcheCADF17.ps1'
$t=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseFile($tool,[ref]$t,[ref]$errors)
if(@($errors).Count -gt 0){throw ('F17 parser error: '+($errors|Out-String))}
function Assert-F17([bool]$OK,[string]$Name){if(!$OK){throw ('F17 FAIL: '+$Name)}}
$source=Get-Content -LiteralPath $tool -Raw -ErrorAction Stop
Assert-F17 ($source -notmatch '\b(New-NetFirewallRule|Set-NetFirewallRule|Remove-NetFirewallRule|Start-Process\s+acad)\b') 'no firewall operations'
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('PCAD-F17-'+[guid]::NewGuid().ToString('N'))
$exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$expected=@('Installations','Processes','Services','Catalog','Firewall','Tasks','Historico','Connections','NetworkOverview','PolicyPreview')
function New-F17Report {
    [pscustomobject]@{
        SchemaVersion=1;Tool='ParcheCAD';ReadOnly=$true;Result='DIAGNOSTICO_COMPLETADO_SIN_CAMBIOS'
        Checks=@($expected|ForEach-Object {[pscustomobject]@{Section=$_;Status='OK'}})
        Sections=[pscustomobject]@{
            Installations=@()
            Historico=@([pscustomobject]@{Recovery=[pscustomobject]@{Status='SIN_RESPALDOS';NeedsReview=0;Unverified=0}})
            Coverage=@([pscustomobject]@{
                Schema='PCAD_COVERAGE_1';ReadOnly=$true;Status='COBERTURA_NO_CERTIFICADA'
                CandidateProgramRules=0;ProgramRulesPresent=0;ProgramRulesMissing=0;ProgramRulesUnknown=0
                AllAutodeskTrafficBlockedVerified=$false
                AutoCADWebViewLaunchPreventedVerified=$false
                WebViewIsolatedFromOtherAppsVerified=$false
            })
        }
    }
}
try{
    $null=New-Item -ItemType Directory -Path (Join-Path $tmp 'before\one') -Force
    $null=New-Item -ItemType Directory -Path (Join-Path $tmp 'after\two') -Force
    $json=New-F17Report | ConvertTo-Json -Depth 9
    [IO.File]::WriteAllText((Join-Path $tmp 'before\one\diagnostico.json'),$json)
    [IO.File]::WriteAllText((Join-Path $tmp 'after\two\diagnostico.json'),$json)
    & $exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File $tool -Mode Evaluate -SessionDirectory $tmp
    Assert-F17 ($LASTEXITCODE -eq 0) 'evaluation subprocess'
    $f=Join-Path $tmp 'evaluacion\F17_MATRIZ_EVIDENCIA.json'
    Assert-F17 (Test-Path -LiteralPath $f -PathType Leaf) 'matrix generated'
    $m=Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
    Assert-F17 ($m.Decision -ceq 'BLOCKED' -and $m.ProductionCertified -eq $false) 'no RC1 certification'
    Assert-F17 (@($m.Gates).Count -eq 10) 'all ten gates'
    Assert-F17 (@($m.Gates | Where-Object {$_.ExternalEvidence -cne 'PENDING_REVIEW'}).Count -eq 0) 'external evidence never autopasses'
    Assert-F17 ((Get-Content -LiteralPath $f -Raw) -notmatch '(?i)C:\\Users\\|192\.0\.2\.') 'matrix sanitized'
    # Expected failures: PowerShell 5.1 maps native stderr to NativeCommandError
    # under Stop. Scope Continue only around these negative test invocations.
    $oldPreference=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        & $exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File $tool -Mode Evaluate -SessionDirectory $tmp *> $null
        $overwriteExit=$LASTEXITCODE
        $after=Join-Path $tmp 'after\two\diagnostico.json'
        Remove-Item -LiteralPath $after -Force
        $null=Remove-Item -LiteralPath (Join-Path $tmp 'evaluacion') -Recurse -Force
        & $exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File $tool -Mode Evaluate -SessionDirectory $tmp *> $null
        $missingExit=$LASTEXITCODE
    } finally {$ErrorActionPreference=$oldPreference}
    Assert-F17 ($overwriteExit -ne 0) 'refuse overwrite'
    Assert-F17 ($missingExit -ne 0) 'missing after fails closed'
    Assert-F17 (!(Test-Path -LiteralPath (Join-Path $tmp 'evaluacion\F17_MATRIZ_EVIDENCIA.json'))) 'no partial matrix'
    # Expected child failures leave LASTEXITCODE=1 even when assertions PASS.
    # Reset only after both negative outcomes have been explicitly asserted.
    $global:LASTEXITCODE=0
    Write-Host 'PASS F17: session distinct, 10 evidence gates, fail-closed, no RC1 or firewall changes.' -ForegroundColor Green
}finally{
    if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Recurse -Force}
}
