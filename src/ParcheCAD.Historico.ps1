# ParcheCAD F2: analiza reglas heredadas SIN eliminarlas o cambiarlas.
Set-StrictMode -Version 2.0
function Get-PCADLegacyAssessment {
    [CmdletBinding()]
    param(
        [string]$Name='',[string]$DisplayName='',[string]$Program='',
        [string]$Action='',[string]$Direction='',[string]$Enabled=''
    )
    $kind=Get-PCADLegacyKind -Name $Name -DisplayName $DisplayName
    $class='AJENA_O_DESCONOCIDA';$confidence='BAJA'
    $web=[bool]($Program -match '(?i)(?:^|[\\/])msedgewebview2\.exe$')
    $autodesk=[bool]($Program -match '(?i)[\\/]Autodesk[\\/]|\bAutoCAD 202[3-7][\\/]')
    $active=($Action -eq 'Block' -and $Enabled -match '^(True|1)$')
    if($web){
        $class='WEBVIEW2_COMPARTIDO'
    } elseif($autodesk) {
        if($Program -match '(?i)[\\/]Autodesk[\\/]AutoCAD 202[3-7][\\/]'){
            $class='AUTOCAD_PRODUCTO'
        } else {$class='AUTODESK_COMPARTIDO'}
    }
    if($kind -ne 'AJENO_O_DESCONOCIDO' -and $class -ne 'AJENA_O_DESCONOCIDA'){
        $confidence='MEDIA'
    }
    $outcome='SOLO_INFORMAR'
    if($web -and $active) {$outcome='ALERTA_WEBVIEW2_COMPARTIDO'}
    elseif($active -and $class -eq 'AUTOCAD_PRODUCTO') {$outcome='BLOQUEO_PRODUCTO_DETECTADO'}
    elseif($active -and $class -eq 'AUTODESK_COMPARTIDO') {$outcome='REVISAR_COMPONENTE_COMPARTIDO'}
    return [pscustomobject]@{
        Category=$class;Family=$kind;Confidence=$confidence
        ActiveBlock=$active;Direction=$Direction
        Assessment=$outcome;Ownership='NO_CONFIRMADA'
        MayDelete=$false;Rationale='Nombre no demuestra propiedad; filtro de programa obligatorio'
    }
}
function Get-PCADRecoveryOverview {
    [CmdletBinding()]
    param([string]$JournalDirectory='')
    $active=0;$review=0;$invalid=0;$valid=0;$truncated=$false
    if(!$JournalDirectory){
        return [pscustomobject]@{Status='NO_CONSULTADO';Valid=$valid;ActiveRules=$active;NeedsReview=$review;Unverified=$invalid}
    }
    if(!(Test-Path -LiteralPath $JournalDirectory -PathType Container)){
        return [pscustomobject]@{Status='SIN_RESPALDOS';Valid=0;ActiveRules=0;NeedsReview=0;Unverified=0}
    }
    try {
        $files=@(Get-ChildItem -LiteralPath $JournalDirectory -File -Filter 'PCAD4_*.json' -ErrorAction Stop | Select-Object -First 501)
        if($files.Count -gt 500){$files=@($files | Select-Object -First 500);$truncated=$true}
        foreach($file in $files){
            try {
                $j=Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if([string]$j.Schema -cne 'PCAD4_OPERATION_1'){throw 'Formato de respaldo desconocido'}
                $valid++
                $created=@($j.Operations|Where-Object {$_.State -eq 'CREATED'}).Count
                if([string]$j.Status -eq 'APPLIED'){$active+=$created}
                if([string]$j.Status -in @('PREPARED','ERROR_PARTIAL','PARTIAL_ROLLBACK') -or
                    @($j.Operations|Where-Object {$_.State -in @('CREATING','ROLLBACK_ERROR')}).Count -gt 0){
                    $review++
                }
            }catch {$invalid++}
        }
        $state=if($invalid -gt 0 -or $truncated){'PARCIAL'}else{'OK'}
        return [pscustomobject]@{
            Status=$state;Valid=$valid;ActiveRules=$active
            NeedsReview=$review;Unverified=$invalid
        }
    }catch {
        return [pscustomobject]@{
            Status='ERROR_ACCESO';Valid=0;ActiveRules=0
            NeedsReview=0;Unverified=1
        }
    }
}
function Get-PCADLegacyOverview {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Firewall=@(),[AllowEmptyCollection()][object[]]$Tasks=@(),[string]$JournalDirectory='')
    $rows=New-Object System.Collections.ArrayList
    $warn=New-Object System.Collections.ArrayList
    $activeWeb=0;$activeAutodesk=0;$foreign=0
    foreach($r in @($Firewall)){
        if($null -eq $r){continue}
        $a=Get-PCADLegacyAssessment -Name ([string]$r.Name) -DisplayName ([string]$r.DisplayName) -Program ([string]$r.Program) -Action ([string]$r.Action) -Enabled ([string]$r.Enabled) -Direction ([string]$r.Direction)
        if($a.ActiveBlock -and $a.Category -eq 'WEBVIEW2_COMPARTIDO') {$activeWeb++}
        if($a.ActiveBlock -and $a.Category -match '^AUTO') {$activeAutodesk++}
        if($a.Family -eq 'AJENO_O_DESCONOCIDO'){$foreign++}
        [void]$rows.Add([pscustomobject]@{
            Name=[string]$r.Name;Program=[string]$r.Program
            Family=$a.Family;Category=$a.Category
            ActiveBlock=$a.ActiveBlock;Direction=$a.Direction
            Assessment=$a.Assessment;Ownership=$a.Ownership
            CanRemoveAutomatically=$false
        })
    }
    if($activeWeb -gt 0){[void]$warn.Add("ATENCION: $activeWeb regla(s) activas de WebView2 compartido; pueden afectar aplicaciones ajenas")}
    $suspicious=@($Tasks | Where-Object {$_.Name -match '(?i)Autodesk Block WebView2|WebView2 Global Block|ParcheCAD'})
    if($suspicious.Count -gt 0){[void]$warn.Add(("{0} tareas con nombres historicos detectadas; NO fueron modificadas" -f $suspicious.Count))}
    $recovery=Get-PCADRecoveryOverview -JournalDirectory $JournalDirectory
    if($recovery.NeedsReview -gt 0 -or $recovery.Status -in @('PARCIAL','ERROR_ACCESO')){
        [void]$warn.Add(('Respaldo: {0} operacion(es) para revisar; lectura {1}' -f $recovery.NeedsReview,$recovery.Status))
    }
    return [pscustomobject]@{
        Recovery=$recovery
        AutoCADAndAutodeskActiveRules=$activeAutodesk
        WebView2ActiveRules=$activeWeb
        UnattributedOrForeignRules=$foreign
        SuspectedTasks=$suspicious.Count
        Items=@($rows.ToArray())
        Warnings=@($warn.ToArray())
        RecoveryPolicy='NO MODIFICAR en F2; copia y verificacion antes de cualquier accion'
    }
}
