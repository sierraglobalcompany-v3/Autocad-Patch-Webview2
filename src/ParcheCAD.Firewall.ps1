# F4 - ejecucion de reglas ParcheCAD propias, respaldo y reversibilidad.
# NUNCA modifica WebView2 global, servicios, GPO, tareas, licencias o registro.
Set-StrictMode -Version 2.0

function Test-PCADAdministrator {
    try {
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
        $principal=New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {return $false}
}
function Assert-PCADManagedEntry {
    param($Entry,[switch]$AllowMissingFile)
    if($null -eq $Entry){throw 'Falta entrada de regla.'}
    $program=Get-PCADCanonicalProgram -Path ([string]$Entry.Program)
    $year=[int]$Entry.Year
    $installRoot=Get-PCADProperty -Object $Entry -Name 'InstallationRoot'
    $program=Assert-PCADProgramInstallRoot -Program $program -Year $year -InstallRoot $installRoot -AllowMissing:$AllowMissingFile
    if([string]$Entry.RuleName -cne (Get-PCADRuleName -Program $program)) {throw 'ID de regla no corresponde al programa.'}
    if([string]$Entry.Group -cne 'PCAD4_MANAGED' -or [string]$Entry.Direction -cne 'Outbound' -or
        [string]$Entry.Action -cne 'Block' -or [string]$Entry.Profile -cne 'Any') {
        throw 'Parametros de regla fuera de politica.'
    }
    if(!$AllowMissingFile -or (Test-Path -LiteralPath $program -PathType Leaf)) {
        if(!(Test-Path -LiteralPath $program -PathType Leaf)) {throw 'Archivo de AutoCAD no existe.'}
        $file=Get-Item -LiteralPath $program -Force -ErrorAction Stop
        if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {throw 'No se aceptan ejecutables enlace.'}
    }
    if([IO.Path]::GetFileName($program) -ieq 'msedgewebview2.exe') {throw 'El runtime WebView2 compartido no es elegible.'}
    return $program
}
function Write-PCADJournal {
    [CmdletBinding()]
    param($Journal,[string]$File)
    $parent=Split-Path -Parent $File
    if(!(Test-Path -LiteralPath $parent -PathType Container)){throw 'Directorio de respaldo inexistente.'}
    $utf8=New-Object Text.UTF8Encoding($false)
    $tmp=$File+'.pending'
    [IO.File]::WriteAllText($tmp,($Journal|ConvertTo-Json -Depth 8),$utf8)
    if(Test-Path -LiteralPath $File -PathType Leaf) {
        [IO.File]::Replace($tmp,$File,($File+'.prev'))
    } else {
        [IO.File]::Move($tmp,$File)
    }
}
function Invoke-PCADRollbackRules {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$JournalPath,[switch]$Commit)
    if(!$Commit){throw 'Reversion requiere confirmacion explicita -Commit.'}
    if(!(Test-PCADAdministrator)){throw 'Reversion requiere administrador.'}
    if(!(Test-Path -LiteralPath $JournalPath -PathType Leaf)){throw 'No existe manifest de operacion.'}
    $journal=Get-Content -LiteralPath $JournalPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if([string]$journal.Schema -cne 'PCAD4_OPERATION_1'){throw 'Manifest no compatible.'}
    $results=New-Object System.Collections.ArrayList
    $count=0
    foreach($entry in @($journal.Operations)){
        if([string]$entry.State -notin @('CREATING','CREATED','ROLLBACK_ERROR')){continue}
        try{
            # Revertir tambien despues de desinstalar AutoCAD: la regla puede quedar huerfana.
            $null=Assert-PCADManagedEntry -Entry $entry -AllowMissingFile
            $before=Get-PCADActualRuleStatus -RuleName ([string]$entry.RuleName) -Program ([string]$entry.Program)
            if($before.State -eq 'EXISTS_VALID') {
                Remove-NetFirewallRule -Name ([string]$entry.RuleName) -PolicyStore PersistentStore -ErrorAction Stop
                $stage='POST_VERIFY'
            $after=Get-PCADActualRuleStatus -RuleName ([string]$entry.RuleName) -Program ([string]$entry.Program)
                if($after.State -ne 'MISSING'){throw 'Regla sigue presente luego de la eliminacion.'}
            } elseif($before.State -ne 'MISSING'){throw 'Regla modificada/ajena. No retirar.'}
            $entry.State='ROLLED_BACK';$count++
            [void]$results.Add("Rollback OK: $($entry.RuleName)")
        }catch{
            $entry.State='ROLLBACK_ERROR'
            [void]$results.Add(("Rollback ERROR: {0} / {1} / {2}" -f $entry.RuleName,$_.Exception.GetType().Name,(Protect-PCADPath -Path $_.Exception.Message)))
        }
        Write-PCADJournal -Journal $journal -File $JournalPath
    }
    $remaining=@($journal.Operations|Where-Object {$_.State -in @('CREATING','CREATED','ROLLBACK_ERROR')}).Count
    $journal.Status=if($remaining){'PARTIAL_ROLLBACK'}else{'ROLLED_BACK'}
    $journal.FinishedAt=(Get-Date).ToString('o')
    Write-PCADJournal -Journal $journal -File $JournalPath
    return [pscustomobject]@{Status=$journal.Status;Removed=$count;Remaining=$remaining;Messages=@($results.ToArray());Manifest=$JournalPath}
}
function Invoke-PCADApplyPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Plan,
        [Parameter(Mandatory=$true)][string]$BackupDirectory,
        [switch]$Commit
    )
    if(!$Commit){throw 'Aplicar requiere confirmacion explicita -Commit.'}
    if(!(Test-PCADAdministrator)){throw 'Aplicar requiere administrador.'}
    if([string]$Plan.State -ne 'PLAN_NO_APLICADO' -or [int]$Plan.Conflicts -ne 0){throw 'El plan tiene conflictos o no fue aprobado.'}
    $entries=@($Plan.Entries)
    if($entries.Count -lt 1 -or $entries.Count -gt 900){throw 'Plan vacio o excesivo.'}
    if(!(Test-Path -LiteralPath $BackupDirectory -PathType Container)) {
        $null=New-Item -ItemType Directory -Path $BackupDirectory -Force -ErrorAction Stop
    }
    $journal=[pscustomobject]@{
        Schema='PCAD4_OPERATION_1';OperationId=[guid]::NewGuid().ToString('N')
        CreatedAt=(Get-Date).ToString('o');FinishedAt='';Status='PREPARED'
        Operations=@();Notes='Contiene rutas locales; no publicar este archivo en GitHub.'
    }
    $journalPath=Join-Path $BackupDirectory ('PCAD4_'+$journal.OperationId+'.json')
    $seen=@{}
    foreach($e in $entries){
        $path=Assert-PCADManagedEntry -Entry $e
        if($seen.ContainsKey([string]$e.RuleName)){throw 'Plan contiene reglas repetidas.'}
        $seen[[string]$e.RuleName]=$true
        $status=Get-PCADActualRuleStatus -RuleName ([string]$e.RuleName) -Program $path
        if($status.State -eq 'CONFLICT'){throw ('Conflicto previo: '+[string]$e.RuleName)}
        $journal.Operations+= [pscustomobject]@{
            RuleName=[string]$e.RuleName;Group='PCAD4_MANAGED';Program=$path;Year=[int]$e.Year
            InstallationRoot=(Get-PCADProperty -Object $e -Name 'InstallationRoot')
            Direction='Outbound';Action='Block';Profile='Any'
            DisplayName=[string]$e.DisplayName
            State=if($status.State -eq 'EXISTS_VALID'){'ALREADY_PRESENT'}else{'PENDING'}
        }
    }
    Write-PCADJournal -Journal $journal -File $journalPath
    $created=0
    $stage='APPLY_START'
    try {
        foreach($e in @($journal.Operations)){
            if($e.State -ne 'PENDING'){continue}
            $state=Get-PCADActualRuleStatus -RuleName $e.RuleName -Program $e.Program
            if($state.State -ne 'MISSING'){throw ('Regla cambio antes de aplicar: '+$e.RuleName)}
            $e.State='CREATING'
            Write-PCADJournal -Journal $journal -File $journalPath
            $stage='PRE_RULE_PATH_RECHECK'
            $null=Assert-PCADManagedEntry -Entry $e
            $stage='NEW_NETFIREWALL_RULE'
            New-NetFirewallRule -Name $e.RuleName -DisplayName $e.DisplayName -Group 'PCAD4_MANAGED' -Direction Outbound -Action Block -Program $e.Program -Enabled True -Profile Any -PolicyStore PersistentStore -ErrorAction Stop | Out-Null
            # Registrar incluso si la validacion posterior falla, para poder revertir.
            $stage='JOURNAL_CREATED'
            $e.State='CREATED'
            Write-PCADJournal -Journal $journal -File $journalPath
            $after=Get-PCADActualRuleStatus -RuleName $e.RuleName -Program $e.Program
            if($after.State -ne 'EXISTS_VALID'){throw ('No se pudo verificar regla creada: '+$e.RuleName)}
            $created++
            Write-Progress -Activity 'ParcheCAD - aplicando reglas propias' -Status $e.RuleName -PercentComplete ([int](100*$created/$entries.Count))
        }
        $journal.Status='APPLIED'
        $journal.FinishedAt=(Get-Date).ToString('o')
        Write-PCADJournal -Journal $journal -File $journalPath
        return [pscustomobject]@{Status='APPLIED';Created=$created;Manifest=$journalPath;TrafficVerified=$false}
    }catch {
        $reason=$_.Exception.Message
        $journal.Status='ERROR_PARTIAL'
        Write-PCADJournal -Journal $journal -File $journalPath
        $rollback=$null
        try{$rollback=Invoke-PCADRollbackRules -JournalPath $journalPath -Commit}catch{}
        return [pscustomobject]@{
            Status=if($null -ne $rollback -and $rollback.Remaining -eq 0){'ERROR_ROLLED_BACK'}else{'ERROR_MANUAL_REVIEW'}
            Error=$reason;ErrorStage=$stage;Manifest=$journalPath;Recovery=$rollback;TrafficVerified=$false
        }
    } finally {Write-Progress -Activity 'ParcheCAD - aplicando reglas propias' -Completed}
}
