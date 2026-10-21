# F15: junction/reparse test on disposable Windows. No firewall changes.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
foreach($src in @('ParcheCAD.Policy.ps1','ParcheCAD.Catalogo.ps1','ParcheCAD.Firewall.ps1')){
    $path=Join-Path (Join-Path $root 'src') $src
    $tokens=$null;$parseErrors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    if(@($parseErrors).Count){throw ('F15 parser failure: '+$src+' '+($parseErrors|Out-String))}
}
. (Join-Path $root 'src\ParcheCAD.Core.ps1')
. (Join-Path $root 'src\ParcheCAD.Catalogo.ps1')
. (Join-Path $root 'src\ParcheCAD.Policy.ps1')
. (Join-Path $root 'src\ParcheCAD.Firewall.ps1')
function Assert-F15([bool]$Pass,[string]$Label){if(!$Pass){throw ('F15 FAIL: '+$Label)}}
$work=Join-Path ([IO.Path]::GetTempPath()) ('pcad-f15-'+[guid]::NewGuid().ToString('N'))
$install=Join-Path $work 'AutoCAD 2027'
$outside=Join-Path $work 'Unrelated Application'
$junction=Join-Path $install 'ExtPlugin'
try {
    $null=New-Item -ItemType Directory -Path $install,$outside -Force
    $acad=Join-Path $install 'acad.exe'
    $helper=Join-Path $install 'AcPerfMonAgent.exe'
    $foreign=Join-Path $outside 'UnrelatedTool.exe'
    foreach($exe in @($acad,$helper,$foreign)){[IO.File]::WriteAllBytes($exe,[byte[]]@(0))}
    Assert-F15 (Assert-PCADNoReparseComponents -Program $helper) 'normal path accepted'
    # A junction inside the legitimate install points OUTSIDE it, despite the
    # target path string still appearing to belong to the AutoCAD directory.
    $null=New-Item -ItemType Junction -Path $junction -Target $outside -ErrorAction Stop
    $redirected=Join-Path $junction 'UnrelatedTool.exe'
    Assert-F15 (Test-Path -LiteralPath $redirected -PathType Leaf) 'synthetic junction resolves'
    $forged=[pscustomobject]@{
        Year=2027;Name='UnrelatedTool.exe';Path=$redirected
        InstallationRoot=$install;Classification='AUTOCAD_PRODUCTO';Policy='SOLO_INVENTARIO'
    }
    $plan=New-PCADRulePlan -Catalog @($forged,[pscustomobject]@{
        Year=2027;Name='AcPerfMonAgent.exe';Path=$helper;InstallationRoot=$install
        Classification='AUTOCAD_PRODUCTO';Policy='SOLO_INVENTARIO'
    })
    Assert-F15 ($plan.Count -eq 1 -and @($plan.Excluded).Count -eq 1) 'forged path excluded at planning'
    $entry=[pscustomobject]@{
        RuleName=(Get-PCADRuleName -Program $redirected)
        Group='PCAD4_MANAGED';Program=$redirected;Year=2027
        InstallationRoot=$install;Direction='Outbound';Action='Block';Profile='Any'
    }
    $denied=$false
    try{$null=Assert-PCADManagedEntry -Entry $entry}catch{$denied=$true}
    Assert-F15 $denied 'forged path denied again at firewall preflight'
    # In rollback, exact owned rule identity is still required, but the path
    # may have disappeared or been replaced. Not a permission to create it.
    $recoveryAllowed=$false
    try{$null=Assert-PCADManagedEntry -Entry $entry -AllowMissingFile;$recoveryAllowed=$true}catch{}
    Assert-F15 $recoveryAllowed 'own previously created rule can still be rolled back'
    $catalog=Get-PCADExecutableCatalog -Installations @([pscustomobject]@{
        Year=2027;FileFound=$true;Path=$acad
    }) -SharedRoots @()
    Assert-F15 ($catalog.Status -eq 'PARCIAL') 'junction omission explicitly marks catalog PARTIAL'
    Assert-F15 (@($catalog.Entries|Where-Object {$_.Name -eq 'UnrelatedTool.exe'}).Count -eq 0) 'catalog never walks redirected app'
    Assert-F15 (@($catalog.Warnings|Where-Object {$_ -match 'Enlace|junction'}).Count -gt 0) 'warn user about skipped path'
    $fakeInstall=Join-Path $work 'AutoCAD 2026'
    $null=New-Item -ItemType Junction -Path $fakeInstall -Target $outside -ErrorAction Stop
    $outsideAcad=Join-Path $outside 'acad.exe'
    [IO.File]::WriteAllBytes($outsideAcad,[byte[]]@(0))
    $deniedRoot=$false
    try{
        $null=Assert-PCADProgramInstallRoot -Program (Join-Path $fakeInstall 'acad.exe') -Year 2026 -InstallRoot $fakeInstall
    }catch{$deniedRoot=$true}
    Assert-F15 $deniedRoot 'installation root junction rejected'
    Write-Host 'PASS F15: no junction traversal, reject forged firewall path, allow exact own-rule rollback.' -ForegroundColor Green
}finally{
    # Junction points must be removed WITHOUT deleting the external target.
    # Windows PowerShell 5.1 Remove-Item on junction may throw or traverse it.
    # .NET deletes the directory REPARSE ENTRY only (non-recursive), never target.
    if([IO.Directory]::Exists($junction)){[IO.Directory]::Delete($junction,$false)}
    $linkedRoot=Join-Path $work 'AutoCAD 2026'
    if([IO.Directory]::Exists($linkedRoot)){[IO.Directory]::Delete($linkedRoot,$false)}
    if(Test-Path -LiteralPath $work -PathType Container){Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop}
}
