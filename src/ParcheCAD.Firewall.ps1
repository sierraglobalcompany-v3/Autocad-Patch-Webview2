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


# Recuperacion tras borrar la carpeta ParcheCAD: identifica SOLO reglas con
# firma estructural PCAD4 exacta que persiste en Windows Firewall.
# El nombre, grupo y display no son una prueba criptografica de origen.
function Get-PCADRecoverableRules {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$FirewallRules=@(),[switch]$ProvidedRules)
    if(!$ProvidedRules){
        # La enumeracion y todos los filtros deben completarse: error = FAIL CLOSED.
        $FirewallRules=@(Get-NetFirewallRule -PolicyStore PersistentStore -ErrorAction Stop)
    }
    $candidates=New-Object System.Collections.ArrayList
    $warnings=New-Object System.Collections.ArrayList
    $review=New-Object System.Collections.ArrayList
    $matched=0
    foreach($rule in @($FirewallRules)){
        if($null -eq $rule){continue}
        $name=[string]$rule.Name
        $group=[string]$rule.Group
        $display=[string]$rule.DisplayName
        $looksManaged=($name -match '^PCAD4_A_[0-9a-fA-F]{24}_OUT$' -or $group -ceq 'PCAD4_MANAGED')
        $looksWeb=($name+' '+$display+' '+$group) -match '(?i)webview2|msedgewebview2'
        $looksCad=($name+' '+$display+' '+$group) -match '(?i)AutoCAD|Autodesk|SGC_AUTODESK'
        if(!$looksManaged -and !$looksWeb -and !$looksCad){continue}
        if(!$looksManaged){
            [void]$review.Add([pscustomobject]@{RuleName=$name;Reason='REGLA_HISTORICA_O_AJENA_SIN_ID_PC4';Removable=$false})
            continue
        }
        $matched++
        if($matched -gt 900){throw 'Demasiadas reglas con firma ParcheCAD: revision manual obligatoria.'}
        try{
            if($name -cnotmatch '^PCAD4_A_[0-9A-F]{24}_OUT$' -or $group -cne 'PCAD4_MANAGED'){
                throw 'Firma de nombre/grupo incompleta.'
            }
            $m=[regex]::Match($display,'^ParcheCAD 4\.0 - AutoCAD (202[3-7]) - ([^\\/]+\.exe)$',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if(!$m.Success){throw 'DisplayName historico no reconocido.'}
            $year=[int]$m.Groups[1].Value
            $programFilter=@($rule | Get-NetFirewallApplicationFilter -ErrorAction Stop)
            if($programFilter.Count -ne 1){throw 'Filtro de programa no unico.'}
            $path=Get-PCADCanonicalProgram -Path ([string]$programFilter[0].Program)
            if([IO.Path]::GetFileName($path) -ine $m.Groups[2].Value -or
                [IO.Path]::GetFileName($path) -ieq 'msedgewebview2.exe'){
                throw 'Programa no corresponde a la identidad AutoCAD.'
            }
            # En recuperacion SIN journal solo se consideran instalaciones con
            # segmento explicito AutoCAD YYYY. Custom roots requieren manifest.
            $null=Assert-PCADProgramInstallRoot -Program $path -Year $year -InstallRoot '' -AllowMissing
            if($name -cne (Get-PCADRuleName -Program $path)){
                throw 'Hash del nombre no corresponde a programa.'
            }
            $status=Get-PCADActualRuleStatus -RuleName $name -Program $path
            if($status.State -cne 'EXISTS_VALID'){throw ('Estado de filtros: '+$status.State)}
            [void]$candidates.Add([pscustomobject]@{
                RuleName=$name;Program=$path;Year=$year
                Group='PCAD4_MANAGED';DisplayName=$display
                Removable=$true;Identification='FIRMA_ESTRUCTURAL_COMPATIBLE_NO_CRIPTOGRAFICA'
            })
        }catch{
            # Una regla alterada, desconocida o ambigua NUNCA entra en la lista.
            [void]$review.Add([pscustomobject]@{RuleName=$name;Reason='IDENTIDAD_NO_VERIFICADA';Removable=$false})
            [void]$warnings.Add('Regla de posible ParcheCAD no verificable; requiere revision manual.')
        }
    }
    return [pscustomobject]@{
        Status='SCAN_COMPLETO';ReadOnly=$true
        Candidates=@($candidates.ToArray())
        NeedsReview=@($review.ToArray())
        Warnings=@($warnings.ToArray())
        VerifiedCount=$candidates.Count
        UnverifiedCount=$review.Count
        Ownership='FIRMA_COMPATIBLE; NO PRUEBA CRIPTOGRAFICA'
        WebViewGlobalRemovalAllowed=$false
    }
}
function Invoke-PCADRecoverWithoutJournal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RecoveryDirectory,
        [AllowEmptyCollection()][string[]]$RuleNames=@(),
        [switch]$Commit
    )
    if(!$Commit){throw 'Recuperacion sin manifest requiere confirmacion explicita.'}
    if(!(Test-PCADAdministrator)){throw 'Recuperacion requiere administrador.'}
    $scan=Get-PCADRecoverableRules
    if($scan.Status -cne 'SCAN_COMPLETO'){throw 'Inventario incompleto, no recuperar.'}
    $eligible=@($scan.Candidates)
    if($RuleNames.Count -gt 0){
        $wanted=@{}
        foreach($name in $RuleNames){$wanted[$name]=$true}
        $eligible=@($eligible|Where-Object {$wanted.ContainsKey([string]$_.RuleName)})
        if($eligible.Count -ne $wanted.Count){throw 'Alguna regla elegida no existe o no es elegible.'}
    }
    if(!$eligible.Count){
        return [pscustomobject]@{Status='NO_CANDIDATES';Removed=0;Remaining=0;Review=$scan.UnverifiedCount}
    }
    if($eligible.Count -gt 900){throw 'Demasiadas reglas; no modificar.'}
    if(!(Test-Path -LiteralPath $RecoveryDirectory -PathType Container)){
        $null=New-Item -ItemType Directory -Path $RecoveryDirectory -Force -ErrorAction Stop
    }
    $id=[guid]::NewGuid().ToString('N')
    $journalPath=Join-Path $RecoveryDirectory ('RECOVERY_'+$id+'.json')
    # El informe de recuperacion se guarda FUERA del programa, en ProgramData
    # (salvo el directorio de QA elegido explicitamente).
    $journal=[pscustomobject]@{
        Schema='PCAD4_JOURNAL_FREE_RECOVERY_1';Id=$id
        CreatedAt=(Get-Date).ToString('o');FinishedAt='';Status='PREPARED';PolicyBackup=''
        Notes='Snapshot previo a retirar reglas de firma estructural ParcheCAD; no prueba autoria criptografica.'
        Operations=@($eligible|ForEach-Object{
            [pscustomobject]@{RuleName=$_.RuleName;Program=$_.Program;Year=$_.Year
                DisplayName=$_.DisplayName;State='PENDING';Group=$_.Group}
        })
    }
    Write-PCADJournal -Journal $journal -File $journalPath
    $journal.PolicyBackup=Save-PCADPolicySnapshot -RecoveryDirectory $RecoveryDirectory
    Write-PCADJournal -Journal $journal -File $journalPath
    $removed=0
    foreach($entry in @($journal.Operations)){
        try{
            # Reescanea antes de cada operacion para evitar cambios entre clicks.
            $existing=@(Get-NetFirewallRule -Name $entry.RuleName -PolicyStore PersistentStore -ErrorAction Stop)
            if($existing.Count -ne 1 -or [string]$existing[0].Group -cne 'PCAD4_MANAGED' -or
               [string]$existing[0].DisplayName -cne [string]$entry.DisplayName -or
               [string]$entry.RuleName -cne (Get-PCADRuleName -Program $entry.Program)){
                throw 'Identidad de regla ha cambiado; no borrar.'
            }
            $status=Get-PCADActualRuleStatus -RuleName $entry.RuleName -Program $entry.Program
            if($status.State -cne 'EXISTS_VALID'){throw 'Filtros cambiados; no borrar.'}
            $entry.State='REMOVING'
            Write-PCADJournal -Journal $journal -File $journalPath
            Remove-NetFirewallRule -Name $entry.RuleName -PolicyStore PersistentStore -ErrorAction Stop
            $after=Get-PCADActualRuleStatus -RuleName $entry.RuleName -Program $entry.Program
            if($after.State -cne 'MISSING'){throw 'Regla persiste tras recuperacion.'}
            $entry.State='REMOVED'
            $removed++
        }catch{
            $entry.State='REVIEW_REQUIRED'
            $journal.Status='PARTIAL'
        }
        Write-PCADJournal -Journal $journal -File $journalPath
    }
    $remaining=@($journal.Operations|Where-Object {$_.State -ne 'REMOVED'}).Count
    $journal.Status=if($remaining){'PARTIAL'}else{'RECOVERED'}
    $journal.FinishedAt=(Get-Date).ToString('o')
    Write-PCADJournal -Journal $journal -File $journalPath
    return [pscustomobject]@{
        Status=$journal.Status;Removed=$removed;Remaining=$remaining
        Review=$scan.UnverifiedCount;Journal=$journalPath
        TrafficVerified=$false
    }
}


# Copia independiente del folder de la app, previa a TODA restauracion sin manifest.
# La exportacion .wfw es para soporte/recuperacion; NO importar automaticamente
# porque eso reemplazaria el conjunto completo de reglas del equipo.
function Save-PCADPolicySnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RecoveryDirectory)
    if(!(Test-PCADAdministrator)){throw 'Exportar politica de firewall requiere administrador.'}
    if(!(Test-Path -LiteralPath $RecoveryDirectory -PathType Container)){
        $null=New-Item -ItemType Directory -Path $RecoveryDirectory -Force -ErrorAction Stop
    }
    $dest=Join-Path $RecoveryDirectory ('PolicyBeforeRestore_'+[guid]::NewGuid().ToString('N')+'.wfw')
    $exe=Join-Path $env:WINDIR 'System32\netsh.exe'
    if(!(Test-Path -LiteralPath $exe -PathType Leaf)){throw 'No se encontro netsh de Windows.'}
    & $exe advfirewall export $dest | Out-Null
    if($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $dest -PathType Leaf) -or
       (Get-Item -LiteralPath $dest -ErrorAction Stop).Length -lt 1024){
        throw 'No se creo la copia de la politica completa; no se restaurara ninguna regla.'
    }
    return $dest
}

# Una sola fuente para localizar reglas de bloqueo por ejecutable, aunque el
# usuario haya eliminado ParcheCAD. Solo se inspecciona PersistentStore local.
function Get-PCADTargetedBlockRules {
    [CmdletBinding()]
    param([ValidateSet('AutoCAD','WebView2')][string]$Kind)
    $found=New-Object System.Collections.ArrayList
    $seen=@{}
    $filters=@(Get-NetFirewallApplicationFilter -PolicyStore PersistentStore -All -ErrorAction Stop)
    if($filters.Count -gt 35000){throw 'Inventario de firewall excesivo; no decidir restauracion.'}
    foreach($filter in $filters){
        $program=[string]$filter.Program
        if([string]::IsNullOrWhiteSpace($program)){continue}
        $isTarget=if($Kind -eq 'WebView2'){
            ($program -match '(?i)(?:^|[\\/])msedgewebview2\.exe$')
        }else{
            ($program -match '(?i)[\\/]AutoCAD 202[3-7][\\/].+\.exe$' -and
             $program -notmatch '(?i)msedgewebview2\.exe$')
        }
        if(!$isTarget){continue}
        $rules=@(Get-NetFirewallRule -AssociatedNetFirewallApplicationFilter $filter -PolicyStore PersistentStore -ErrorAction Stop)
        foreach($rule in $rules){
            $key=[string]$rule.Name
            if(!$key -or $seen.ContainsKey($key)){continue}
            $seen[$key]=$true
            $block=([string]$rule.Action -eq 'Block' -and [string]$rule.Enabled -eq 'True')
            [void]$found.Add([pscustomobject]@{
                RuleName=$key
                Program=$program
                DisplayName=[string]$rule.DisplayName
                Group=[string]$rule.Group
                Direction=[string]$rule.Direction
                IsBlocking=$block
                Kind=$Kind
                Ownership=if([string]$rule.Group -ceq 'PCAD4_MANAGED'){'POSIBLE_PCAD4'}else{'NO_VERIFICADA'}
            })
        }
    }
    return @($found.ToArray() | Sort-Object RuleName)
}

# Regla ajena/historica SOLO con seleccion exacta y confirmacion por el usuario.
# No hace rollback a ciegas ni toca perfiles/GPO, antivirus, procesos o servicios.
function Invoke-PCADRestoreSelectedRule {
    [CmdletBinding()]
    param(
        [ValidateSet('AutoCAD','WebView2')][string]$Kind,
        [Parameter(Mandatory=$true)][string]$RuleName,
        [Parameter(Mandatory=$true)][string]$RecoveryDirectory,
        [switch]$Commit
    )
    if(!$Commit -or !(Test-PCADAdministrator)){throw 'Restauracion requiere consentimiento y administrador.'}
    $rules=@(Get-PCADTargetedBlockRules -Kind $Kind | Where-Object {$_.RuleName -ceq $RuleName -and $_.IsBlocking})
    if($rules.Count -ne 1){throw 'La regla ya no existe, no bloquea o su identidad es ambigua.'}
    $target=$rules[0]
    $original=@(Get-NetFirewallRule -Name $RuleName -PolicyStore PersistentStore -ErrorAction Stop)
    if($original.Count -ne 1 -or [string]$original[0].Action -cne 'Block' -or
       [string]$original[0].Enabled -cne 'True' -or
       [string]$original[0].Group -cne $target.Group -or
       [string]$original[0].DisplayName -cne $target.DisplayName){
        throw 'Estado cambio al intentar restaurar. No se ha borrado.'
    }
    $programFilters=@($original[0] | Get-NetFirewallApplicationFilter -ErrorAction Stop)
    if($programFilters.Count -ne 1 -or [string]$programFilters[0].Program -ine $target.Program){
        throw 'Filtro de programa cambio. No se ha borrado.'
    }
    $policyBackup=Save-PCADPolicySnapshot -RecoveryDirectory $RecoveryDirectory
    $journalPath=Join-Path $RecoveryDirectory ('SelectedRestore_'+[guid]::NewGuid().ToString('N')+'.json')
    $journal=[pscustomobject]@{
        Schema='PCAD4_SELECTED_RESTORE_1';CreatedAt=(Get-Date).ToString('o');FinishedAt=''
        Status='PREPARED';Kind=$Kind;RuleName=$RuleName;Program=$target.Program
        PolicyBackup=$policyBackup;Error=''
        Note='Regla seleccionada expresamente. Posible procedencia externa, autoria no verificada.'
    }
    Write-PCADJournal -Journal $journal -File $journalPath
    try{
        # Ultima consulta antes de borrar.
        $now=@(Get-PCADTargetedBlockRules -Kind $Kind | Where-Object {
            $_.RuleName -ceq $RuleName -and $_.Program -ieq $target.Program -and
            $_.DisplayName -ceq $target.DisplayName -and $_.IsBlocking
        })
        if($now.Count -ne 1){throw 'Regla cambio entre revision y confirmacion.'}
        $journal.Status='REMOVING'
        Write-PCADJournal -Journal $journal -File $journalPath
        Remove-NetFirewallRule -Name $RuleName -PolicyStore PersistentStore -ErrorAction Stop
        if(@(Get-NetFirewallRule -Name $RuleName -PolicyStore PersistentStore -ErrorAction SilentlyContinue).Count -ne 0){
            throw 'La regla sigue presente tras intentar retirarla.'
        }
        $journal.Status='RESTORED'
    }catch{
        $journal.Status='REVIEW_REQUIRED'
        $journal.Error=$_.Exception.GetType().Name
    }
    $journal.FinishedAt=(Get-Date).ToString('o')
    Write-PCADJournal -Journal $journal -File $journalPath
    return [pscustomobject]@{
        Status=$journal.Status;RuleName=$RuleName
        Removed=($journal.Status -eq 'RESTORED');Journal=$journalPath
        PolicyBackup=$policyBackup;TrafficVerified=$false
    }
}
