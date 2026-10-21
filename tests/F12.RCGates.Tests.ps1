# F12: no-release acceptance gate fixtures. Does NOT modify system.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$module=Join-Path $root 'src\ParcheCAD.RCGates.ps1'
$cli=Join-Path $root 'tools\Invoke-ParcheCADRC12.ps1'
foreach($path in @($module,$cli)){
    $t=$null;$e=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$t,[ref]$e)
    if(@($e).Count){throw ('F12 parse error: '+$path+' '+($e|Out-String))}
}
. $module
function Assert-F12([bool]$condition,[string]$label){
    if(!$condition){throw ('F12 FAIL: '+$label)}
}
function New-F12Report {
    $expected=@('Installations','Processes','Services','Catalog','Firewall','Tasks',
        'Historico','Connections','NetworkOverview','PolicyPreview')
    [pscustomobject]@{
        SchemaVersion=1;Tool='ParcheCAD';ReadOnly=$true;Result='DIAGNOSTICO_COMPLETADO_SIN_CAMBIOS'
        Checks=@($expected | ForEach-Object {[pscustomobject]@{Section=$_;Status='OK'}})
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
$b=New-F12Report
$a=New-F12Report
$r=Get-PCADRC12Assessment -Before $b -After $a
Assert-F12 ($r.Decision -eq 'BLOCKED' -and !$r.ProductionCertified) 'empty machine blocked'
Assert-F12 (@($r.Gates).Count -eq 10) 'ten gates'
Assert-F12 (@($r.Gates | Where-Object {$_.Status -eq 'PASS'}).Count -eq 1) 'only snapshot gate passes'
Assert-F12 (!$r.WebViewIsolatedVerified -and !$r.AllAutodeskTrafficBlockedVerified) 'no false isolation'

$a.Sections.Installations=@([pscustomobject]@{
    FileFound=$true;Year=2027;Name='acad.exe';Publisher='Autodesk'
    Path='C:\Users\MyPrivateName\Autodesk\AutoCAD 2027\acad.exe'
})
$a.Sections.Coverage[0].CandidateProgramRules=2
$a.Sections.Coverage[0].ProgramRulesPresent=2
$r=Get-PCADRC12Assessment -Before $b -After $a
Assert-F12 ($r.After.InstallationsFound -eq 1 -and $r.After.Years[0] -eq 2027) 'observed installation'
Assert-F12 (@($r.Gates | Where-Object {$_.Gate -eq 'AUTOCAD_INSTALADO'})[0].Status -eq 'OBSERVADO') 'binary presence only observed'
Assert-F12 (@($r.Gates | Where-Object {$_.Gate -eq 'REGLAS_SALIENTES'})[0].Status -eq 'CONFIGURACION_OBSERVADA') 'configured rule not network evidence'
Assert-F12 (@($r.Gates | Where-Object {$_.Gate -eq 'TRAFICO_AUTODESK'})[0].Status -eq 'BLOCKED') 'no traffic pass'
Assert-F12 ($r.Decision -eq 'BLOCKED' -and @($r.Gates | Where-Object {$_.Gate -eq 'GUI_UAC'})[0].Status -eq 'BLOCKED') 'still blocked with candidate rules'
$json=$r|ConvertTo-Json -Depth 9
Assert-F12 ($json -notmatch 'MyPrivateName' -and $json -notmatch 'C:\\Users\\') 'sanitized assessment'
Assert-F12 ($json -notmatch 'RemoteAddress') 'no IP copying'
$a.Checks[0].Status='PARCIAL'
$r=Get-PCADRC12Assessment -Before $b -After $a
Assert-F12 (!$r.After.Valid -and @($r.Gates | Where-Object {$_.Gate -eq 'DIAGNOSTICOS'})[0].Status -eq 'BLOCKED') 'partial diagnostic invalidates snapshot'
$a.Checks[0].Status='OK'
$a.Sections.Coverage[0].WebViewIsolatedFromOtherAppsVerified=$true
$r=Get-PCADRC12Assessment -Before $b -After $a
Assert-F12 (!$r.After.Valid -and !$r.WebViewIsolatedVerified) 'untrusted report cannot override WebView restriction'
$a.Sections.Coverage[0].WebViewIsolatedFromOtherAppsVerified=$false
$a.Sections.Coverage[0].ProgramRulesPresent=3
$r=Get-PCADRC12Assessment -Before $b -After $a
Assert-F12 (!$r.After.Valid) 'incoherent firewall counts fail closed'
$a.Sections.Coverage[0].ProgramRulesPresent=2
$a.Sections.Historico[0].Recovery.NeedsReview=1
$r=Get-PCADRC12Assessment -Before $b -After $a
Assert-F12 (!$r.After.Valid) 'unrecovered journal blocks gate'
$a.Sections.Historico[0].Recovery.NeedsReview=0
$a.Checks[0].Section='Processes'
$r=Get-PCADRC12Assessment -Before $b -After $a
Assert-F12 (!$r.After.Valid) 'duplicate stage blocks acceptance'

Write-Host 'PASS F12: fail-closed acceptance, before/after snapshots, no false traffic/WebView/UAC/reboot certification.' -ForegroundColor Green
