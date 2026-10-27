# ParcheCAD 4.2 - vista previa AutoCAD en proceso independiente y solo lectura.
# Evita bloquear el hilo UI de WinForms durante el catalogo y las consultas de firewall.
#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ParcheCAD.Core.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Catalogo.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Policy.ps1')

$folder=[IO.Path]::GetFullPath($OutputDirectory)
if($folder -match '^\\\\'){throw 'Vista previa: no se admiten carpetas de red.'}
$cursor=$folder
while($cursor){
    if(Test-Path -LiteralPath $cursor){
        if(((Get-Item -LiteralPath $cursor -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'Vista previa: ruta enlazada o junction no permitida.'
        }
    }
    $parent=[IO.Path]::GetDirectoryName($cursor)
    if(!$parent -or $parent -eq $cursor){break}
    $cursor=$parent
}
if(!(Test-Path -LiteralPath $folder -PathType Container)){throw 'Vista previa: carpeta de sesion inexistente.'}
$reportPath=Join-Path $folder 'preview.json'
$markerPath=Join-Path $folder 'preview.exitcode'
$stagePath=Join-Path $folder 'preview.fase.txt'
foreach($file in @($reportPath,$markerPath,$stagePath)){
    if(Test-Path -LiteralPath $file){throw 'Vista previa existente; no sobrescribir.'}
}
$utf8=New-Object Text.UTF8Encoding($false)
function Write-PCADPreviewStage([string]$Message){
    [IO.File]::WriteAllText($stagePath,$Message,$utf8)
}
try{
    Write-PCADPreviewStage '1/3 - Localizando instalaciones AutoCAD...'
    $inst=@(Get-PCADInstallations -InternalPaths | Where-Object {$_.FileFound})
    Write-PCADPreviewStage '2/3 - Catalogando ejecutables AutoCAD (puede tardar)...'
    # Excluir explicitamente todas las raices Autodesk compartidas.
    $catalog=Get-PCADExecutableCatalog -Installations $inst -SharedRoots @() -InternalPaths
    Write-PCADPreviewStage '3/3 - Comprobando reglas existentes, filtros y conflictos...'
    $plan=New-PCADRulePlan -Catalog @($catalog.Entries) -CheckExisting
    $years=@($inst | ForEach-Object {$_.Year} | Sort-Object -Unique)
    $installed=@($plan.Entries | Where-Object {$_.Existing -ceq 'EXISTS_VALID'}).Count
    $missing=@($plan.Entries | Where-Object {$_.Existing -ceq 'MISSING'}).Count
    $unverified=@($plan.Entries | Where-Object {$_.Existing -notin @('EXISTS_VALID','MISSING')}).Count
    if(($installed+$missing+$unverified) -ne [int]$plan.Count){
        throw 'Conteo de reglas incoherente: no publicar un estado falso.'
    }
    $actual=if($catalog.Status -ne 'OK'){'INVENTARIO_PARCIAL'}
        elseif($unverified -gt 0){'NO_VERIFICADO'}
        elseif($plan.Count -eq 0){'SIN_CANDIDATAS'}
        elseif($installed -eq $plan.Count){'TODAS_VERIFICADAS'}
        elseif($installed -eq 0){'NINGUNA_INSTALADA'}
        else{'APLICACION_PARCIAL'}
    $report=[ordered]@{
        Schema='PCAD_AUTOCAD_PREVIEW_1';Tool='ParcheCAD';Version='4.3'
        ReadOnly=$true;NoFirewallChanges=$true
        Status=if($catalog.Status -eq 'OK'){'PREVIEW_COMPLETA'}else{'PREVIEW_PARCIAL'}
        GeneratedAt=(Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        Installations=$inst.Count;Years=@($years)
        Candidates=[int]$plan.Count;Conflicts=[int]$plan.Conflicts
        InstalledValid=[int]$installed;MissingRules=[int]$missing;UnverifiedRules=[int]$unverified
        RuleVerificationState=$actual
        Excluded=@($plan.Excluded).Count
        CatalogStatus=[string]$catalog.Status
        PlanState=[string]$plan.State
        WebView2SharedExcluded=$true
        Limit='Vista previa no crea reglas ni demuestra bloqueo de trafico.'
    }
    [IO.File]::WriteAllText($reportPath,($report | ConvertTo-Json -Depth 5),$utf8)
    [IO.File]::WriteAllText($markerPath,'0',$utf8)
    Write-PCADPreviewStage '3/3 - Vista previa guardada.'
    Write-Host ('Vista previa: {0} instalaciones, {1} candidatas, {2} conflictos; catalogo {3}' -f
      $inst.Count,$plan.Count,$plan.Conflicts,$catalog.Status)
    Write-Host ('Estado local: {0}/{1} reglas válidas, {2} faltantes, {3} sin verificar; {4}.' -f $installed,$plan.Count,$missing,$unverified,$actual)
    exit 0
}catch{
    try{[IO.File]::WriteAllText($markerPath,'2',$utf8)}catch{}
    Write-Error ('Vista previa parcial: '+$_.Exception.GetType().Name+': '+$_.Exception.Message)
    exit 2
}
