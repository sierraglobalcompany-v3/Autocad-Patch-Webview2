# F13 — Prove a real outbound TCP outcome for a synthetic EXE on disposable Windows.
# Not a test of AutoCAD, shared Autodesk services or Microsoft WebView2.
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\ParcheCAD.Core.ps1')
. (Join-Path $root 'src\ParcheCAD.Policy.ps1')
. (Join-Path $root 'src\ParcheCAD.Firewall.ps1')

if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
    throw 'F13: only GitHub-hosted disposable Windows is permitted.'
}
if(!(Test-PCADAdministrator)){throw 'F13 BLOCKED: Windows runner has no administrator token.'}

$work=Join-Path ([IO.Path]::GetTempPath()) ('pcad4-egress-qa-'+[guid]::NewGuid().ToString('N'))
$installed=Join-Path $work 'Autodesk\AutoCAD 2023'
$exe=Join-Path $installed 'acad.exe'
$control=Join-Path $work 'ProbeControl.exe'
$ruleName=''
$manifest=''
$cleanupError=$false
$phase='SETUP'
try {
    $null=New-Item -ItemType Directory -Path $installed -Force
    # Compiled test-only client: sends no payload, credentials, file contents or
    # process metadata. Uses a stable public HTTPS TCP endpoint, IPv4 only.
    # This is NOT Autodesk software; the filename is solely a policy fixture.
    $source=@'
using System;
using System.Net.Sockets;
public static class PcadSyntheticClient {
    public static int Main(string[] args) {
        try {
            using (var client = new TcpClient(AddressFamily.InterNetwork)) {
                IAsyncResult pending = client.BeginConnect("1.1.1.1", 443, null, null);
                bool connected = pending.AsyncWaitHandle.WaitOne(4000);
                pending.AsyncWaitHandle.Close();
                if (!connected) return 21;
                client.EndConnect(pending);
                return 0;
            }
        } catch {
            return 22;
        }
    }
}
'@
    Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly $exe -OutputType ConsoleApplication -ErrorAction Stop
    Copy-Item -LiteralPath $exe -Destination $control -ErrorAction Stop
    function Test-F13Connect([string]$Program){
        & $Program | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
    $phase='BASELINE'
    if(!(Test-F13Connect $exe) -or !(Test-F13Connect $control)){
        throw 'F13 BLOCKED: baseline TCP egress unavailable; cannot test rule effectiveness honestly.'
    }
    Write-Host 'F13 BASELINE PASS: synthetic app and independent control both connected.' -ForegroundColor Green

    $profile=@(Get-NetFirewallProfile -ErrorAction Stop | Where-Object {$_.Enabled -eq $true})
    if($profile.Count -eq 0){throw 'F13 BLOCKED: Windows Firewall disabled on all network profiles.'}

    $plan=New-PCADRulePlan -Catalog @([pscustomobject]@{
        Name='acad.exe';Path=$exe;Year=2023;Classification='AUTOCAD_PRODUCTO'
        Policy='SOLO_INVENTARIO';InstallationRoot=$installed
    }) -CheckExisting
    if($plan.Count -ne 1 -or $plan.Conflicts -ne 0 -or $plan.Entries[0].Existing -ne 'MISSING'){
        throw 'F13 BLOCKED: synthetic rule candidate was not clean.'
    }
    $ruleName=[string]$plan.Entries[0].RuleName
    $phase='APPLY'
    $res=Invoke-PCADApplyPlan -Plan $plan -BackupDirectory (Join-Path $work 'journals') -Commit
    $manifest=[string]$res.Manifest
    if($res.Status -cne 'APPLIED' -or $res.Created -ne 1 -or
       (Get-PCADActualRuleStatus -RuleName $ruleName -Program $exe).State -cne 'EXISTS_VALID'){
        throw 'F13 BLOCKED: synthetic outbound firewall rule not verified.'
    }
    $phase='WITH_RULE'
    # Observe two denied attempts AND success of the same program bytes at an
    # unrelated path. This reduces false positives from a network outage.
    $targetDenied=(!(Test-F13Connect $exe) -and !(Test-F13Connect $exe))
    $controlAllowed=(Test-F13Connect $control)
    if(!$targetDenied -or !$controlAllowed){
        throw ('F13 BLOCKED: effective TCP isolation not proven (targetDenied={0}; controlAllowed={1}).' -f $targetDenied,$controlAllowed)
    }
    Write-Host 'F13 EGRESS PASS: managed app denied twice; unrelated identical client still connects.' -ForegroundColor Green

    $phase='ROLLBACK'
    $undo=Invoke-PCADRollbackRules -JournalPath $manifest -Commit
    if($undo.Status -cne 'ROLLED_BACK' -or $undo.Removed -ne 1 -or
       (Get-PCADActualRuleStatus -RuleName $ruleName -Program $exe).State -cne 'MISSING'){
        throw 'F13 BLOCKED: rollback did not restore firewall rule state.'
    }
    $phase='RESTORED'
    if(!(Test-F13Connect $exe) -or !(Test-F13Connect $control)){
        throw 'F13 BLOCKED: egress did not recover after rollback.'
    }
    Write-Host 'PASS F13: IPv4 outbound synthetic TCP allowed / denied / restored; unrelated process unaffected.' -ForegroundColor Green
    Write-Host 'F13 LIMIT: NOT a test of installed AutoCAD, UDP, IPv6, services, proxy or WebView2.'
} finally {
    if($ruleName){
        $left=@(Get-NetFirewallRule -Name $ruleName -PolicyStore PersistentStore -ErrorAction SilentlyContinue)
        if($left.Count -gt 0){
            if($left.Count -eq 1 -and [string]$left[0].Group -ceq 'PCAD4_MANAGED' -and
               [string]$left[0].Direction -eq 'Outbound' -and [string]$left[0].Action -eq 'Block'){
                $filter=@($left[0] | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue)
                if($filter.Count -eq 1 -and [string]$filter[0].Program -ieq $exe){
                    Remove-NetFirewallRule -Name $ruleName -PolicyStore PersistentStore -ErrorAction Stop
                    Write-Warning 'F13 cleanup: removed owned synthetic rule left behind after error.'
                }else{$cleanupError=$true}
            }else{$cleanupError=$true}
        }
    }
    if(Test-Path -LiteralPath $work -PathType Container){
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop
    }
    if($cleanupError){throw ('F13 BLOCKED at '+$phase+': unexpected firewall rule; runner discarded, no unrelated rule removed.')}
}
