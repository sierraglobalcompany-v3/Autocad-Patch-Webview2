# F11: pure coverage classification fixtures, no firewall/network mutations.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'src\ParcheCAD.Cobertura.ps1'
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if(@($errors).Count -gt 0){throw ('F11 parser: '+($errors|Out-String))}
. $source
function Assert-F11([bool]$value,[string]$label){if(!$value){throw ('F11 FAIL: '+$label)}}

$empty=Get-PCADCoverageReport
Assert-F11 ($empty.Schema -eq 'PCAD_COVERAGE_1' -and $empty.Status -eq 'COBERTURA_NO_CERTIFICADA') 'empty coverage does not claim success'
Assert-F11 ($empty.CandidateProgramRules -eq 0 -and $empty.ProgramRulesPresent -eq 0) 'empty coverage has no candidate'
Assert-F11 (!$empty.AllAutodeskTrafficBlockedVerified -and !$empty.AutoCADWebViewLaunchPreventedVerified -and !$empty.WebViewIsolatedFromOtherAppsVerified) 'empty report cannot claim WebView isolation'

$catalog=@(
    [pscustomobject]@{Name='acad.exe';Path='C:\Users\PrivatePerson\Autodesk\AutoCAD 2027\acad.exe';Classification='AUTOCAD_PRODUCTO';Year=2027},
    [pscustomobject]@{Name='AcPerfMonAgent.exe';Path='C:\Autodesk\AutoCAD 2027\AcPerfMonAgent.exe';Classification='AUTOCAD_PRODUCTO';Year=2027},
    [pscustomobject]@{Name='AdskInstallerUpdateCheck.exe';Path='C:\Autodesk\AdODIS\AdskInstallerUpdateCheck.exe';Classification='AUTODESK_COMPARTIDO';Year=0},
    [pscustomobject]@{Name='msedgewebview2.exe';Path='C:\Microsoft\WebView2\msedgewebview2.exe';Classification='WEBVIEW2_COMPARTIDO';Year=0},
    [pscustomobject]@{Name='strange.exe';Path='C:\Unknown\strange.exe';Classification='DESCONOCIDO';Year=0}
)
$services=@([pscustomobject]@{Name='AdskLicensingService';ExecutablePath='C:\Autodesk\Shared\AdskLicensingService.exe'})
$processes=@(
    [pscustomobject]@{PID=7;Name='acad.exe';Classification='AUTOCAD_PRODUCTO'},
    [pscustomobject]@{PID=8;Name='AutodeskDesktopApp.exe';Classification='AUTODESK_COMPARTIDO'},
    [pscustomobject]@{PID=9;Name='msedgewebview2.exe';Classification='WEBVIEW2_COMPARTIDO'},
    [pscustomobject]@{PID=10;Name='mystery.exe';Classification='DESCONOCIDO'}
)
$conns=@(
    [pscustomobject]@{PID=7;Protocol='TCP';RemoteAddress='[OCULTA]'},
    [pscustomobject]@{PID=8;Protocol='TCP';RemoteAddress='[OCULTA]'},
    [pscustomobject]@{PID=9;Protocol='TCP';RemoteAddress='[OCULTA]'},
    [pscustomobject]@{PID=10;Protocol='TCP';RemoteAddress='[OCULTA]'},
    [pscustomobject]@{PID=9;Protocol='UDP_ENDPOINT';RemoteAddress='[NO_DISPONIBLE]'}
)
$plan=[pscustomobject]@{State='PLAN_NO_APLICADO';Count=2;Entries=@(
    [pscustomobject]@{Existing='EXISTS_VALID';RuleName='PCAD4_FIXTURE_1'},
    [pscustomobject]@{Existing='MISSING';RuleName='PCAD4_FIXTURE_2'}
)}
$web=[pscustomobject]@{ProbableAutoCAD=1;IsolationVerified=$false}
$r=Get-PCADCoverageReport -Catalog $catalog -Services $services -Processes $processes -Connections $conns -Plan $plan -NetworkOverview $web
Assert-F11 (@($r.Rows).Count -eq 6) 'all six categories present'
Assert-F11 ($r.CandidateProgramRules -eq 2 -and $r.ProgramRulesPresent -eq 1 -and $r.ProgramRulesMissing -eq 1 -and $r.ProgramRulesUnknown -eq 0) 'rule status without implying traffic success'
Assert-F11 ($r.AutodeskServicesInventoried -eq 1 -and $r.TcpEntriesObserved -eq 4 -and $r.TcpEntriesUnattributed -eq 2) 'TCP attribution snapshot only'
Assert-F11 ($r.UdpEndpointsObserved -eq 1 -and $r.WebViewProcessesObserved -eq 1 -and $r.WebViewProbableAutoCAD -eq 1) 'WebView counted but not isolated'
foreach($kind in @('AUTOCAD_PRODUCTO','AUTODESK_COMPARTIDO','WEBVIEW2_COMPARTIDO','DESCONOCIDO')){
    $row=@($r.Rows | Where-Object {$_.Category -eq $kind})
    Assert-F11 ($row.Count -eq 1 -and $row[0].Count -ge 1) ('class coverage '+$kind)
}
$shared=@($r.Rows | Where-Object {$_.Category -eq 'AUTODESK_COMPARTIDO'})[0]
$webrow=@($r.Rows | Where-Object {$_.Category -eq 'WEBVIEW2_COMPARTIDO'})[0]
Assert-F11 ($shared.Policy -eq 'EXCLUIDO_AUTOMATICO' -and $webrow.Policy -eq 'EXCLUIDO_AUTOMATICO') 'shared components must stay excluded'
$json=$r | ConvertTo-Json -Depth 9
Assert-F11 ($json -notmatch 'PrivatePerson' -and $json -notmatch 'RemoteAddress' -and $json -notmatch 'C:\\Users\\') 'coverage JSON does not leak private path or endpoint'
Assert-F11 ($json -match 'NO_CERTIFICADA' -and $json -notmatch '"AllAutodeskTrafficBlockedVerified":\s*true') 'no misleading total isolation'
$missingPlan=Get-PCADCoverageReport -Catalog $catalog
Assert-F11 ($missingPlan.ProgramRulesPresent -eq 0 -and !$missingPlan.AllAutodeskTrafficBlockedVerified) 'no plan cannot imply rules'
Write-Host 'PASS F11: candidate/exclusion matrix, shared Autodesk, WebView2, TCP/UDP limits and privacy.' -ForegroundColor Green
