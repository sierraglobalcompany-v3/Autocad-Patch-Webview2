# F10: independent PowerShell process recovering an interrupted test-only rule.
# ONLY invoked by the ephemeral GitHub-hosted Windows firewall integration.
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$JournalPath,
    [Parameter(Mandatory=$true)][string]$ExpectedRule,
    [Parameter(Mandatory=$true)][string]$ExpectedProgram
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
    throw 'F10 recovery child may only execute on GitHub-hosted disposable Windows.'
}
if($ExpectedRule -notmatch '^PCAD4_A_[0-9A-F]{24}_OUT$' -or
   $ExpectedProgram -notmatch '(?i)\\pcad4-firewall-qa-[a-f0-9]{32}\\Autodesk\\AutoCAD 2023\\acad\.exe$'){
    throw 'F10: expected a synthetic AutoCAD fixture under unique TEMP.'
}
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\ParcheCAD.Core.ps1')
. (Join-Path $root 'src\ParcheCAD.Policy.ps1')
. (Join-Path $root 'src\ParcheCAD.Firewall.ps1')
if(!(Test-PCADAdministrator)){throw 'F10: child is not administrator.'}
if((Get-PCADRuleName -Program $ExpectedProgram) -cne $ExpectedRule){throw 'F10: computed fixture rule does not match.'}
if((Get-PCADActualRuleStatus -RuleName $ExpectedRule -Program $ExpectedProgram).State -cne 'EXISTS_VALID'){
    throw 'F10: no owned rule visible in new process.'
}
$manifest=Get-Content -LiteralPath $JournalPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
if($manifest.Schema -cne 'PCAD4_OPERATION_1' -or @($manifest.Operations).Count -ne 1 -or
   [string]$manifest.Operations[0].RuleName -cne $ExpectedRule -or
   [string]$manifest.Operations[0].Program -ine $ExpectedProgram -or
   [string]$manifest.Operations[0].State -cne 'CREATING'){
    throw 'F10: invalid/foreign interrupted journal.'
}
$result=Invoke-PCADRollbackRules -JournalPath $JournalPath -Commit
if($result.Status -cne 'ROLLED_BACK' -or [int]$result.Removed -ne 1 -or [int]$result.Remaining -ne 0){
    throw 'F10: independent process could not recover its test rule.'
}
if((Get-PCADActualRuleStatus -RuleName $ExpectedRule -Program $ExpectedProgram).State -cne 'MISSING'){
    throw 'F10: test rule remained after independent-process recovery.'
}
Write-Host 'PASS F10: fresh PowerShell process recovered interrupted test rule and verified absence.' -ForegroundColor Green
