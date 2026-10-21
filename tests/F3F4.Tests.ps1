# F3/F4 - QA sin modificar firewall real: mocks de NetSecurity y ficheros temporales.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$paths=@('ParcheCAD.Core.ps1','ParcheCAD.Catalogo.ps1','ParcheCAD.Network.ps1',
         'ParcheCAD.Policy.ps1','ParcheCAD.Firewall.ps1','ParcheCAD.Diagnostico.ps1')
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
        param($Name,$PolicyStore,$ErrorAction)
        if($script:fakeRules.ContainsKey([string]$Name)) {return $script:fakeRules[[string]$Name]}
        return $null
    }
    function Get-NetFirewallApplicationFilter {
        param([Parameter(ValueFromPipeline=$true)]$Rule,$ErrorAction)
        process {if($null -ne $Rule){return [pscustomobject]@{Program=$Rule.Program}}}
    }
    function New-NetFirewallRule {
        param($Name,$DisplayName,$Group,$Direction,$Action,$Program,$Enabled,$Profile,$PolicyStore,$ErrorAction)
        if($script:FailOnHelper -and $Program -match 'helper\.exe$'){throw 'Fallo simulado de alta'}
        if($script:fakeRules.ContainsKey([string]$Name)){throw 'Duplicado de prueba'}
        $script:fakeRules[[string]$Name]=[pscustomobject]@{
            Name=$Name;DisplayName=$DisplayName;Group=$Group;Direction=[string]$Direction
            Action=[string]$Action;Enabled=[string]$Enabled;Profile=[string]$Profile;Program=$Program
        }
    }
    function Remove-NetFirewallRule {
        param($Name,$PolicyStore,$ErrorAction)
        if(!$script:fakeRules.ContainsKey([string]$Name)){throw 'No existe'}
        $script:fakeRules.Remove([string]$Name)
    }
    $first=Invoke-PCADApplyPlan -Plan $plan -BackupDirectory $backup -Commit
    Write-Host ('F4 diagnostic: {0}' -f ($first | ConvertTo-Json -Depth 7 -Compress))
    Assert-F34 ($first.Status -eq 'APPLIED' -and $first.Created -eq 2 -and $script:fakeRules.Count -eq 2) 'F4 mocked apply'
    $secondPlan=New-PCADRulePlan -Catalog $catalog -CheckExisting
    $second=Invoke-PCADApplyPlan -Plan $secondPlan -BackupDirectory $backup -Commit
    Assert-F34 ($second.Status -eq 'APPLIED' -and $second.Created -eq 0 -and $script:fakeRules.Count -eq 2) 'F4 idempotency'
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
