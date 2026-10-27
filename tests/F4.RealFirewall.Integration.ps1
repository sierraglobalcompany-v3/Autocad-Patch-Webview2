# F4 real firewall QA only on ephemeral GitHub-hosted Windows runner.
# TESTS ONE TEMPORARY copied OS binary under TEMP; NEVER real AutoCAD or WebView2.
# DO NOT RUN on end-user computers. Requires runner admin; guaranteed cleanup.
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\ParcheCAD.Core.ps1')
. (Join-Path $root 'src\ParcheCAD.Policy.ps1')
. (Join-Path $root 'src\ParcheCAD.Firewall.ps1')

if($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted'){
    throw 'Requiere una VM efimera GitHub-hosted; prohibido en maquinas de usuario o self-hosted.'
}
if(!(Test-PCADAdministrator)){throw 'El runner no tiene permiso administrador; QA real BLOCKED.'}
$testDir=Join-Path ([IO.Path]::GetTempPath()) ('pcad4-firewall-qa-'+[Guid]::NewGuid().ToString('N'))
$product=Join-Path $testDir 'Autodesk\AutoCAD 2023'
$exe=Join-Path $product 'acad.exe'
$manifest=''
$ruleName=''
$webRule=''
$webOtherRule=''
$webExe=''
$hasCleanupError=$false
try {
    $null=New-Item -ItemType Directory -Path $product -Force -ErrorAction Stop
    # Copy only for fixture identity/path; do not start the executable.
    Copy-Item -LiteralPath (Join-Path $env:WINDIR 'System32\whoami.exe') -Destination $exe -ErrorAction Stop
    $ruleName=Get-PCADRuleName -Program $exe
    $before=Get-PCADActualRuleStatus -RuleName $ruleName -Program $exe
    if($before.State -ne 'MISSING'){throw 'TEST INSEGURA: el nombre de regla ya existe; abortando sin cambiar nada.'}
    $plan=New-PCADRulePlan -Catalog @([pscustomobject]@{
        Name='acad.exe';Path=$exe;Year=2023;Classification='AUTOCAD_PRODUCTO';Policy='SOLO_INVENTARIO'
    }) -CheckExisting
    if($plan.Count -ne 1 -or $plan.Conflicts -ne 0 -or $plan.Entries[0].Existing -ne 'MISSING'){
        throw 'No fue posible preparar la unica regla de prueba.'
    }
    $res=Invoke-PCADApplyPlan -Plan $plan -BackupDirectory (Join-Path $testDir 'backups') -Commit
    $manifest=[string]$res.Manifest
    Write-Host ('F4 Integration: {0}' -f ($res | ConvertTo-Json -Depth 8 -Compress))
    if($res.Status -ne 'APPLIED' -or $res.Created -ne 1){throw 'Fallo en aplicacion real.'}
    $verified=Get-PCADActualRuleStatus -RuleName $ruleName -Program $exe
    if($verified.State -ne 'EXISTS_VALID'){throw 'La regla real creada no se pudo verificar.'}
    # F16: a rule may look valid by Name/Program yet restrict the remote IP.
    # Mutate ONLY our temporary fixture and restore it in finally. An
    # altered filter must prevent idempotent acceptance, not be overwritten.
    $myRule=Get-NetFirewallRule -Name $ruleName -PolicyStore PersistentStore -ErrorAction Stop
    $addressFilter=$myRule | Get-NetFirewallAddressFilter -ErrorAction Stop
    try {
        $addressFilter | Set-NetFirewallAddressFilter -RemoteAddress '192.0.2.77' -ErrorAction Stop
        $narrow=Get-PCADActualRuleStatus -RuleName $ruleName -Program $exe
        if($narrow.State -cne 'CONFLICT'){
            throw ('F16: narrowed RemoteAddress incorrectly accepted as '+$narrow.State)
        }
        $driftPlan=New-PCADRulePlan -Catalog @([pscustomobject]@{
            Name='acad.exe';Path=$exe;Year=2023
            Classification='AUTOCAD_PRODUCTO';Policy='SOLO_INVENTARIO'
        }) -CheckExisting
        if($driftPlan.Conflicts -ne 1 -or $driftPlan.State -cne 'CONFLICT'){
            throw 'F16: narrowed rule did not block the preview/apply plan.'
        }
        Write-Host 'F16 PASS: remote-IP-only firewall rule reports CONFLICT (never EXISTS_VALID).' -ForegroundColor Green
    } finally {
        $addressFilter | Set-NetFirewallAddressFilter -RemoteAddress Any -ErrorAction Stop
        if((Get-PCADActualRuleStatus -RuleName $ruleName -Program $exe).State -cne 'EXISTS_VALID'){
            throw 'F16: temporary firewall address scope did not restore to Any.'
        }
    }
    $second=New-PCADRulePlan -Catalog @([pscustomobject]@{
        Name='acad.exe';Path=$exe;Year=2023;Classification='AUTOCAD_PRODUCTO';Policy='SOLO_INVENTARIO'
    }) -CheckExisting
    $repeat=Invoke-PCADApplyPlan -Plan $second -BackupDirectory (Join-Path $testDir 'backups') -Commit
    if($repeat.Status -ne 'APPLIED' -or $repeat.Created -ne 0){throw 'Fallo en idempotencia real.'}
    # Simular desinstalacion del programa antes de revertir.
    Remove-Item -LiteralPath $exe -Force -ErrorAction Stop
    $undo=Invoke-PCADRollbackRules -JournalPath $manifest -Commit
    Write-Host ('F4 Rollback: {0}' -f ($undo | ConvertTo-Json -Depth 7 -Compress))
    if($undo.Status -ne 'ROLLED_BACK' -or $undo.Removed -ne 1){throw 'No se revirtio al quitar el EXE.'}
    $after=Get-PCADActualRuleStatus -RuleName $ruleName -Program $exe
    if($after.State -ne 'MISSING'){throw 'Regla persiste tras rollback.'}
    Write-Host 'PASS REAL: regla temporal saliente creada, identificada, repetida sin duplicar y revertida tras eliminar EXE.' -ForegroundColor Green

    # Sin carpeta ni backup: ID en firewall + filtros bastan para reconocer
    # la regla sintética exacta. El diario nuevo persiste aparte.
    New-NetFirewallRule -Name $ruleName -DisplayName 'ParcheCAD 4.0 - AutoCAD 2023 - acad.exe' -Group 'PCAD4_MANAGED' -Program $exe -Direction Outbound -Action Block -Enabled True -Profile Any -PolicyStore PersistentStore -ErrorAction Stop | Out-Null
    $allOwned=Get-PCADRecoverableRules
    if(@($allOwned.Candidates|Where-Object {$_.RuleName -ceq $ruleName}).Count -ne 1){
        throw 'RECOVERY: regla PCAD4 sin backup no reconocida.'
    }
    $restoreDir=Join-Path $testDir 'persistent-recovery'
    $undoNoBackup=Invoke-PCADRecoverWithoutJournal -RecoveryDirectory $restoreDir -RuleNames @($ruleName) -Commit
    if($undoNoBackup.Status -cne 'RECOVERED' -or $undoNoBackup.Removed -ne 1 -or
       !(Test-Path -LiteralPath $undoNoBackup.Journal -PathType Leaf)){
        throw 'RECOVERY: restauracion AutoCAD sin backup o nuevo journal fallaron.'
    }
    $rec=Get-Content -LiteralPath $undoNoBackup.Journal -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    if(!(Test-Path -LiteralPath $rec.PolicyBackup -PathType Leaf) -or
       (Get-PCADActualRuleStatus -RuleName $ruleName -Program $exe).State -cne 'MISSING'){
        throw 'RECOVERY: no se exporto politica o persistio regla tras restaurar.'
    }

    # WebView2 compartido: regla sintetica con nombre ajeno, pero filtro real
    # de ejecutable msedgewebview2.exe. Solo se elimina tras seleccion exacta.
    $webExe=Join-Path $testDir 'msedgewebview2.exe'
    Copy-Item -LiteralPath (Join-Path $env:WINDIR 'System32\whoami.exe') -Destination $webExe -ErrorAction Stop
    $webRule='SGC_WEBVIEW2_CONTROL_V1_'+[guid]::NewGuid().ToString('N')
    $webOtherRule='PCAD_QA_UNRELATED_WEB_'+[guid]::NewGuid().ToString('N')
    New-NetFirewallRule -Name $webRule -DisplayName 'Autodesk AutoCAD WebView2 - legacy test' -Group 'PCAD_QA_TEST' -Program $webExe -Direction Outbound -Action Block -Enabled True -Profile Any -PolicyStore PersistentStore -ErrorAction Stop|Out-Null
    New-NetFirewallRule -Name $webOtherRule -DisplayName 'WebView2 Global Block - unrelated software' -Group 'PCAD_QA_TEST' -Program $webExe -Direction Outbound -Action Block -Enabled True -Profile Any -PolicyStore PersistentStore -ErrorAction Stop|Out-Null
    $webList=@(Get-PCADTargetedBlockRules -Kind 'WebView2')
    if(@($webList|Where-Object {$_.RuleName -ceq $webRule -and $_.IsBlocking -and $_.AutodeskIntent -ne ''}).Count -ne 1){
        throw 'RESTORE AUTODESK: historic tagged rule not detected by program filter.'
    }
    if(@($webList|Where-Object {$_.RuleName -ceq $webOtherRule}).Count -ne 0){
        throw 'RESTORE AUTODESK: unrelated shared WebView2 block became eligible.'
    }
    $rejected=$false
    try{
        $null=Invoke-PCADRestoreSelectedRule -Kind WebView2 -RuleName $webOtherRule -RecoveryDirectory $restoreDir -Commit
    }catch{$rejected=$true}
    if(!$rejected -or $null -eq (Get-NetFirewallRule -Name $webOtherRule -PolicyStore PersistentStore -ErrorAction Stop)){
        throw 'RESTORE AUTODESK: generic rule wrongly removed or accepted.'
    }
    if((Get-PCADAutodeskWebViewIntent -Name 'SGC_WEBVIEW2_V2_ABCD' -DisplayName 'WebView2 Global Block' -Group '') -ne ''){
        throw 'RESTORE AUTODESK: ambiguous historic SGC marker without Autodesk evidence allowed.'
    }
    $webDone=Invoke-PCADRestoreSelectedRule -Kind WebView2 -RuleName $webRule -RecoveryDirectory $restoreDir -Commit
    if($webDone.Status -cne 'RESTORED' -or !(Test-Path -LiteralPath $webDone.PolicyBackup) -or
       $null -ne (Get-NetFirewallRule -Name $webRule -PolicyStore PersistentStore -ErrorAction SilentlyContinue)){
        throw 'RESTORE AUTODESK: tagged rule not removed after backup.'
    }
    if($null -eq (Get-NetFirewallRule -Name $webOtherRule -PolicyStore PersistentStore -ErrorAction Stop)){
        throw 'RESTORE AUTODESK: generic WebView2 rule was modified.'
    }
    Write-Host 'PASS F4 AUTODESK: recovered historic named rule; generic WebView2 rule retained; backup and safe rejection verified.' -ForegroundColor Green

    # Simula una interrupcion despues de que Windows crea la regla, pero
    # antes de registrar CREATED en el journal. No hay procesos ni AV alterados.
    $manifestCrash=Join-Path (Join-Path $testDir 'backups') ('PCAD4_'+[guid]::NewGuid().ToString('N')+'.json')
    $fixture=[pscustomobject]@{
        Schema='PCAD4_OPERATION_1';OperationId=[guid]::NewGuid().ToString('N')
        CreatedAt=(Get-Date).ToString('o');FinishedAt='';Status='PREPARED'
        Operations=@([pscustomobject]@{
            RuleName=$ruleName;Group='PCAD4_MANAGED';Program=$exe;Year=2023
            InstallationRoot=$product;Direction='Outbound';Action='Block';Profile='Any'
            DisplayName='ParcheCAD 4.0 - AutoCAD 2023 - acad.exe';State='CREATING'
        })
    }
    Write-PCADJournal -Journal $fixture -File $manifestCrash
    New-NetFirewallRule -Name $ruleName -DisplayName 'ParcheCAD 4.0 - AutoCAD 2023 - acad.exe' -Group 'PCAD4_MANAGED' -Program $exe -Direction Outbound -Action Block -Enabled True -Profile Any -PolicyStore PersistentStore -ErrorAction Stop | Out-Null
    if((Get-PCADActualRuleStatus -RuleName $ruleName -Program $exe).State -ne 'EXISTS_VALID'){throw 'No se creo regla temporal del escenario interrumpido.'}
    # The interrupted transaction is recovered by a NEW PowerShell process,
    # importing project modules from GitHub exactly as after relaunching PCAD.
    $child=Join-Path $root 'tests\F10.Recover.Child.ps1'
    $psExe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $psExe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File $child -JournalPath $manifestCrash -ExpectedRule $ruleName -ExpectedProgram $exe
    if($LASTEXITCODE -ne 0){throw 'F10: independent recovery process returned a failure.'}
    $recovered=Get-Content -LiteralPath $manifestCrash -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if([string]$recovered.Status -cne 'ROLLED_BACK' -or [string]$recovered.Operations[0].State -cne 'ROLLED_BACK'){
        throw 'F10: independent process did not persist recovered journal.'
    }
    if((Get-PCADActualRuleStatus -RuleName $ruleName -Program $exe).State -ne 'MISSING'){throw 'Regla permanecio tras recuperacion interrumpida.'}
    # El mismo journal recuperado no debe volver a retirar reglas.
    $again=Invoke-PCADRollbackRules -JournalPath $manifestCrash -Commit
    if($again.Removed -ne 0){throw 'Rollback interrumpido no fue idempotente.'}
    Write-Host 'PASS REAL F10: recuperacion en nuevo proceso tras interrupcion simulada CREATING, sin ejecutable y sin reglas residuales.' -ForegroundColor Green

 } finally {
    foreach($name in @($webRule,$webOtherRule)){
        if(!$name){continue}
        $wr=@(Get-NetFirewallRule -Name $name -PolicyStore PersistentStore -ErrorAction SilentlyContinue)
        if($wr.Count -eq 1 -and [string]$wr[0].Group -ceq 'PCAD_QA_TEST'){
            $wf=@($wr[0]|Get-NetFirewallApplicationFilter -ErrorAction Stop)
            if($wf.Count -eq 1 -and [string]$wf[0].Program -ieq $webExe){
                Remove-NetFirewallRule -Name $name -PolicyStore PersistentStore -ErrorAction Stop
            }else{$hasCleanupError=$true}
        }elseif($wr.Count -gt 0){$hasCleanupError=$true}
    }
    if($ruleName) {
        $remaining=Get-NetFirewallRule -Name $ruleName -PolicyStore PersistentStore -ErrorAction SilentlyContinue
        if($null -ne $remaining) {
            $all=@($remaining)
            if($all.Count -eq 1 -and [string]$all[0].Group -ceq 'PCAD4_MANAGED' -and
               [string]$all[0].Direction -eq 'Outbound' -and [string]$all[0].Action -eq 'Block') {
                $filter=@($all[0] | Get-NetFirewallApplicationFilter -ErrorAction Stop)
                if($filter.Count -eq 1 -and [string]$filter[0].Program -ieq $exe) {
                    Remove-NetFirewallRule -Name $ruleName -PolicyStore PersistentStore -ErrorAction Stop
                    Write-Host 'CLEANUP PASS: regla propia temporal retirada.'
                } else {
                    $hasCleanupError=$true;Write-Warning 'CLEANUP BLOCKED: filtro inesperado; no se retiro regla ajena.'
                }
            } else {
                $hasCleanupError=$true;Write-Warning 'CLEANUP BLOCKED: identidad de regla inesperada.'
            }
        }
    }
    if(Test-Path -LiteralPath $testDir -PathType Container) {
        Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction Stop
    }
    if($hasCleanupError){throw 'QA BLOCKED: cleanup requiere inspeccion; runner efimero se descarta.'}
}
