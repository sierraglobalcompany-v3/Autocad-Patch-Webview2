# F14: read-only shared Autodesk root inventory fixtures.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$file=Join-Path $root 'src\ParcheCAD.Catalogo.ps1'
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw ('F14 Parser failed: '+($errors|Out-String))}
. (Join-Path $root 'src\ParcheCAD.Core.ps1')
. $file
. (Join-Path $root 'src\ParcheCAD.Policy.ps1')
function Assert-F14([bool]$condition,[string]$label){if(!$condition){throw ('F14 FAIL: '+$label)}}
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('pcad-f14-'+[guid]::NewGuid().ToString('N'))
$install=Join-Path $tmp 'AutoCAD 2027'
$shared=Join-Path $tmp 'Autodesk\AdODIS'
$deep=Join-Path $shared 'A\B\C'
try{
    $null=New-Item -ItemType Directory -Path $install,$deep -Force
    $acad=Join-Path $install 'acad.exe'
    $helper=Join-Path $install 'AcPerfMonAgent.exe'
    $installer=Join-Path $shared 'AdskInstallerUpdateCheck.exe'
    $child=Join-Path $deep 'AdskUninstallHelper.exe'
    foreach($path in @($acad,$helper,$installer,$child)){[IO.File]::WriteAllBytes($path,[byte[]]@(0))}
    $fakeInstall=[pscustomobject]@{Year=2027;FileFound=$true;Path=$acad}
    $catalog=Get-PCADExecutableCatalog -Installations @($fakeInstall) -SharedRoots @($shared) -InternalPaths -MaxDepth 7 -MaxSharedDepth 5
    Assert-F14 ($catalog.Status -eq 'OK' -and $catalog.SharedStatus -eq 'INVENTARIO_LIMITADO') 'full product and shared reads'
    Assert-F14 (@($catalog.Entries).Count -eq 4) 'four distinct executable rows'
    Assert-F14 (@($catalog.Entries|Where-Object {$_.Classification -eq 'AUTOCAD_PRODUCTO'}).Count -eq 2) 'product classification'
    Assert-F14 (@($catalog.Entries|Where-Object {$_.Classification -eq 'AUTODESK_COMPARTIDO'}).Count -eq 2) 'shared classification'
    $sharedRows=@($catalog.Entries|Where-Object {$_.Classification -eq 'AUTODESK_COMPARTIDO'})
    Assert-F14 (@($sharedRows|Where-Object {$_.Year -ne 0 -or $_.Policy -ne 'SOLO_INVENTARIO'}).Count -eq 0) 'shared never eligible'
    $plan=New-PCADRulePlan -Catalog @($catalog.Entries)
    Assert-F14 ($plan.Count -eq 2 -and @($plan.Excluded).Count -eq 2) 'shared must not join policy'
    $depth=Get-PCADExecutableCatalog -Installations @($fakeInstall) -SharedRoots @($shared) -MaxSharedDepth 1
    Assert-F14 ($depth.Status -eq 'OK' -and $depth.SharedStatus -eq 'PARCIAL') 'shared deep scan flagged separately'
    Assert-F14 (@($depth.Warnings|Where-Object {$_ -match 'Autodesk compartido'}).Count -gt 0) 'shared warnings preserved'
    Assert-F14 (@($depth.Entries|Where-Object {$_.Classification -eq 'AUTOCAD_PRODUCTO'}).Count -eq 2) 'shared limitation does not impact product'
    $limit=Get-PCADExecutableCatalog -Installations @($fakeInstall) -SharedRoots @($shared) -MaxFilesPerProduct 1
    Assert-F14 ($limit.Status -eq 'PARCIAL') 'product truncation prevents false complete'
    $remote=Get-PCADCatalogTree -Root '\\example\share' -MaxFiles 10
    Assert-F14 ($remote.Partial -and @($remote.Entries).Count -eq 0) 'network roots rejected'
    Write-Host 'PASS F14: shared roots, exclusions, depth/truncation and independent inventory status.' -ForegroundColor Green
}finally{
    if(Test-Path -LiteralPath $tmp -PathType Container){Remove-Item -LiteralPath $tmp -Recurse -Force}
}
