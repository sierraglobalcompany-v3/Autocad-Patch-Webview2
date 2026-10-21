# ParcheCAD 4.0 - CLI de reglas por ejecutable AutoCAD, independiente del panel.
# Preview = SOLO lectura, Apply/Rollback = explicitos y requieren administrador.
[CmdletBinding()]
param(
    [ValidateSet('Preview','Apply','Rollback')][string]$Mode='Preview',
    [ValidateRange(2023,2027)][int[]]$Years=@(2023,2024,2025,2026,2027),
    [string]$Manifest='',
    [string]$BackupDirectory='',
    [switch]$ConfirmChange
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ParcheCAD.Core.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Catalogo.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Policy.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Firewall.ps1')
$root=Split-Path -Parent $PSScriptRoot
if(!$BackupDirectory){$BackupDirectory=Join-Path (Join-Path $root 'informes') 'operaciones'}
Write-Host 'ParcheCAD 4.0 | Motor de reglas por ruta' -ForegroundColor Cyan
Write-Host 'NO controla msedgewebview2.exe compartido ni garantiza ausencia de trafico.'
try {
    if($Mode -eq 'Rollback') {
        if(!$Manifest){throw 'Rollback requiere -Manifest con respaldo original.'}
        if(!$ConfirmChange){throw 'Rollback requiere -ConfirmChange y confirmacion interactiva.'}
        if((Read-Host 'Escribe REVERTIR para confirmar') -cne 'REVERTIR'){throw 'Operacion cancelada.'}
        $result=Invoke-PCADRollbackRules -JournalPath $Manifest -Commit
        $result|Format-List|Out-Host
        if($result.Status -ne 'ROLLED_BACK'){exit 2}
        exit 0
    }
    Write-Host 'Descubriendo instalaciones reales y ejecutables sin modificar Windows...'
    $inst=@(Get-PCADInstallations|Where-Object {$_.Year -in $Years -and $_.FileFound})
    $cat=Get-PCADExecutableCatalog -Installations $inst
    if($cat.Status -ne 'OK'){
        Write-Warning 'Catalogo incompleto; se conserva detalle de advertencias.'
        @($cat.Warnings)|ForEach-Object {Write-Warning $_}
    }
    $plan=New-PCADRulePlan -Catalog @($cat.Entries) -CheckExisting
    Write-Host ('Versiones detectadas: '+(@($inst|Select-Object -ExpandProperty Year -Unique)-join ', '))
    Write-Host ('Candidatos: {0}, excluidos: {1}, conflictos: {2}' -f $plan.Count,@($plan.Excluded).Count,$plan.Conflicts)
    foreach($item in @($plan.Entries)){
        Write-Host ('  {0} / {1} / {2}' -f $item.Year,$item.Existing,(Protect-PCADPath $item.Program))
    }
    if($Mode -eq 'Preview') {
        Write-Host 'SOLO VISTA PREVIA. No se ha creado ninguna regla.' -ForegroundColor Yellow
        exit 0
    }
    if(!$ConfirmChange){throw 'Apply requiere -ConfirmChange y confirmacion interactiva.'}
    if($cat.Status -ne 'OK'){throw 'No aplicar: el inventario de EXE es parcial.'}
    if($plan.Count -eq 0){throw 'No hay ejecutables confirmados para aplicar.'}
    if($plan.Conflicts -gt 0){throw 'No aplicar: existen reglas con conflicto de identidad.'}
    Write-Warning 'El bloqueo saliente por ruta afecta tambien redes LAN; AutoCAD puede perder funciones o validaciones de suscripcion.'
    Write-Warning 'Los componentes Autodesk compartidos y el WebView2 de Microsoft no se modifican.'
    if((Read-Host 'Escribe APLICAR para confirmar') -cne 'APLICAR'){throw 'Operacion cancelada.'}
    $result=Invoke-PCADApplyPlan -Plan $plan -BackupDirectory $BackupDirectory -Commit
    $result|Format-List|Out-Host
    if($result.Status -ne 'APPLIED'){exit 2}
    Write-Host 'Reglas creadas/verificadas. Las conexiones reales NO estan aun certificadas.'
    exit 0
} catch {
    Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red
    exit 2
}
