# ParcheCAD 4.0 - CLI de reglas por ejecutable AutoCAD, independiente del panel.
# Preview = SOLO lectura, Apply/Rollback = explicitos y requieren administrador.
[CmdletBinding()]
param(
    [ValidateSet('Preview','Apply','Rollback','RestoreFirewall','RestoreWebView2')][string]$Mode='Preview',
    [ValidateRange(2023,2027)][int[]]$Years=@(2023,2024,2025,2026,2027),
    [string]$Manifest='',
    [string]$BackupDirectory='',
    [switch]$ConfirmChange,
    [switch]$InteractivePause
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ParcheCAD.Core.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Catalogo.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Policy.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Firewall.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Historico.ps1')
$root=Split-Path -Parent $PSScriptRoot
if(!$BackupDirectory){$BackupDirectory=Join-Path $env:ProgramData 'ParcheCAD\Operations'}
Write-Host 'ParcheCAD 4.0 | Motor de reglas por ruta' -ForegroundColor Cyan
Write-Host 'NO controla msedgewebview2.exe compartido ni garantiza ausencia de trafico.'
try {
    if($Mode -in @('RestoreFirewall','RestoreWebView2')){
        $recoveryDir=Join-Path $env:ProgramData 'ParcheCAD\Recovery'
        if($Mode -eq 'RestoreFirewall'){
            $pcad=Get-PCADRecoverableRules
            $other=@(Get-PCADTargetedBlockRules -Kind 'AutoCAD' | Where-Object {$_.IsBlocking})
            Write-Host ('FIREWALL AUTOCAD — Reglas PCAD4 verificadas {0}; otros bloqueos AutoCAD {1}; historicas/ambiguas {2}.' -f
                $pcad.VerifiedCount,$other.Count,$pcad.UnverifiedCount) -ForegroundColor Cyan
            Write-Host 'La firma PCAD4 es estructural, NO criptografica. No se modificara ninguna regla no seleccionada.'
            foreach($item in @($pcad.Candidates)){
                Write-Host ('  PCAD4 {0} / AutoCAD {1} / {2}' -f $item.RuleName,$item.Year,(Protect-PCADPath $item.Program))
            }
            foreach($item in $other){
                Write-Host ('  DETECTADA {0} / {1} / {2} / Propiedad: {3}' -f
                    $item.RuleName,$item.Direction,(Protect-PCADPath $item.Program),$item.Ownership)
            }
            if($other.Count -eq 0 -and $pcad.VerifiedCount -eq 0){
                Write-Host 'No hay bloqueos por EXE AutoCAD detectados en PersistentStore. Otros mecanismos no estan certificados.'
                exit 0
            }
            if(!$ConfirmChange){throw 'Restaurar firewall requiere -ConfirmChange.'}
            Write-Host 'ESCRIBE PROPIAS para restaurar todas las reglas PCAD4 verificadas.'
            Write-Host 'O escribe el NOMBRE EXACTO de UNA regla AutoCAD detectada para retirarla individualmente.'
            Write-Host 'ENTER cancela sin cambios.'
            $choice=[string](Read-Host 'Seleccion')
            if(!$choice.Trim()){Write-Host 'Cancelado sin cambios.';exit 0}
            if($choice -ceq 'PROPIAS'){
                if($pcad.VerifiedCount -lt 1){throw 'No hay reglas PCAD4 verificadas para restaurar.'}
                if(!(Test-PCADAdministrator)){throw 'Se necesita administrador.'}
                if((Read-Host 'Escribe RESTAURAR FIREWALL para confirmar') -cne 'RESTAURAR FIREWALL'){
                    throw 'Cancelado sin cambios.'
                }
                $result=Invoke-PCADRecoverWithoutJournal -RecoveryDirectory $recoveryDir -Commit
            }else{
                $picked=@($other|Where-Object {$_.RuleName -ceq $choice})
                if($picked.Count -ne 1){throw 'Nombre no encontrado o ambiguo. No se modificaron reglas.'}
                Write-Warning 'Regla seleccionada puede pertenecer a software ajeno. Se exportara la politica completa.'
                if((Read-Host 'Escribe RESTAURAR FIREWALL para retirar SOLO esta regla') -cne 'RESTAURAR FIREWALL'){
                    throw 'Cancelado sin cambios.'
                }
                $result=Invoke-PCADRestoreSelectedRule -Kind AutoCAD -RuleName $choice -RecoveryDirectory $recoveryDir -Commit
            }
        }else{
            $matches=@(Get-PCADTargetedBlockRules -Kind 'WebView2' | Where-Object {$_.IsBlocking})
            Write-Host ('WEBVIEW2 COMPARTIDO: {0} bloqueos locales de EXE detectados.' -f $matches.Count) -ForegroundColor Cyan
            foreach($item in $matches){
                Write-Host ('  {0} / {1} / {2} / Origen {3}' -f
                    $item.RuleName,$item.Direction,(Protect-PCADPath $item.Program),$item.Ownership)
            }
            Write-Warning 'Reglas WebView2 pueden ser de terceros. Una restauracion afecta TODAS las apps que usen esa ruta.'
            if($matches.Count -eq 0){
                Write-Host 'Sin reglas locales de bloqueo por ruta msedgewebview2.exe detectadas. Otras causas no evaluadas.'
                exit 0
            }
            if(!$ConfirmChange){throw 'Restaurar WebView2 requiere -ConfirmChange.'}
            $choice=[string](Read-Host 'Escribe el NOMBRE EXACTO de UNA regla WebView2 a quitar; ENTER cancela')
            if(!$choice.Trim()){Write-Host 'Cancelado sin cambios.';exit 0}
            if(@($matches|Where-Object {$_.RuleName -ceq $choice}).Count -ne 1){
                throw 'No se encontro una regla activa y unica con ese nombre.'
            }
            Write-Warning 'Se exportara toda la politica de firewall para conservar una copia independiente.'
            if((Read-Host 'Escribe RESTAURAR WEBVIEW2 para retirar SOLO esa regla') -cne 'RESTAURAR WEBVIEW2'){
                throw 'Cancelado sin cambios.'
            }
            $result=Invoke-PCADRestoreSelectedRule -Kind WebView2 -RuleName $choice -RecoveryDirectory $recoveryDir -Commit
        }
        $result|Format-List|Out-Host
        if($result.Status -notin @('RECOVERED','RESTORED','NO_CANDIDATES')){
            throw 'Recuperacion parcial; consultar nuevo journal en ProgramData.'
        }
        Write-Host 'Restauracion local verificada. No demuestra comunicacion real ni elimina otros bloqueos.' -ForegroundColor Green
        exit 0
    }
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
    $inst=@(Get-PCADInstallations -InternalPaths|Where-Object {$_.Year -in $Years -and $_.FileFound})
    $cat=Get-PCADExecutableCatalog -Installations $inst -SharedRoots @() -InternalPaths
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
    # No crear mas reglas si una operacion previa fue interrumpida o su respaldo no se puede validar.
    $null=Assert-PCADRecoveryReady -JournalDirectory $BackupDirectory
    Write-Warning 'El bloqueo saliente por ruta afecta tambien redes LAN; AutoCAD puede perder funciones o validaciones de suscripcion.'
    Write-Warning 'Los componentes Autodesk compartidos y el WebView2 de Microsoft no se modifican.'
    if((Read-Host 'Escribe APLICAR para confirmar') -cne 'APLICAR'){throw 'Operacion cancelada.'}
    # Reconsultar al final de la confirmacion por si aparecio un journal pendiente.
    $null=Assert-PCADRecoveryReady -JournalDirectory $BackupDirectory
    $result=Invoke-PCADApplyPlan -Plan $plan -BackupDirectory $BackupDirectory -Commit
    $result|Format-List|Out-Host
    if($result.Status -ne 'APPLIED'){exit 2}
    Write-Host 'Reglas creadas/verificadas. Las conexiones reales NO estan aun certificadas.'
    exit 0
} catch {
    Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red
    exit 2
} finally {
    if($InteractivePause -and $Mode -in @('RestoreFirewall','RestoreWebView2')){
        $null=Read-Host 'Presiona ENTER para cerrar este informe y volver a ParcheCAD'
    }
}
