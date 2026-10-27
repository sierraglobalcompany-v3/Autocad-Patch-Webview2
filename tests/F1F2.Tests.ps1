# F1/F2: pruebas puras y catalogo con fixtures temporales, sin tocar firewall.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
foreach($name in @('ParcheCAD.Core.ps1','ParcheCAD.Catalogo.ps1','ParcheCAD.Historico.ps1','ParcheCAD.Diagnostico.ps1','ParcheCAD.Panel.ps1')){
    $file=Join-Path (Join-Path $root 'src') $name
    $tok=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tok,[ref]$errors)
    if(@($errors).Count -gt 0){throw ("Parser FAIL: {0}: {1}" -f $name,($errors|Out-String))}
    $txt=[IO.File]::ReadAllText($file)
    if($txt -match '(?i)\b(New|Remove|Set|Disable|Enable)-NetFirewallRule\b|\b(Disable|Enable|Unregister|Register)-ScheduledTask\b'){
        throw "Forbidden mutation command in $name"
    }
}
. (Join-Path $root 'src\ParcheCAD.Core.ps1')
. (Join-Path $root 'src\ParcheCAD.Catalogo.ps1')
. (Join-Path $root 'src\ParcheCAD.Historico.ps1')
function Assert-PCAD([bool]$Condition,[string]$Label){if(!$Condition){throw "FAIL: $Label"}}
$c=Get-PCADFileClass -FilePath 'C:\Program Files\Autodesk\AutoCAD 2023\acad.exe' -InstallationRoot 'C:\Program Files\Autodesk\AutoCAD 2023' -Year 2023
Assert-PCAD ($c.Classification -eq 'AUTOCAD_PRODUCTO' -and $c.Confidence -eq 'ALTA' -and $c.FirewallEligible) 'acad 2023 exact'
$c=Get-PCADFileClass -FilePath 'C:\Program Files\Autodesk\AutoCAD 2027\AcPerfMonAgent.exe' -InstallationRoot 'C:\Program Files\Autodesk\AutoCAD 2027' -Year 2027
Assert-PCAD ($c.Classification -eq 'AUTOCAD_PRODUCTO' -and $c.Confidence -eq 'MEDIA') '2027 auxiliary'
$c=Get-PCADFileClass -FilePath 'C:\Program Files\Autodesk\AdODIS\AdskInstallerUpdateCheck.exe' -Kind 'SHARED'
Assert-PCAD ($c.Classification -eq 'AUTODESK_COMPARTIDO' -and !$c.FirewallEligible) 'shared'
$c=Get-PCADFileClass -FilePath 'C:\Program Files (x86)\Microsoft\EdgeWebView\Application\msedgewebview2.exe' -InstallationRoot 'C:\Program Files\Autodesk\AutoCAD 2023' -Year 2023
Assert-PCAD ($c.Classification -eq 'WEBVIEW2_COMPARTIDO' -and !$c.FirewallEligible) 'webview cannot be exclusive'
$c=Get-PCADFileClass -FilePath 'C:\other\acad.exe' -InstallationRoot 'C:\Program Files\Autodesk\AutoCAD 2027' -Year 2027
Assert-PCAD (!$c.FirewallEligible) 'foreign acad.exe'
$h=Get-PCADLegacyAssessment -Name 'WebView2GlobalBlock.5EE264B543B814BD.Outbound' -Program 'C:\Program Files (x86)\Microsoft\EdgeWebView\Application\155\msedgewebview2.exe' -Action 'Block' -Direction 'Outbound' -Enabled 'True'
Assert-PCAD ($h.Category -eq 'WEBVIEW2_COMPARTIDO' -and $h.Assessment -eq 'ALERTA_WEBVIEW2_COMPARTIDO' -and !$h.MayDelete) 'webview legacy risk and no delete'
$h=Get-PCADLegacyAssessment -Name 'PCAD_A_V3_123' -Program 'C:\Program Files\Autodesk\AutoCAD 2023\acad.exe' -Action 'Block' -Direction 'Outbound' -Enabled 'True'
Assert-PCAD ($h.Category -eq 'AUTOCAD_PRODUCTO' -and !$h.MayDelete) 'legacy owned name not proof'
$o=Get-PCADLegacyOverview -Firewall @(
 [pscustomobject]@{Name='WebView2GlobalBlock.5EE264B543B814BD.Outbound';DisplayName='';Program='C:\Microsoft\EdgeWebView\Application\msedgewebview2.exe';Action='Block';Direction='Outbound';Enabled='True'}
) -Tasks @([pscustomobject]@{Name='Autodesk Block WebView2';State='Ready'})
Assert-PCAD ($o.WebView2ActiveRules -eq 1 -and $o.SuspectedTasks -eq 1) 'legacy summary'
Assert-PCAD ($o.Items[0].CanRemoveAutomatically -eq $false) 'historical safety'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('PCAD-F1-FIXTURE-'+[guid]::NewGuid().ToString('N'))
try{
    $dir=Join-Path $temp 'Autodesk\AutoCAD 2023'
    $child=Join-Path $dir 'Support'
    $null=New-Item -ItemType Directory -Path $child -Force
    foreach($p in @((Join-Path $dir 'acad.exe'),(Join-Path $child 'AcPerfMonAgent.exe'))){
        [IO.File]::WriteAllBytes($p,[byte[]]@(0))
    }
    $catalog=Get-PCADExecutableCatalog -Installations @([pscustomobject]@{Year=2023;FileFound=$true;Path=(Join-Path $dir 'acad.exe')}) -MaxFilesPerProduct 20
    Assert-PCAD ($catalog.Status -eq 'OK' -and @($catalog.Entries).Count -eq 2) 'fixture catalog 2 executables'
    Assert-PCAD (@($catalog.Entries | Where-Object {$_.Classification -ne 'AUTOCAD_PRODUCTO'}).Count -eq 0) 'fixture only autocad'
    $limited=Get-PCADExecutableCatalog -Installations @([pscustomobject]@{Year=2023;FileFound=$true;Path=(Join-Path $dir 'acad.exe')}) -MaxFilesPerProduct 1
    Assert-PCAD ($limited.Status -eq 'PARCIAL') 'catalog truncation must warn'
    $budget=Get-PCADCatalogTree -Root $dir -MaxScanSeconds 0
    Assert-PCAD ($budget.Partial -and @($budget.Entries).Count -eq 0) 'elapsed scan budget must fail-closed'
    $visible=Get-PCADExecutableCatalog -Installations @([pscustomobject]@{Year=2023;FileFound=$true;Path=(Join-Path $dir 'acad.exe')}) -MaxFilesPerProduct 20 -ShowProgress
    Assert-PCAD ($visible.Status -eq 'OK' -and @($visible.Entries).Count -eq 2) 'console progress path returns same catalogue'
} finally {
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
Write-Host 'PASS F1/F2: parser, clasificacion, catalogo ficticio, riesgos y ausencia de mutaciones.' -ForegroundColor Green
