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
    $recoverCrash=Invoke-PCADRollbackRules -JournalPath $manifestCrash -Commit
    if($recoverCrash.Status -ne 'ROLLED_BACK' -or $recoverCrash.Removed -ne 1){throw 'No se recupero regla real con journal CREATING.'}
    if((Get-PCADActualRuleStatus -RuleName $ruleName -Program $exe).State -ne 'MISSING'){throw 'Regla permanecio tras recuperacion interrumpida.'}
    # El mismo journal recuperado no debe volver a retirar reglas.
    $again=Invoke-PCADRollbackRules -JournalPath $manifestCrash -Commit
    if($again.Removed -ne 0){throw 'Rollback interrumpido no fue idempotente.'}
    Write-Host 'PASS REAL: recuperacion tras interrupcion CREATING, sin ejecutable y sin reglas residuales.' -ForegroundColor Green

} finally {
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
