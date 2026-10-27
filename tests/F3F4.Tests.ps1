# F3/F4 - QA sin modificar firewall real: mocks de NetSecurity y ficheros temporales.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$paths=@('ParcheCAD.Core.ps1','ParcheCAD.Catalogo.ps1','ParcheCAD.Network.ps1',
         'ParcheCAD.Policy.ps1','ParcheCAD.Firewall.ps1','ParcheCAD.Diagnostico.ps1','ParcheCAD.Reglas.ps1','ParcheCAD.Panel.ps1')
foreach($name in $paths){
    $f=Join-Path (Join-Path $root 'src') $name
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errors)
    if(@($errors).Count){throw ("PS Parser FAIL "+$name+": "+($errors|Out-String))}
}
. (Join-Path $root 'src\ParcheCAD.Core.ps1')
. (Join-Path $root 'src\ParcheCAD.Catalogo.ps1')
. (Join-Path $root 'src\ParcheCAD.Network.ps1')
. (Join-Path $root 'src\ParcheCAD.Policy.ps1')
. (Join-Path $root 'src\ParcheCAD.Firewall.ps1')
function Assert-F34([bool]$Condition,[string]$Label) {
    if(!$Condition){throw ("FAIL: "+$Label)}
}
# F3: parentesco probable, WebView2 de otra app no atribuible y conexion puntal.
$procs=@(
  [pscustomobject]@{PID=10;ParentPID=1;Name='acad.exe';ExecutablePath='C:\Program Files\Autodesk\AutoCAD 2023\acad.exe';UserDataFolder='';HostHint='';Classification='AUTOCAD_PRODUCTO'},
  [pscustomobject]@{PID=11;ParentPID=1;Name='WhatsApp.exe';ExecutablePath='C:\WhatsApp\WhatsApp.exe';UserDataFolder='';HostHint='';Classification='DESCONOCIDO'},
  [pscustomobject]@{PID=12;ParentPID=10;Name='msedgewebview2.exe';ExecutablePath='C:\Microsoft\msedgewebview2.exe';UserDataFolder='';HostHint='';Classification='WEBVIEW2_COMPARTIDO'},
  [pscustomobject]@{PID=13;ParentPID=11;Name='msedgewebview2.exe';ExecutablePath='C:\Microsoft\msedgewebview2.exe';UserDataFolder='';HostHint='';Classification='WEBVIEW2_COMPARTIDO'}
)
$net=Get-PCADNetworkOverview -Processes $procs -Connections @(
  [pscustomobject]@{PID=12;Protocol='TCP';State='Established';RemoteScope='PUBLICA_O_ESPECIAL'}
)
Assert-F34 ($net.TotalWebView2 -eq 2 -and $net.ProbableAutoCAD -eq 1 -and $net.WebViewIndeterminate -eq 1) 'F3 host segregation'
Assert-F34 (!$net.IsolationVerified -and !$net.TrafficAbsenceVerified) 'F3 no false verified isolation'
# F4: generar ruta sintética AutoCAD.
$temp=Join-Path ([IO.Path]::GetTempPath()) ('PCAD-F4-'+[guid]::NewGuid().ToString('N'))
$install=Join-Path $temp 'Autodesk\AutoCAD 2023'
$backup=Join-Path $temp 'informes'
try {
    $null=New-Item -ItemType Directory -Path $install -Force
    $main=Join-Path $install 'acad.exe'
    $extra=Join-Path $install 'helper.exe'
    foreach($p in @($main,$extra)){[IO.File]::WriteAllBytes($p,[byte[]]@(0))}
    $catalog=@(
      [pscustomobject]@{Path=$main;Name='acad.exe';Classification='AUTOCAD_PRODUCTO';Policy='SOLO_INVENTARIO';Year=2023},
      [pscustomobject]@{Path=$extra;Name='helper.exe';Classification='AUTOCAD_PRODUCTO';Policy='SOLO_INVENTARIO';Year=2023},
      [pscustomobject]@{Path='C:\Microsoft\EdgeWebView\msedgewebview2.exe';Name='msedgewebview2.exe';Classification='WEBVIEW2_COMPARTIDO';Policy='SOLO_INVENTARIO';Year=2023}
    )
    $plan=New-PCADRulePlan -Catalog $catalog
    Assert-F34 ($plan.Count -eq 2 -and @($plan.Excluded).Count -eq 1) 'F4 no shared WebView'
    Assert-F34 ($plan.Entries[0].RuleName -eq (Get-PCADRuleName -Program $plan.Entries[0].Program)) 'F4 deterministic name'
    Assert-F34 ($plan.Entries[0].RuleName -ne $plan.Entries[1].RuleName) 'F4 unique names'
    $script:fakeRules=@{}
    $script:FailOnHelper=$false
    function Test-PCADAdministrator {return $true}
    function Get-NetFirewallRule {
        [CmdletBinding()]
        param($Name,$PolicyStore)
        if($script:fakeRules.ContainsKey([string]$Name)) {return $script:fakeRules[[string]$Name]}
        return $null
    }
    function Get-NetFirewallApplicationFilter {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline=$true)]$Rule)
        process {if($null -ne $Rule){return [pscustomobject]@{Program=$Rule.Program}}}
    }
    function Get-NetFirewallPortFilter {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline=$true)]$Rule)
        process {
            if($null -ne $Rule){
                return [pscustomobject]@{
                    Protocol=if($Rule.PSObject.Properties['MockProtocol']){$Rule.MockProtocol}else{'Any'}
                    LocalPort='Any';RemotePort='Any'
                }
            }
        }
    }
    function Get-NetFirewallAddressFilter {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline=$true)]$Rule)
        process {
            if($null -ne $Rule){
                return [pscustomobject]@{
                    LocalAddress='Any'
                    RemoteAddress=if($Rule.PSObject.Properties['MockRemoteAddress']){$Rule.MockRemoteAddress}else{'Any'}
                }
            }
        }
    }
    function Get-NetFirewallServiceFilter {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline=$true)]$Rule)
        process {
            if($null -ne $Rule){
                return [pscustomobject]@{
                    Service=if($Rule.PSObject.Properties['MockService']){$Rule.MockService}else{'Any'}
                }
            }
        }
    }
    function Get-NetFirewallInterfaceTypeFilter {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline=$true)]$Rule)
        process {
            if($null -ne $Rule){
                return [pscustomobject]@{
                    InterfaceType=if($Rule.PSObject.Properties['MockInterfaceType']){$Rule.MockInterfaceType}else{'Any'}
                }
            }
        }
    }
    function Get-NetFirewallInterfaceFilter {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline=$true)]$Rule)
        process {
            if($null -ne $Rule){
                return [pscustomobject]@{
                    InterfaceAlias=if($Rule.PSObject.Properties['MockInterfaceAlias']){$Rule.MockInterfaceAlias}else{'Any'}
                }
            }
        }
    }
    function New-NetFirewallRule {
        [CmdletBinding()]
        param($Name,$DisplayName,$Group,$Direction,$Action,$Program,$Enabled,$Profile,$PolicyStore)
        if($script:FailOnHelper -and $Program -match 'helper\.exe$'){throw 'Fallo simulado de alta'}
        if($script:fakeRules.ContainsKey([string]$Name)){throw 'Duplicado de prueba'}
        $script:fakeRules[[string]$Name]=[pscustomobject]@{
            Name=$Name;DisplayName=$DisplayName;Group=$Group;Direction=[string]$Direction
            Action=[string]$Action;Enabled=[string]$Enabled;Profile=[string]$Profile;Program=$Program
        }
    }
    function Remove-NetFirewallRule {
        [CmdletBinding()]
        param($Name,$PolicyStore)
        if(!$script:fakeRules.ContainsKey([string]$Name)){throw 'No existe'}
        $script:fakeRules.Remove([string]$Name)
    }
    $id=[guid]::NewGuid().ToString('N')
    $progress=Join-Path $backup ('PCAD4_PROGRESS_'+$id+'.json')
    $first=Invoke-PCADApplyPlan -Plan $plan -BackupDirectory $backup -OperationId $id -ProgressFile $progress -Commit
    Write-Host ('F4 debug apply result: '+($first|ConvertTo-Json -Depth 7 -Compress))
    Assert-F34 ($first.Verified -eq 2 -and $first.Manifest -like ('*PCAD4_'+$id+'.json')) 'F4 journal correlates ID and validates all rules'
    $progressData=Get-Content -LiteralPath $progress -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    Assert-F34 ($progressData.Stage -eq 'VERIFYING' -and $progressData.Completed -eq 2 -and
        $progressData.Total -eq 2) 'F4 progress persisted and verified before APPLIED'
    $duplicateRejected=$false
    try{$null=Invoke-PCADApplyPlan -Plan $plan -BackupDirectory $backup -OperationId $id -Commit}
    catch{$duplicateRejected=$true}
    Assert-F34 $duplicateRejected 'F4 refuses to reuse existing operation ID'
    Write-Host ('F4 diagnostic: {0}' -f ($first | ConvertTo-Json -Depth 7 -Compress))
    Assert-F34 ($first.Status -eq 'APPLIED' -and $first.Created -eq 2 -and $script:fakeRules.Count -eq 2) 'F4 mocked apply'
    $secondPlan=New-PCADRulePlan -Catalog $catalog -CheckExisting
    $second=Invoke-PCADApplyPlan -Plan $secondPlan -BackupDirectory $backup -Commit
    Assert-F34 ($second.Status -eq 'APPLIED' -and $second.Created -eq 0 -and $second.Verified -eq 2 -and $script:fakeRules.Count -eq 2) 'F4 idempotency'
    $undo=Invoke-PCADRollbackRules -JournalPath $first.Manifest -Commit
    Assert-F34 ($undo.Status -eq 'ROLLED_BACK' -and $undo.Removed -eq 2 -and $script:fakeRules.Count -eq 0) 'F4 rollback own created only'
    $undoAgain=Invoke-PCADRollbackRules -JournalPath $first.Manifest -Commit
    Assert-F34 ($undoAgain.Removed -eq 0) 'F4 rollback idempotency'
    # Colisión con nombre ajeno: prohibir preflight en lugar de pisarla.
    $conflict=$plan.Entries[0]
    $script:fakeRules[[string]$conflict.RuleName]=[pscustomobject]@{
        Name=$conflict.RuleName;Group='FOREIGN';Program=$conflict.Program
        Action='Block';Direction='Outbound';Enabled='True';Profile='Any'
    }
    $conflicted=New-PCADRulePlan -Catalog $catalog -CheckExisting
    Assert-F34 ($conflicted.Conflicts -eq 1) 'F4 foreign collision'
    $script:fakeRules.Clear()
    # F16: identical primary rule metadata is NOT sufficient if a filter
    # narrows to TCP, a single destination, an app service or an interface.
    foreach($drift in @(
        @{MockProtocol='TCP'},@{MockRemoteAddress='192.0.2.10'},
        @{MockService='Spooler'},@{MockInterfaceType='Wireless'},
        @{MockInterfaceAlias='Ethernet'}
    )){
        $one=$plan.Entries[0]
        $rule=[pscustomobject]@{
            Name=$one.RuleName;Group='PCAD4_MANAGED';Program=$one.Program
            Action='Block';Direction='Outbound';Enabled='True';Profile='Any'
        }
        foreach($key in $drift.Keys){$rule|Add-Member -NotePropertyName $key -NotePropertyValue $drift[$key]}
        $script:fakeRules[[string]$one.RuleName]=$rule
        Assert-F34 ((Get-PCADActualRuleStatus -RuleName $one.RuleName -Program $one.Program).State -eq 'CONFLICT') ('F16 narrowed filter rejected '+($drift.Keys -join ','))
        $collision=New-PCADRulePlan -Catalog $catalog -CheckExisting
        Assert-F34 ($collision.Conflicts -eq 1) ('F16 narrowed filter is blocking conflict '+($drift.Keys -join ','))
        $script:fakeRules.Clear()
    }
    # Fallo a mitad: compensación de reglas propias creadas.
    $script:FailOnHelper=$true
    $failed=Invoke-PCADApplyPlan -Plan $plan -BackupDirectory $backup -Commit
    Assert-F34 ($failed.Status -eq 'ERROR_ROLLED_BACK' -and $script:fakeRules.Count -eq 0) 'F4 failure compensation'
    Assert-F34 ((Test-Path -LiteralPath $failed.Manifest -PathType Leaf)) 'F4 journal persists'
    # Misma ruta fake, pero WebView2: siempre rechazado.
    $invalid=[pscustomobject]@{Year=2023;Program='C:\Microsoft\EdgeWebView\msedgewebview2.exe';Group='PCAD4_MANAGED';RuleName='invalid';Direction='Outbound';Action='Block';Profile='Any'}
    $rejected=$false
    try{$null=Assert-PCADManagedEntry -Entry $invalid}catch{$rejected=$true}
    Assert-F34 $rejected 'F4 invalid rule rejected'
} finally {
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
Write-Host 'PASS F3/F4: attribution, policy, mocked firewall apply, idempotence, conflicts, rollback.' -ForegroundColor Green
