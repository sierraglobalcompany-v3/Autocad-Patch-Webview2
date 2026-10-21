# F5 QA: custom installation roots + report redaction + interrupted recovery.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
foreach($name in @('ParcheCAD.Core.ps1','ParcheCAD.Catalogo.ps1','ParcheCAD.Policy.ps1','ParcheCAD.Firewall.ps1','ParcheCAD.Evidence.ps1','ParcheCAD.Historico.ps1','ParcheCAD.Diagnostico.ps1')){
    $f=Join-Path (Join-Path $root 'src') $name
    $tok=$null;$errs=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($f,[ref]$tok,[ref]$errs)
    if(@($errs).Count){throw ('Parser ERROR '+$name+': '+($errs|Out-String))}
}
. (Join-Path $root 'src\ParcheCAD.Core.ps1')
. (Join-Path $root 'src\ParcheCAD.Catalogo.ps1')
. (Join-Path $root 'src\ParcheCAD.Policy.ps1')
. (Join-Path $root 'src\ParcheCAD.Evidence.ps1')
. (Join-Path $root 'src\ParcheCAD.Firewall.ps1')
. (Join-Path $root 'src\ParcheCAD.Historico.ps1')
function Assert-F5([bool]$Condition,[string]$Reason){if(!$Condition){throw "F5 FAIL: $Reason"}}
$path='C:\Users\NombrePrivado\AppData\Local\Autodesk\AutoCAD Custom 2025\acad.exe'
Assert-F5 ((Protect-PCADPath $path) -notmatch 'NombrePrivado') 'public paths redacted'
$r=ConvertTo-PCADSafeRecord -Record ([pscustomobject]@{Name='AutoCAD';Path=$path}) -PathFields @('Path')
Assert-F5 ($r.Path -notmatch 'NombrePrivado') 'private path not leaked by clone'
Assert-F5 ($path -match 'NombrePrivado') 'safe copy did not modify private original'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('PCAD-F5-'+[guid]::NewGuid().ToString('N'))
try {
    $custom=Join-Path $temp 'DesignTools\CustomCAD2025'
    $null=New-Item -ItemType Directory -Path $custom -Force
    $main=Join-Path $custom 'acad.exe'
    $helper=Join-Path $custom 'AcPerfMonAgent.exe'
    [IO.File]::WriteAllBytes($main,[byte[]]@(0))
    [IO.File]::WriteAllBytes($helper,[byte[]]@(0))
    Assert-F5 ((Resolve-PCADRegistryInstallDirectory -InstallLocation '' -DisplayIcon ('"'+$main+'",0')) -ieq $custom) 'DisplayIcon quoted fallback'
    Assert-F5 ((Resolve-PCADRegistryInstallDirectory -InstallLocation '' -DisplayIcon ($main+',-1')) -ieq $custom) 'DisplayIcon unquoted fallback'
    Assert-F5 ((Resolve-PCADRegistryInstallDirectory -InstallLocation '' -DisplayIcon '"C:\Unknown\acad.exe",0') -eq '') 'DisplayIcon nonexistent ignored'
    Assert-F5 ((Resolve-PCADRegistryInstallDirectory -InstallLocation '' -DisplayIcon '"C:\Windows\cmd.exe",0') -eq '') 'DisplayIcon other program ignored'
    Assert-F5 ((Resolve-PCADRegistryInstallDirectory -InstallLocation $custom -DisplayIcon '"C:\Unknown\acad.exe",0') -ieq $custom) 'Existing InstallLocation priority'
    $inst=@([pscustomobject]@{Year=2025;Product='AutoCAD 2025';Path=$main;FileFound=$true})
    $cat=Get-PCADExecutableCatalog -Installations $inst -InternalPaths
    Assert-F5 ($cat.Status -eq 'OK' -and @($cat.Entries).Count -eq 2) 'private custom installation discovered'
    Assert-F5 ($cat.Entries[0].InstallationRoot -ieq $custom) 'private root kept for planner'
    $plan=New-PCADRulePlan -Catalog @($cat.Entries)
    Assert-F5 ($plan.Count -eq 2 -and $plan.Conflicts -eq 0) 'custom installation enters firewall preview'
    Assert-F5 (@($plan.Entries | Where-Object { $_.InstallationRoot -ine $custom }).Count -eq 0) 'root propagated to plan'
    foreach($e in @($plan.Entries)){$null=Assert-PCADManagedEntry -Entry $e}
    $unsafe=[pscustomobject]@{
        Program=$main;Year=2025;InstallationRoot=(Join-Path $temp 'OTHER');
        Group='PCAD4_MANAGED';Direction='Outbound';Action='Block';Profile='Any';
        RuleName=(Get-PCADRuleName -Program $main)
    }
    $rejected=$false
    try{$null=Assert-PCADManagedEntry -Entry $unsafe}catch{$rejected=$true}
    Assert-F5 $rejected 'foreign root rejected'
    $reportPlan=ConvertTo-PCADSafePlan -Plan $plan
    $reportJson=$reportPlan|ConvertTo-Json -Depth 8
    $userFolder=[regex]::Match($temp,'(?i)\\Users\\([^\\]+)\\').Groups[1].Value
    if($userFolder){Assert-F5 ($reportJson -notmatch [regex]::Escape($userFolder)) 'journal private user not leaked in public preview'}
    Assert-F5 ($plan.Entries[0].Program -notmatch '\[USUARIO\]') 'saneamiento no corrompe el plan privado'
    # Rollback must remain valid when main exe no longer exists.
    Remove-Item -LiteralPath $main -Force
    Remove-Item -LiteralPath $helper -Force
    foreach($e in @($plan.Entries)){$null=Assert-PCADManagedEntry -Entry $e -AllowMissingFile}
    $journalDir=Join-Path $temp 'journals';$null=New-Item -ItemType Directory -Path $journalDir
    $journalPath=Join-Path $journalDir 'PCAD4_fixture.json'
    $j=[pscustomobject]@{
        Schema='PCAD4_OPERATION_1';Status='PREPARED';FinishedAt='';
        Operations=@([pscustomobject]@{
            Program=$main;Year=2025;InstallationRoot=$custom;
            RuleName=(Get-PCADRuleName -Program $main);Group='PCAD4_MANAGED';
            Direction='Outbound';Action='Block';Profile='Any';State='CREATING'
        })
    }
    Write-PCADJournal -Journal $j -File $journalPath
    # Deliberately fail verification: must NOT report ROLLED_BACK when a CREATING rule cannot be inspected.
    function Test-PCADAdministrator {return $true}
    function Get-PCADActualRuleStatus {throw 'SIMULATED_NO_FIREWALL_ACCESS'}
    $undo=Invoke-PCADRollbackRules -JournalPath $journalPath -Commit
    Assert-F5 ($undo.Status -eq 'PARTIAL_ROLLBACK' -and $undo.Remaining -eq 1) 'interrupted CREATING remains blocked for review'
    $incomplete=Get-PCADRecoveryOverview -JournalDirectory $journalDir
    Assert-F5 ($incomplete.Status -eq 'PARCIAL' -and $incomplete.NeedsReview -eq 1) 'incomplete journal fail-closed'
    $completed=[pscustomobject]@{
        Schema='PCAD4_OPERATION_1';Status='APPLIED';FinishedAt='';
        Operations=@([pscustomobject]@{State='CREATED'})
    }
    Write-PCADJournal -Journal $completed -File (Join-Path $journalDir 'PCAD4_active.json')
    [IO.File]::WriteAllText((Join-Path $journalDir 'PCAD4_corrupt.json'),'{INVALID_JSON')
    $overview=Get-PCADRecoveryOverview -JournalDirectory $journalDir
    Assert-F5 ($overview.Status -eq 'PARCIAL' -and $overview.NeedsReview -eq 1 -and $overview.ActiveRules -eq 1 -and $overview.Unverified -eq 1) 'active/incomplete/corrupt journals differentiated'
    $legacy=Get-PCADLegacyOverview -JournalDirectory $journalDir
    Assert-F5 ($legacy.Recovery.NeedsReview -eq 1 -and @($legacy.Warnings).Count -gt 0) 'historical dashboard warns of incomplete operations'
} finally {
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
Write-Host 'PASS F5: custom root, path privacy, plan consistency and interrupted rollback safety.' -ForegroundColor Green
