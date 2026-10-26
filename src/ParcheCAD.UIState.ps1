# F8: estado de informe para WinForms, funciones puras y sin mutaciones.
Set-StrictMode -Version 2.0

function Get-PCADReportField {
    [CmdletBinding()]
    param($Object,[Parameter(Mandatory=$true)][string]$Name)
    if($null -eq $Object){return $null}
    if($Object -is [System.Collections.IDictionary]){
        if($Object.Contains($Name)){return $Object[$Name]}
        return $null
    }
    $property=$Object.PSObject.Properties[$Name]
    if($null -eq $property){return $null}
    return $property.Value
}

function Get-PCADReportRows {
    [CmdletBinding()]
    param($Object,[Parameter(Mandatory=$true)][string]$Name)
    $value=Get-PCADReportField -Object $Object -Name $Name
    foreach($item in @($value)) {if($null -ne $item){Write-Output $item}}
}

function Get-PCADReportUiState {
    [CmdletBinding()]
    param($Report,[AllowNull()][Nullable[int]]$ExitCode=$null)
    $expected=@('Installations','Processes','Services','Catalog','Firewall','Tasks',
                'Historico','Connections','NetworkOverview','PolicyPreview')
    $empty=[pscustomobject]@{
        Complete=$false;CanApply=$false;CanPreview=$false;ChecksOK=$false
        RecoveryOK=$false;PlanOK=$false;ExitCodeOK=$false
        Result='SIN_INFORME';Description='Aun no existe diagnostico valido.'
        Plan=$null;Recovery=$null;Sections=$null;Checks=@()
    }
    if($null -eq $Report){return $empty}

    $result=[string](Get-PCADReportField -Object $Report -Name 'Result')
    $sections=Get-PCADReportField -Object $Report -Name 'Sections'
    $checks=@(Get-PCADReportRows -Object $Report -Name 'Checks')
    $plans=@(Get-PCADReportRows -Object $sections -Name 'PolicyPreview')
    $historic=@(Get-PCADReportRows -Object $sections -Name 'Historico')
    $recovery=if($historic.Count -eq 1){Get-PCADReportField -Object $historic[0] -Name 'Recovery'}else{$null}
    $plan=if($plans.Count -eq 1){$plans[0]}else{$null}

    $stageNames=@($checks | ForEach-Object {[string](Get-PCADReportField -Object $_ -Name 'Section')})
    $allStages=($checks.Count -eq $expected.Count)
    if($allStages){
        foreach($name in $expected){
            if(@($stageNames | Where-Object {$_ -ceq $name}).Count -ne 1) {$allStages=$false;break}
        }
    }
    $checksOK=$allStages
    if($checksOK){
        foreach($c in $checks){
            if([string](Get-PCADReportField -Object $c -Name 'Status') -cne 'OK'){$checksOK=$false;break}
        }
    }
    $recoveryOK=($null -ne $recovery -and
        [string](Get-PCADReportField -Object $recovery -Name 'Status') -in @('OK','SIN_RESPALDOS') -and
        [int](Get-PCADReportField -Object $recovery -Name 'NeedsReview') -eq 0 -and
        [int](Get-PCADReportField -Object $recovery -Name 'Unverified') -eq 0)

    $planOK=($null -ne $plan -and
        [string](Get-PCADReportField -Object $plan -Name 'State') -ceq 'PLAN_NO_APLICADO' -and
        [int](Get-PCADReportField -Object $plan -Name 'Count') -gt 0 -and
        [int](Get-PCADReportField -Object $plan -Name 'Conflicts') -eq 0)
    $schemaOK=([string](Get-PCADReportField -Object $Report -Name 'Tool') -ceq 'ParcheCAD' -and
        [int](Get-PCADReportField -Object $Report -Name 'SchemaVersion') -eq 1 -and
        (Get-PCADReportField -Object $Report -Name 'ReadOnly') -eq $true)
    $exitOK=($null -ne $ExitCode -and [int]$ExitCode -eq 0)
    $complete=($exitOK -and $schemaOK -and $checksOK -and $recoveryOK -and
        $result -ceq 'DIAGNOSTICO_COMPLETADO_SIN_CAMBIOS')

    return [pscustomobject]@{
        Complete=$complete;CanApply=($complete -and $recoveryOK -and $planOK)
        CanPreview=($null -ne $plan);ChecksOK=$checksOK;RecoveryOK=$recoveryOK
        PlanOK=$planOK;ExitCodeOK=$exitOK;Result=$result
        Description=if($complete){'DIAGNOSTICO COMPLETO (sin cambios)'}else{'DIAGNOSTICO PARCIAL O INVALIDO: revisar errores'}
        Plan=$plan;Recovery=$recovery;Sections=$sections;Checks=$checks
    }
}

# V4.1: descripcion humana del gate; CanApply permanece sin modificaciones.
function Get-PCADApplyBlockReason {
    [CmdletBinding()]
    param($Ui,[switch]$Busy)
    if($Busy){return 'Aplicar no disponible: consulta u operacion en curso.'}
    if($null -eq $Ui -or !$Ui.Complete){
        return 'Aplicar no disponible: diagnostico incompleto o sin resultado valido.'
    }
    if(!$Ui.RecoveryOK){return 'Aplicar no disponible: recuperacion de reglas pendiente de verificar.'}
    if($null -eq $Ui.Plan){return 'Aplicar no disponible: sin vista previa de reglas.'}
    if([int](Get-PCADReportField -Object $Ui.Plan -Name 'Conflicts') -gt 0){
        return 'Aplicar no disponible: existen conflictos entre reglas.'
    }
    $count=[int](Get-PCADReportField -Object $Ui.Plan -Name 'Count')
    if($count -le 0){return 'Aplicar no disponible: no hay ejecutables candidatos. Comprueba el catalogo.'}
    if(!$Ui.CanApply){return 'Aplicar no disponible: plan de reglas no verificable.'}
    return ('Listo: {0} reglas candidatas. Requiere UAC y confirmacion escrita.' -f $count)
}
