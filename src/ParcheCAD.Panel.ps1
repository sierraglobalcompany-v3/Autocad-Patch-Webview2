# ParcheCAD 4.1 - panel WinForms; diagnostico y monitor independientes; firewall con gates.
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$SelfTest,[switch]$InteractionSelfTest)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'ParcheCAD.UIState.ps1')
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:Runner=Join-Path $PSScriptRoot 'ParcheCAD.Diagnostico.ps1'
$script:Reports=Join-Path (Split-Path -Parent $PSScriptRoot) 'informes'
$script:Proc=$null
$script:RunRoot=''
$script:LogOut=''
$script:LogErr=''
$script:ExitMarker=''
$script:Started=Get-Date
$script:LastReport=$null
$script:LastExitCode=$null
$script:AdminProc=$null
$script:MonitorProc=$null
$script:MonitorRoot=''
$script:MonitorStopRequested=$false
$script:MonitorErr=''
# CI fixture only: never execute an administrative command or change the firewall.
if($InteractionSelfTest -and ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted')) {
    throw 'InteractionSelfTest requires an ephemeral GitHub-hosted Windows runner.'
}
function PCAD-Label([string]$Text,[int]$X,[int]$Y,[int]$W,[int]$H,[int]$Size=10) {
    $o=New-Object Windows.Forms.Label
    $o.Text=$Text;$o.Location=New-Object Drawing.Point($X,$Y)
    $o.Size=New-Object Drawing.Size($W,$H)
    $o.Font=New-Object Drawing.Font('Segoe UI',$Size)
    return $o
}
function PCAD-Button([string]$Text,[int]$X,[int]$Y,[int]$W,[int]$H=48) {
    $o=New-Object Windows.Forms.Button
    $o.Text=$Text;$o.Location=New-Object Drawing.Point($X,$Y)
    $o.Size=New-Object Drawing.Size($W,$H)
    $o.FlatStyle=[Windows.Forms.FlatStyle]::Flat
    $o.FlatAppearance.BorderColor=[Drawing.Color]::LightSteelBlue
    $o.BackColor=[Drawing.Color]::White
    $o.ForeColor=[Drawing.Color]::FromArgb(23,47,87)
    $o.UseVisualStyleBackColor=$false
    $o.Font=New-Object Drawing.Font('Segoe UI',10)
    return $o
}
function PCAD-Section([string]$Title,[int]$X,[int]$Y,[int]$W,[int]$H) {
    $o=New-Object Windows.Forms.GroupBox
    $o.Text=$Title
    $o.Location=New-Object Drawing.Point($X,$Y)
    $o.Size=New-Object Drawing.Size($W,$H)
    $o.BackColor=[Drawing.Color]::FromArgb(248,250,253)
    $o.ForeColor=[Drawing.Color]::FromArgb(33,59,97)
    $o.Font=New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
    return $o
}
$form=New-Object Windows.Forms.Form
$form.Text='ParcheCAD 4.1 | Control y diagnostico AutoCAD 2023-2027'
$form.ClientSize=New-Object Drawing.Size(1160,862)
$form.MinimumSize=New-Object Drawing.Size(1178,900)
$form.FormBorderStyle='FixedSingle';$form.MaximizeBox=$false
$form.StartPosition='CenterScreen';$form.BackColor=[Drawing.Color]::FromArgb(244,247,251)
$form.Font=New-Object Drawing.Font('Segoe UI',10)
$form.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Font
$header=PCAD-Label 'ParcheCAD 4.1 | Control y diagnostico' 28 19 1100 44 20
$header.ForeColor=[Drawing.Color]::FromArgb(19,38,75)
$header.Font=New-Object Drawing.Font('Segoe UI',20,[Drawing.FontStyle]::Bold)
$sub=PCAD-Label 'Diagnostico de solo lectura. Los cambios requieren autorizacion administrativa expresa.' 30 70 1100 24 10
$sub.ForeColor=[Drawing.Color]::DimGray
$summaryGroup=PCAD-Section 'Estado del sistema' 16 102 1128 170
$installed=PCAD-Label 'AutoCAD detectados: pendiente' 38 139 254 67 13
$webview=PCAD-Label 'WebView2 observado: pendiente' 320 139 254 67 13
$attribution=PCAD-Label 'WebView2 de AutoCAD (probable): pendiente' 602 139 254 67 12
$rules=PCAD-Label 'Reglas Autodesk: pendiente' 885 139 244 67 12
foreach($metric in @($installed,$webview,$attribution,$rules)){
    $metric.BackColor=[Drawing.Color]::White
    $metric.BorderStyle=[Windows.Forms.BorderStyle]::FixedSingle
    $metric.TextAlign=[Drawing.ContentAlignment]::MiddleCenter
    $metric.ForeColor=[Drawing.Color]::FromArgb(23,47,87)
}
$why=PCAD-Label 'ATENCION: WebView2 es compartido con WhatsApp y Correo. No aplicar bloqueos globales.' 28 234 1102 28 10
$why.ForeColor=[Drawing.Color]::DarkRed
$actions=PCAD-Section 'Acciones | selecciona la tarea' 16 281 1128 268
$diagnosticGroup=PCAD-Section 'Diagnostico' 27 310 269 228
$operationGroup=PCAD-Section 'Operaciones' 309 310 269 228
$monitorGroup=PCAD-Section 'Monitor AutoCAD / WebView2' 591 310 269 228
$utilitiesGroup=PCAD-Section 'Utilidades' 873 310 259 228
$start=PCAD-Button 'ANALIZAR SISTEMA' 40 348 243 53
$start.BackColor=[Drawing.Color]::FromArgb(20,105,204)
$start.ForeColor=[Drawing.Color]::White
$start.Font=New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Bold)
$open=PCAD-Button 'ABRIR INFORMES' 40 408 243 52
$preview=PCAD-Button 'VISTA PREVIA DE BLOQUEOS' 40 468 243 52
$apply=PCAD-Button 'APLICAR CON CONFIRMACION' 322 348 243 53
$apply.Font=New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
$rollback=PCAD-Button 'REVERTIR OPERACION PROPIA' 322 408 243 52
$monitorStart=PCAD-Button 'INICIAR MONITOR' 604 348 243 53
$monitorStop=PCAD-Button 'DETENER MONITOR Y GUARDAR LOG' 604 408 243 52
$cancel=PCAD-Button 'CANCELAR CONSULTA' 886 348 233 53
$exit=PCAD-Button 'SALIR' 886 408 233 52
$applyHint=PCAD-Label 'Aplicar: esperando diagnostico' 322 472 243 56 8
$applyHint.ForeColor=[Drawing.Color]::DimGray
$monitorHint=PCAD-Label 'Monitor: observacion, no certifica bloqueo.' 604 472 243 56 8
$monitorHint.ForeColor=[Drawing.Color]::DimGray
$operationInfo=PCAD-Label '' 886 470 233 61 8
$operationInfo.ForeColor=[Drawing.Color]::DarkRed
$progressGroup=PCAD-Section 'Progreso y estado' 16 557 1128 116
$progressLabel=PCAD-Label 'Listo para analizar' 31 588 650 27 10
$bar=New-Object Windows.Forms.ProgressBar
$bar.Location=New-Object Drawing.Point(31,619);$bar.Size=New-Object Drawing.Size(685,20)
$bar.Minimum=0;$bar.Maximum=100
$status=PCAD-Label 'Diagnostico: pendiente' 735 586 396 27 10
$monitorStatus=PCAD-Label 'Monitor: inactivo' 735 618 396 33 9
$monitorStatus.ForeColor=[Drawing.Color]::FromArgb(27,73,133)
$resultsGroup=PCAD-Section 'Resultado e informacion' 16 684 1128 147
$tabs=New-Object Windows.Forms.TabControl
$tabs.Location=New-Object Drawing.Point(30,709)
$tabs.Size=New-Object Drawing.Size(1100,110)
$diagnosticTab=New-Object Windows.Forms.TabPage
$diagnosticTab.Text='Diagnostico y reglas'
$monitorTab=New-Object Windows.Forms.TabPage
$monitorTab.Text='Monitor y registro'
[void]$tabs.TabPages.Add($diagnosticTab)
[void]$tabs.TabPages.Add($monitorTab)
$details=New-Object Windows.Forms.TextBox
$details.Dock=[Windows.Forms.DockStyle]::Fill
$details.Multiline=$true;$details.ScrollBars='Both'
$details.ReadOnly=$true;$details.WordWrap=$false
$details.Font=New-Object Drawing.Font('Consolas',9)
$details.Text='ParcheCAD 4.1: analiza el sistema para consultar las candidatas de reglas.'
$diagnosticTab.Controls.Add($details)
$monitorDetails=New-Object Windows.Forms.TextBox
$monitorDetails.Dock=[Windows.Forms.DockStyle]::Fill
$monitorDetails.Multiline=$true;$monitorDetails.ScrollBars='Both'
$monitorDetails.ReadOnly=$true;$monitorDetails.WordWrap=$false
$monitorDetails.Font=New-Object Drawing.Font('Consolas',9)
$monitorDetails.Text='El monitor es independiente del diagnostico. No observa todas las llamadas de red.'
$monitorTab.Controls.Add($monitorDetails)
$foot=PCAD-Label 'No se bloquea WebView2 compartido. Cambios con administrador, confirmacion escrita y respaldo.' 27 837 1110 24 9
$foot.ForeColor=[Drawing.Color]::DimGray
$form.Controls.AddRange(@($summaryGroup,$actions,$diagnosticGroup,$operationGroup,$monitorGroup,$utilitiesGroup,
    $progressGroup,$resultsGroup,$header,$sub,$installed,$webview,$attribution,$rules,$why,
    $start,$open,$cancel,$exit,$preview,$apply,$rollback,$monitorStart,$monitorStop,
    $applyHint,$monitorHint,$operationInfo,$progressLabel,$bar,$status,$monitorStatus,$tabs,$foot))
foreach($g in @($summaryGroup,$actions,$diagnosticGroup,$operationGroup,$monitorGroup,$utilitiesGroup,$progressGroup,$resultsGroup)){$g.SendToBack()}
$cancel.Enabled=$false
$preview.Enabled=$false;$apply.Enabled=$false;$rollback.Enabled=$false;$monitorStop.Enabled=$false
function PCAD-Busy([bool]$Busy) {
    $script:monitorStart.Enabled=(-not $Busy) -and ($null -eq $script:MonitorProc)
    $script:monitorStop.Enabled=($null -ne $script:MonitorProc) -and (-not $script:MonitorStopRequested)
    $script:start.Enabled=-not $Busy
    $script:open.Enabled=-not $Busy
    $script:cancel.Enabled=$Busy -and ($null -eq $script:AdminProc)
    $ui=Get-PCADReportUiState -Report $script:LastReport -ExitCode $script:LastExitCode
    $script:preview.Enabled=(-not $Busy) -and $ui.CanPreview
    $script:apply.Enabled=(-not $Busy) -and ($null -eq $script:AdminProc) -and $ui.CanApply -and
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'ParcheCAD.Reglas.ps1') -PathType Leaf)
    $script:rollback.Enabled=(-not $Busy) -and (Test-Path -LiteralPath (Join-Path $script:Reports 'operaciones') -PathType Container)
    $script:apply.BackColor=$(if($script:apply.Enabled){[Drawing.Color]::FromArgb(21,138,66)}else{[Drawing.Color]::FromArgb(226,232,240)})
    $script:apply.ForeColor=$(if($script:apply.Enabled){[Drawing.Color]::White}else{[Drawing.Color]::FromArgb(99,110,126)})
    $script:applyHint.Text=Get-PCADApplyBlockReason -Ui $ui -Busy:$Busy
}
function PCAD-StopOwnedDiagnostic {
    [CmdletBinding()]
    param([ValidateRange(100,30000)][int]$TimeoutMs=5000)
    # The panel owns ONLY its read-only diagnostic child. Never terminate
    # administrative processes, unrelated PowerShell instances or WebView2.
    $owned=$script:Proc
    if($null -eq $owned){return $true}
    try {
        $owned.Refresh()
        if(!$owned.HasExited) {
            $owned.Kill()
            if(!$owned.WaitForExit($TimeoutMs)){return $false}
        }
        $owned.Dispose()
        $script:Proc=$null
        return $true
    } catch {
        # Keep the reference and display a failure; never claim CANCELADO.
        return $false
    }
}
function PCAD-ReadLog([string]$File) {
    try {if(Test-Path -LiteralPath $File -PathType Leaf) {return (Get-Content -LiteralPath $File -ErrorAction Stop) -join [Environment]::NewLine}}
    catch {}
    return ''
}
function PCAD-Finish {
    # Diagnostic completion must not stop polling the independent monitor.
    if($null -eq $script:MonitorProc){$timer.Stop()}
    $p=$script:Proc
    if($null -eq $p){return}
    $script:Proc=$null
    # ExitCode of Start-Process -PassThru is not consistently readable in
    # Windows PowerShell 5.1. The child writes a completion marker only after
    # persisting its JSON; absent, damaged or contradictory marker => PARTIAL.
    $p.Refresh()
    $nativeCode=$null
    try {$nativeCode=$p.ExitCode} catch {}
    $p.Dispose()
    $code=2
    if($script:ExitMarker -and (Test-Path -LiteralPath $script:ExitMarker -PathType Leaf)){
        try {
            $text=(Get-Content -LiteralPath $script:ExitMarker -Raw -ErrorAction Stop).Trim()
            if($text -cin @('0','2')){
                $code=[int]$text
                if($null -ne $nativeCode -and [int]$nativeCode -ne $code){$code=2}
            }
        } catch {$code=2}
    }
    $script:LastExitCode=$code
    PCAD-Busy $false
    $bar.Style='Continuous';$bar.Value=100
    $reports=@(Get-ChildItem -LiteralPath $script:RunRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    $file=if($reports.Count){Join-Path $reports[0].FullName 'diagnostico.json'}else{''}
    $data=$null
    if($file -and (Test-Path -LiteralPath $file -PathType Leaf)){
        try {$data=Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop}catch{}
    }
    if($null -eq $data){
        $status.Text='ERROR: informe no disponible o invalido.'
        $status.ForeColor=[Drawing.Color]::Firebrick
        $details.Text=PCAD-ReadLog $script:LogErr
        if(!$details.Text){$details.Text=PCAD-ReadLog $script:LogOut}
        return
    }
    $script:LastReport=$data
    $ui=Get-PCADReportUiState -Report $data -ExitCode $code
    $inst=@(Get-PCADReportRows -Object $ui.Sections -Name 'Installations' | Where-Object {
        (Get-PCADReportField -Object $_ -Name 'FileFound') -eq $true
    })
    $years=@($inst | ForEach-Object {Get-PCADReportField -Object $_ -Name 'Year'} | Sort-Object -Unique)
    $installed.Text='AutoCAD detectados: '+$(if($years.Count){$years -join ', '}else{'ninguno'})
    $web=@(Get-PCADReportRows -Object $ui.Sections -Name 'Processes' | Where-Object {
        (Get-PCADReportField -Object $_ -Name 'Classification') -eq 'WEBVIEW2_COMPARTIDO'
    })
    $acadWeb=@($web | Where-Object {(Get-PCADReportField -Object $_ -Name 'Attribution') -eq 'AUTOCAD_PROBABLE'})
    $webview.Text=("WebView2 observados: {0} procesos" -f $web.Count)
    $attribution.Text=("Atribuibles a AutoCAD: {0} (probable)" -f $acadWeb.Count)
    $historical=@(Get-PCADReportRows -Object $ui.Sections -Name 'Historico')
    if($historical.Count -gt 0 -and $null -ne $historical[0]){
        $h=$historical[0]
        $countAutodesk=Get-PCADReportField -Object $h -Name 'AutoCADAndAutodeskActiveRules'
        $countWebView=Get-PCADReportField -Object $h -Name 'WebView2ActiveRules'
        $countTasks=Get-PCADReportField -Object $h -Name 'SuspectedTasks'
        $rules.Text=("Firewall Autodesk: {0}; WebView2 global: {1}; tareas sospechosas: {2}" -f $countAutodesk,$countWebView,$countTasks)
    }
    $status.Text=$ui.Description
    $status.ForeColor=$(if($ui.Complete){[Drawing.Color]::ForestGreen}else{[Drawing.Color]::Firebrick})
    $progressLabel.Text=("Terminado en {0}s; informe guardado." -f (Get-PCADReportField -Object $data -Name 'ElapsedSeconds'))
    $lines=New-Object System.Collections.Generic.List[string]
    $lines.Add(("Resultado: {0}" -f $ui.Result))
    $catalogRows=@(Get-PCADReportRows -Object $ui.Sections -Name 'Catalog')
    $lines.Add(("Catalogo: {0} ejecutables" -f $catalogRows.Count))
    $scope=@(Get-PCADReportRows -Object $ui.Sections -Name 'CatalogScope')
    if($scope.Count -eq 1){
        $lines.Add(('F14 alcance de EXE: AutoCAD {0}; Autodesk compartido {1}; bloqueo de compartidos: NO' -f
           (Get-PCADReportField -Object $scope[0] -Name 'ProductStatus'),
           (Get-PCADReportField -Object $scope[0] -Name 'SharedStatus')))
    }
    $network=@(Get-PCADReportRows -Object $ui.Sections -Name 'NetworkOverview')
    if($network.Count -gt 0 -and $null -ne $network[0]) {
        $lines.Add(('Atribucion F3: {0} WebView2 observados, {1} AutoCAD probable(s), aislamiento NO VERIFICADO' -f $network[0].TotalWebView2,$network[0].ProbableAutoCAD))
    }
    $planRows=@(Get-PCADReportRows -Object $ui.Sections -Name 'PolicyPreview')
    if($planRows.Count -gt 0 -and $null -ne $planRows[0]) {
        $lines.Add(('Vista previa F4: {0} reglas candidatas, {1} conflictos, {2} excluidos; NINGUNA regla aplicada' -f $planRows[0].Count,$planRows[0].Conflicts,@($planRows[0].Excluded).Count))
    }
    $coverage=@(Get-PCADReportRows -Object $ui.Sections -Name 'Coverage')
    if($coverage.Count -eq 1){
        $cov=$coverage[0]
        $lines.Add(('F11 cobertura NO CERTIFICADA: EXE candidatos {0}, reglas propias presentes {1}, ausentes {2}, sin verificar {3}' -f $cov.CandidateProgramRules,$cov.ProgramRulesPresent,$cov.ProgramRulesMissing,$cov.ProgramRulesUnknown))
        $lines.Add(('Servicios Autodesk: {0}; TCP instantanea: {1}; UDP endpoints: {2}; WebView2: {3}' -f $cov.AutodeskServicesInventoried,$cov.TcpEntriesObserved,$cov.UdpEndpointsObserved,$cov.WebViewProcessesObserved))
        foreach($group in @($cov.Rows)){
            $lines.Add(('  {0}: {1} / {2}' -f $group.Category,$group.Count,$group.Policy))
        }
        $lines.Add('Reglas presentes no prueban bloqueo de trafico. WebView2 excluido.')
    }else{
        $lines.Add('F11 cobertura: INDETERMINADA (matriz no disponible).')
    }
    foreach($c in $ui.Checks){
        $cSection=Get-PCADReportField -Object $c -Name 'Section'
        $cStatus=Get-PCADReportField -Object $c -Name 'Status'
        $cCount=Get-PCADReportField -Object $c -Name 'Count'
        $cDetail=Get-PCADReportField -Object $c -Name 'Detail'
        $lines.Add(("{0}: {1} ({2}) {3}" -f $cSection,$cStatus,$cCount,$cDetail))
    }
    if($null -ne $ui.Recovery){
        $rec=$ui.Recovery
        $active=Get-PCADReportField -Object $rec -Name 'ActiveRules'
        $review=Get-PCADReportField -Object $rec -Name 'NeedsReview'
        $invalid=Get-PCADReportField -Object $rec -Name 'Unverified'
        $recStatus=Get-PCADReportField -Object $rec -Name 'Status'
        $lines.Add(("Recuperacion: {0} reglas registradas (NO VERIFICADAS), {1} operaciones por revisar, {2} respaldos invalidos / lectura {3}" -f $active,$review,$invalid,$recStatus))
    }
    $lines.Add('WebView2 de AutoCAD aislado: NO VERIFICADO.')
    $lines.Add(("Informe: {0}" -f $file))
    $details.Text=$lines -join [Environment]::NewLine
    $tabs.SelectedTab=$diagnosticTab
    PCAD-Busy $false
}
# F17 monitor observer: owned, read-only child, independently stoppable.
function PCAD-MonitorTick {
    $owned=$script:MonitorProc
    if($null -eq $owned){return}
    try{$owned.Refresh()}catch{return}
    if(!$owned.HasExited){return}
    $nativeCode=2
    try{$nativeCode=[int]$owned.ExitCode}catch{}
    $owned.Dispose();$script:MonitorProc=$null
    $script:MonitorStopRequested=$false
    $path=Join-Path $script:MonitorRoot 'monitor.json'
    $marker=Join-Path $script:MonitorRoot 'monitor.exitcode'
    $valid=$false;$data=$null
    if($nativeCode -eq 0 -and (Test-Path -LiteralPath $path -PathType Leaf) -and
       (Test-Path -LiteralPath $marker -PathType Leaf)){
        try{
            $data=Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $exitText=(Get-Content -LiteralPath $marker -Raw -ErrorAction Stop).Trim()
            $valid=($exitText -ceq '0' -and $data.Schema -ceq 'PCAD_MONITOR_1' -and
                    $data.ReadOnly -eq $true -and $data.Result -ceq 'MONITOREO_COMPLETADO_OBSERVACIONAL' -and
                    $data.BlockedTrafficVerified -eq $false -and $data.WebViewIsolationVerified -eq $false)
        }catch{}
    }
    PCAD-Busy ($null -ne $script:Proc -or $null -ne $script:AdminProc)
    if($null -eq $script:Proc -and $null -eq $script:AdminProc){
        if($valid){
            $monitorStatus.Text='Monitor FINALIZADO. Bloqueo total NO verificado.'
            $status.ForeColor=[Drawing.Color]::DarkBlue
            $monitorDetails.Text=('Informe local: {0}' -f $path)+[Environment]::NewLine+
               ('Muestras: {0}; Eventos: {1}; TCP: {2}; UDP endpoints: {3}' -f
                 $data.Samples,@($data.Events).Count,$data.ConnectionEventsTcp,$data.UdpEndpointsObserved)+
               [Environment]::NewLine+'AutoCAD/WebView2: correlacion PROBABLE; ninguna ausencia de trafico certificada.'
        }else{
            $monitorStatus.Text='Monitor PARCIAL o ERROR. No interpretar ausencia de llamadas.'
            $status.ForeColor=[Drawing.Color]::Firebrick
            $monitorDetails.Text='Ver logs locales: '+$script:MonitorErr
        }
    }
    if($null -eq $script:Proc -and $null -eq $script:AdminProc){$timer.Stop()}
}
# Keep the sequence available at the moment of starting observation.
# The monitor records snapshots; it does NOT know when firewall rules were applied.
function Get-PCADMonitorTestGuide {
    $nl=[Environment]::NewLine
    return @(
        'PRUEBA COMPARATIVA - ANTES Y DESPUES'
        ''
        '1. ANTES DE APLICAR: cierra AutoCAD. Si ya hay reglas propias activas,'
        '   esta captura NO es una linea base sin bloqueo; revierte solo las'
        '   reglas propias mediante ParcheCAD antes de comenzar, si procede.'
        '2. Inicia el monitor y abre AutoCAD sin aplicar nuevas reglas.'
        '   Repite actividades normales durante 1-2 minutos.'
        '3. Cierra AutoCAD. APLICA el parche desde el panel con confirmacion'
        '   y administrador. ANOTA LA HORA de aplicacion (hh:mm:ss).'
        '4. DESPUES DE APLICAR: abre AutoCAD y repite las mismas actividades'
        '   durante 1-2 minutos.'
        '5. Pulsa DETENER MONITOR Y GUARDAR LOG. En ABRIR INFORMES revisa'
        '   monitor.json y resumen.txt. Comparte solo tras revisar privacidad.'
        ''
        'IMPORTANTE: el registro NO marca automaticamente la aplicacion,'
        'no demuestra bloqueo total de red ni aislamiento de WebView2.'
        'La sesion termina automaticamente a los 10 minutos.'
    ) -join $nl
}
function PCAD-MonitorBegin {
    if($null -ne $script:MonitorProc -or $null -ne $script:Proc -or $null -ne $script:AdminProc){return}
    try {
        $runner=Join-Path $PSScriptRoot 'ParcheCAD.Monitor.ps1'
        if(!(Test-Path -LiteralPath $runner -PathType Leaf)){throw 'No existe el monitor en este paquete.'}
        if(!(Test-Path -LiteralPath $script:Reports -PathType Container)){
            $null=New-Item -ItemType Directory -Path $script:Reports -Force -ErrorAction Stop
        }
        $id=[guid]::NewGuid().ToString('N')
        $script:MonitorRoot=Join-Path $script:Reports ('monitor_'+$id)
        $logOut=Join-Path $script:Reports ('monitor_'+$id+'.stdout.log')
        $script:MonitorErr=Join-Path $script:Reports ('monitor_'+$id+'.stderr.log')
        $args='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -OutputDirectory "{1}" -DurationSeconds 600 -IntervalMilliseconds 1000' -f $runner,$script:MonitorRoot
        $script:MonitorProc=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $script:MonitorErr -PassThru -ErrorAction Stop
        $script:MonitorStopRequested=$false
        PCAD-Busy $false
        $monitorStatus.Text='Monitor activo: primero sin parche; luego aplica y repite.'
        $status.ForeColor=[Drawing.Color]::DarkBlue
        $monitorDetails.Text='ANTES: abre AutoCAD SIN nuevas reglas y prueba 1-2 minutos.'+[Environment]::NewLine+
            'APLICA: cierra AutoCAD, aplica ParcheCAD y ANOTA LA HORA exacta.'+[Environment]::NewLine+
            'DESPUES: reabre AutoCAD, repite acciones 1-2 minutos y pulsa DETENER.'+[Environment]::NewLine+
            'El monitor NO registra cuando se aplico el parche ni verifica todo el trafico.'+[Environment]::NewLine+
            'Sesion de maximo 10 minutos; log local: '+$script:MonitorRoot
        $tabs.SelectedTab=$monitorTab
        $timer.Start()
    } catch {
        PCAD-Busy $false
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Monitor no iniciado')
    }
}
function PCAD-MonitorStop {
    if($null -eq $script:MonitorProc -or $script:MonitorStopRequested){return}
    if(!(Test-Path -LiteralPath $script:MonitorRoot -PathType Container)){
        $monitorStatus.Text='Monitor iniciando; reintenta detener en unos instantes.'
        return
    }
    try{
        [IO.File]::WriteAllText((Join-Path $script:MonitorRoot 'detener.solicitud'),'STOP',(New-Object Text.UTF8Encoding($false)))
        $script:MonitorStopRequested=$true
        $monitorStop.Enabled=$false
        $monitorStatus.Text='Deteniendo monitor y guardando informe...'
        $timer.Start()
    }catch{
        $monitorStatus.Text='Error al detener monitor; terminara por duracion maxima.'
        $status.ForeColor=[Drawing.Color]::Firebrick
    }
}
$timer=New-Object Windows.Forms.Timer
$timer.Interval=400
$timer.Add_Tick({
    PCAD-MonitorTick
    if($null -ne $script:AdminProc){
        $script:AdminProc.Refresh()
        if($script:AdminProc.HasExited){
            $code=$script:AdminProc.ExitCode
            $script:AdminProc.Dispose();$script:AdminProc=$null
            PCAD-Busy $false
            $operationInfo.Text=('Ultima operacion: codigo '+$code)
            if($code -ne 0){[void][Windows.Forms.MessageBox]::Show('Operacion no completada. Comprueba la consola elevada y el informe; no se asume bloqueo.','ParcheCAD 4.1','OK','Warning')}
            $status.Text=('Operacion administrativa finalizada (codigo '+$code+'). Reconsultando...')
            PCAD-Begin
        } else {$progressLabel.Text='Operacion administrativa en consola elevada: esperando confirmacion/resultado...'}
        return
    }
    if($null -eq $script:Proc){return}
    $elapsed=[int]((Get-Date)-$script:Started).TotalSeconds
    $log=PCAD-ReadLog $script:LogOut
    $hits=[regex]::Matches($log,'\[(\d+)/(\d+)\]\s*([^\r\n]+)')
    if($hits.Count -gt 0){
        $hit=$hits[$hits.Count-1];$step=[int]$hit.Groups[1].Value;$total=[int]$hit.Groups[2].Value
        $progressLabel.Text=("Paso {0}/{1}: {2} | {3}s" -f $step,$total,$hit.Groups[3].Value,$elapsed)
        if($total -gt 0){$bar.Style='Continuous';$bar.Value=[math]::Min(99,[int](100*($step-1)/$total))}
    }else{$progressLabel.Text=("Preparando inventario | {0}s" -f $elapsed)}
    $script:Proc.Refresh()
    if($script:Proc.HasExited){PCAD-Finish}
})
function PCAD-Begin {
    if($null -ne $script:Proc -or $null -ne $script:AdminProc){return}
    $script:LastReport=$null
    $script:LastExitCode=$null
    try{
        if(!(Test-Path -LiteralPath $script:Runner -PathType Leaf)){throw 'Falta el modulo de diagnostico.'}
        if(!(Test-Path -LiteralPath $script:Reports -PathType Container)){
            New-Item -ItemType Directory -Path $script:Reports -Force -ErrorAction Stop | Out-Null
        }
        $script:RunRoot=Join-Path $script:Reports ('panel_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
        New-Item -ItemType Directory -Path $script:RunRoot -ErrorAction Stop | Out-Null
        $script:LogOut=Join-Path $script:RunRoot 'salida.log'
        $script:LogErr=Join-Path $script:RunRoot 'errores.log'
        $script:ExitMarker=Join-Path $script:RunRoot 'diagnostico.exitcode'
        $arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -OutputDirectory "{1}" -WriteExitMarker' -f $script:Runner,$script:RunRoot
        $script:Proc=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $script:LogOut -RedirectStandardError $script:LogErr -PassThru -ErrorAction Stop
        $script:Started=Get-Date
        PCAD-Busy $true
        $bar.Style='Marquee';$bar.MarqueeAnimationSpeed=25
        $status.Text='TRABAJANDO: solo lectura; el panel sigue disponible.'
        $status.ForeColor=[Drawing.Color]::DarkBlue
        $progressLabel.Text='Iniciando consultas...'
        $timer.Start()
    } catch {
        PCAD-Busy $false
        $status.Text='ERROR al iniciar'
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'ParcheCAD','OK','Error')
    }
}
function PCAD-LaunchAdmin([string]$Mode,[string]$Manifest=''){
    if($null -ne $script:Proc -or $null -ne $script:AdminProc){return}
    $engine=Join-Path $PSScriptRoot 'ParcheCAD.Reglas.ps1'
    if(!(Test-Path -LiteralPath $engine -PathType Leaf)){[void][Windows.Forms.MessageBox]::Show('Falta motor de reglas.','ParcheCAD');return}
    try{
        $args='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode {1} -ConfirmChange' -f $engine,$Mode
        if($Mode -eq 'Rollback'){$args+=' -Manifest "'+$Manifest+'"'}
        $script:AdminProc=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args -Verb RunAs -PassThru -ErrorAction Stop
        PCAD-Busy $true;$cancel.Enabled=$false
        $status.Text='OPERACION ELEVADA: esperando confirmacion en consola.'
        $progressLabel.Text='Confirma o cancela en consola y espera a que termine.'
        $timer.Start()
    }catch{
        $script:AdminProc=$null;PCAD-Busy $false
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'No se inicio la operacion')
    }
}
$preview.Add_Click({
    $ui=Get-PCADReportUiState -Report $script:LastReport -ExitCode $script:LastExitCode
    if(!$ui.CanPreview){return}
    $p=$ui.Plan
    $nl=[Environment]::NewLine
    $candidate=Get-PCADReportField -Object $p -Name 'Count'
    $conflicts=Get-PCADReportField -Object $p -Name 'Conflicts'
    $excluded=@(Get-PCADReportRows -Object $p -Name 'Excluded')
    $msg=('Candidatas: {0} / conflictos: {1} / excluidos: {2}' -f $candidate,$conflicts,$excluded.Count)+$nl+'WebView2 compartido excluido; tambien puede afectar LAN.'
    [void][Windows.Forms.MessageBox]::Show($msg,'Vista previa F4')
})
$apply.Add_Click({
    $ui=Get-PCADReportUiState -Report $script:LastReport -ExitCode $script:LastExitCode
    if($null -ne $script:Proc -or $null -ne $script:AdminProc -or !$ui.CanApply){
        [void][Windows.Forms.MessageBox]::Show((Get-PCADApplyBlockReason -Ui $ui -Busy:($null -ne $script:Proc -or $null -ne $script:AdminProc)),'Por que no puedo aplicar','OK','Information')
        return
    }
    $q=('Crear hasta {0} reglas salientes para AutoCAD 2023-2027? Puede afectar LAN y funciones/licencias. NO controla WebView2 compartido. Pedira administrador y confirmacion adicional.' -f
        (Get-PCADReportField -Object $ui.Plan -Name 'Count'))
    if([Windows.Forms.MessageBox]::Show($q,'Confirmar bloqueo','YesNo','Warning') -eq 'Yes'){PCAD-LaunchAdmin -Mode 'Apply'}
})
$rollback.Add_Click({
    $folder=Join-Path $script:Reports 'operaciones'
    if(!(Test-Path -LiteralPath $folder -PathType Container)){return}
    $dlg=New-Object Windows.Forms.OpenFileDialog
    $dlg.InitialDirectory=$folder;$dlg.Filter='Manifiestos ParcheCAD|PCAD4_*.json'
    if($dlg.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){$dlg.Dispose();return}
    $file=[IO.Path]::GetFullPath($dlg.FileName);$dlg.Dispose()
    if([IO.Path]::GetDirectoryName($file) -ine [IO.Path]::GetFullPath($folder) -or
       [IO.Path]::GetFileName($file) -notmatch '^PCAD4_[a-f0-9]{32}\.json$'){
        [void][Windows.Forms.MessageBox]::Show('Selecciona un manifiesto de esta instalacion.','ParcheCAD');return
    }
    if([Windows.Forms.MessageBox]::Show('Revertir solo reglas nuevas registradas en esta operacion?','Revertir','YesNo','Warning') -eq 'Yes'){
        PCAD-LaunchAdmin -Mode 'Rollback' -Manifest $file
    }
})
$start.Add_Click({PCAD-Begin})
$monitorStart.Add_Click({
    if($null -ne $script:MonitorProc -or $null -ne $script:Proc -or $null -ne $script:AdminProc){return}
    $answer=[Windows.Forms.MessageBox]::Show(
        ((Get-PCADMonitorTestGuide)+[Environment]::NewLine+[Environment]::NewLine+'Iniciar monitor ahora?'),
        'Guia de prueba AutoCAD y WebView2','YesNo','Information')
    if($answer -eq [Windows.Forms.DialogResult]::Yes){PCAD-MonitorBegin}
})
$monitorStop.Add_Click({PCAD-MonitorStop})
$open.Add_Click({
    if(Test-Path -LiteralPath $script:Reports -PathType Container){
        Start-Process -FilePath explorer.exe -ArgumentList ('"'+$script:Reports+'"')
    }else{[void][Windows.Forms.MessageBox]::Show('Todavia no existen informes.','ParcheCAD')}
})
$cancel.Add_Click({
    if($null -eq $script:Proc){return}
    if(!$InteractionSelfTest -and [Windows.Forms.MessageBox]::Show('Cancelar consulta? No se modifica Windows.','ParcheCAD','YesNo','Question') -ne 'Yes'){return}
    $timer.Stop()
    if(!(PCAD-StopOwnedDiagnostic)){
        $status.Text='ERROR: no se pudo detener el diagnostico. Espera o revisa el proceso.'
        $status.ForeColor=[Drawing.Color]::Firebrick
        PCAD-Busy $true
        $timer.Start()
        return
    }
    $script:LastReport=$null
    $script:LastExitCode=$null
    PCAD-Busy $false
    $bar.Style='Continuous';$bar.Value=0
    $status.Text='CANCELADO. No se modifico el firewall.'
    $status.ForeColor=[Drawing.Color]::DarkRed
})
$exit.Add_Click({$form.Close()})
$form.Add_FormClosing({
    param($sender,$e)
    if($null -ne $script:AdminProc){$script:AdminProc.Refresh();if(!$script:AdminProc.HasExited){$e.Cancel=$true;return}}
    if($null -ne $script:MonitorProc){
        PCAD-MonitorTick
        if($null -ne $script:MonitorProc){
            $e.Cancel=$true
            PCAD-MonitorStop
            $status.Text='Esperando cierre seguro del monitor antes de salir.'
            return
        }
    }
    $timer.Stop()
    if($null -ne $script:Proc -and !(PCAD-StopOwnedDiagnostic)){
        $e.Cancel=$true
        $status.Text='NO SE PUDO CERRAR: el diagnostico sigue activo.'
        $status.ForeColor=[Drawing.Color]::Firebrick
        $timer.Start()
    }
})
$form.Add_Shown({if(!$InteractionSelfTest){PCAD-Begin}})
if($InteractionSelfTest){
    # F9 CI: WinForms EVENT integration without requiring a desktop session.
    # GitHub-hosted Windows actions are not guaranteed to expose an interactive
    # desktop. OnClick reflection dispatches the same registered button handlers.
    # The real diagnostic child is read-only; dummy child processes simulate
    # Cancel and administrative-close lifecycle, with zero firewall writes.
    $createdRunRoot=''
    $unrelated=$null
    $binding=[Reflection.BindingFlags]::Instance -bor [Reflection.BindingFlags]::NonPublic
    function Invoke-PCADClick([Windows.Forms.Button]$Button){
        $onClick=$Button.GetType().GetMethod('OnClick',$binding)
        if($null -eq $onClick){throw 'F9: cannot resolve button OnClick handler'}
        $null=$onClick.Invoke($Button,[object[]]@([EventArgs]::Empty))
    }
    try {
        if($apply.Enabled -or !$start.Enabled){throw 'F9: initial action state unsafe'}
        Write-Host 'F9: dispatch Analyze handler without displaying a desktop window.'
        Invoke-PCADClick -Button $start
        if($null -eq $script:Proc -or !$cancel.Enabled -or $apply.Enabled){throw 'F9: Analyze did not start read-only child'}
        $createdRunRoot=$script:RunRoot
        if(!$script:Proc.WaitForExit(65000)){throw 'F9: read-only diagnostic child exceeded 65 seconds'}
        # Regression: a running observation child must survive F0 completion,
        # and the WinForms timer must remain enabled to report its final log.
        $monitorFixture=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList '-NoLogo -NoProfile -Command "Start-Sleep -Seconds 30"' -PassThru -WindowStyle Hidden -ErrorAction Stop
        $script:MonitorProc=$monitorFixture
        PCAD-Finish
        if(!$timer.Enabled -or $null -eq $script:MonitorProc){
            throw 'Monitor F17: diagnostic completion incorrectly stopped observation UI.'
        }
        $monitorFixture.Refresh()
        if(!$monitorFixture.HasExited){$monitorFixture.Kill();$monitorFixture.WaitForExit(5000)|Out-Null}
        $monitorFixture.Dispose();$script:MonitorProc=$null
        $timer.Stop()
        PCAD-Busy $false
        if($null -eq $script:LastReport -or $null -eq $script:LastExitCode){
            throw 'F9: diagnostic process finished without a readable report or completion marker'
        }
        $ui=Get-PCADReportUiState -Report $script:LastReport -ExitCode $script:LastExitCode
        if(!$start.Enabled -or $cancel.Enabled -or $apply.Enabled){throw 'F9: wrong controls after read-only diagnostic on clean runner'}
        if($status.Text -cne $ui.Description){throw 'F9: GUI header disagrees with validator'}
        $scope=@(Get-PCADReportRows -Object $ui.Sections -Name 'CatalogScope')
        if($scope.Count -ne 1 -or $scope[0].SharedAutomaticBlocking -ne $false -or
           $details.Text -notmatch 'F14 alcance de EXE'){
            throw 'F14: report/UI missing shared inventory warning or it allowed automatic shared blocking'
        }
        $cov=@(Get-PCADReportRows -Object $ui.Sections -Name 'Coverage')
        if($cov.Count -ne 1 -or [string]$cov[0].Status -cne 'COBERTURA_NO_CERTIFICADA' -or
           $cov[0].AllAutodeskTrafficBlockedVerified -ne $false -or
           $details.Text -notmatch 'F11 cobertura NO CERTIFICADA'){
            throw 'F11: diagnostic child/UI did not expose honest coverage matrix'
        }
        Write-Host ('F9 PASS: Analyze handler -> read-only Windows child -> report -> safe status ({0}).' -f $ui.Result)

        Write-Host 'F9: dispatch Cancel handler against an owned dummy sleeping process.'
        $unrelated=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList '-NoLogo -NoProfile -Command "Start-Sleep -Seconds 30"' -PassThru -WindowStyle Hidden -ErrorAction Stop
        $script:LastReport=$null;$script:LastExitCode=$null
        $script:Proc=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList '-NoLogo -NoProfile -Command "Start-Sleep -Seconds 30"' -PassThru -WindowStyle Hidden -ErrorAction Stop
        $ownedPid=$script:Proc.Id
        PCAD-Busy $true
        if(!$cancel.Enabled -or $apply.Enabled){throw 'F9: cancel disabled while read-only child running'}
        Invoke-PCADClick -Button $cancel
        if($null -ne $script:Proc -or $cancel.Enabled -or $apply.Enabled -or $status.Text -notmatch 'CANCELADO'){
            throw 'F9: cancel handler failed to release owned process and reset controls'
        }
        if(Get-Process -Id $ownedPid -ErrorAction SilentlyContinue){throw 'F10: Cancel claimed success but owned PID is still active'}
        $unrelated.Refresh()
        if($unrelated.HasExited){throw 'F10: Cancel unexpectedly terminated unrelated PowerShell'}
        Write-Host 'F10 PASS: Cancel verified owned PID exit, unrelated PowerShell stays alive.'

        Write-Host 'F9: exercise FormClosing handler against a dummy admin placeholder (no UAC).'
        $script:AdminProc=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList '-NoLogo -NoProfile -Command "Start-Sleep -Seconds 30"' -PassThru -WindowStyle Hidden -ErrorAction Stop
        PCAD-Busy $true
        if($cancel.Enabled -or $apply.Enabled -or $rollback.Enabled){throw 'F9: mutating controls enabled during simulated administration'}
        $onFormClosing=[Windows.Forms.Form].GetMethod('OnFormClosing',$binding)
        if($null -eq $onFormClosing){throw 'F9: cannot resolve FormClosing'}
        $closing=[Windows.Forms.FormClosingEventArgs]::new([Windows.Forms.CloseReason]::UserClosing,$false)
        $null=$onFormClosing.Invoke($form,[object[]]@($closing))
        if(!$closing.Cancel){throw 'F9: FormClosing was not canceled during simulated admin process'}
        $script:AdminProc.Refresh()
        if(!$script:AdminProc.HasExited){$script:AdminProc.Kill()}
        $script:AdminProc.WaitForExit(5000) | Out-Null
        $script:AdminProc.Dispose();$script:AdminProc=$null
        PCAD-Busy $false
        $closing2=[Windows.Forms.FormClosingEventArgs]::new([Windows.Forms.CloseReason]::UserClosing,$false)
        $null=$onFormClosing.Invoke($form,[object[]]@($closing2))
        if($closing2.Cancel){throw 'F9: FormClosing stays blocked after admin placeholder ends'}
        Write-Host 'F9 PASS: FormClosing denied with active admin placeholder, allowed after exit.'
        # Exercise normal FormClosing against an owned, read-only process as well.
        $script:Proc=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList '-NoLogo -NoProfile -Command "Start-Sleep -Seconds 30"' -PassThru -WindowStyle Hidden -ErrorAction Stop
        $closingPid=$script:Proc.Id
        PCAD-Busy $true
        $closingReadOnly=[Windows.Forms.FormClosingEventArgs]::new([Windows.Forms.CloseReason]::UserClosing,$false)
        $null=$onFormClosing.Invoke($form,[object[]]@($closingReadOnly))
        if($closingReadOnly.Cancel -or $null -ne $script:Proc){throw 'F10: closing failed to stop its owned read-only process'}
        if(Get-Process -Id $closingPid -ErrorAction SilentlyContinue){throw 'F10: closing left read-only child running'}
        $unrelated.Refresh()
        if($unrelated.HasExited){throw 'F10: closing terminated unrelated PowerShell'}
        Write-Host 'F10 PASS: FormClosing verified owned child stopped without touching unrelated process.'
        Write-Host 'PASS F9: WinForms event handlers validated headlessly, UAC/visual QA remain pending.' -ForegroundColor Green
        exit 0
    } finally {
        $timer.Stop()
        foreach($name in @('Proc','AdminProc','MonitorProc')){
            $p=Get-Variable -Name $name -Scope Script -ValueOnly -ErrorAction SilentlyContinue
            if($null -ne $p){
                try {$p.Refresh();if(!$p.HasExited){$p.Kill();$p.WaitForExit(5000)|Out-Null}}catch{}
                try {$p.Dispose()}catch{}
                Set-Variable -Name $name -Scope Script -Value $null
            }
        }
        if($null -ne $unrelated){
            try {$unrelated.Refresh();if(!$unrelated.HasExited){$unrelated.Kill();$unrelated.WaitForExit(5000)|Out-Null}}catch{}
            try {$unrelated.Dispose()}catch{}
        }
        if(!$form.IsDisposed){$form.Dispose()}
        if($createdRunRoot -and (Test-Path -LiteralPath $createdRunRoot -PathType Container)){
            Remove-Item -LiteralPath $createdRunRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
if($SelfTest){
    $guide=Get-PCADMonitorTestGuide
    foreach($required in @('ANTES DE APLICAR','APLICA','DESPUES DE APLICAR',
                           'ANOTA LA HORA','NO marca automaticamente','10 minutos')){
        if(!$guide.Contains($required)){throw ('GUI selftest: incomplete monitor instructions: '+$required)}
    }
    if(!$form.Controls.Contains($preview) -or !$form.Controls.Contains($apply) -or
       !$form.Controls.Contains($rollback) -or !$form.Controls.Contains($monitorStart) -or
        !$form.Controls.Contains($monitorStop) -or $monitorStop.Enabled -or $apply.Enabled -or $rollback.Enabled){throw 'GUI selftest: controls missing or dangerous startup state'}
    $script:LastExitCode=0
    $script:LastReport=[pscustomobject]@{
        Tool='ParcheCAD';SchemaVersion=1;ReadOnly=$true;Result='PARCIAL_NO_VERIFICADO'
        Sections=[pscustomobject]@{
            PolicyPreview=@([pscustomobject]@{Count=2;Conflicts=0;State='PLAN_NO_APLICADO'})
        }
    }
    PCAD-Busy $false
    if($apply.Enabled -or !$monitorStart.Enabled -or $monitorStop.Enabled){throw 'GUI selftest: unsafe monitor/action state'}
    if(!$form.Controls.Contains($tabs) -or !$diagnosticTab.Controls.Contains($details) -or !$monitorTab.Controls.Contains($monitorDetails)){throw 'V41: diagnostico y monitor no separados'}
    if($form.Text -notmatch '4\.1'){throw 'V41: version visible incorrecta'}
    $script:LastReport.Result='DIAGNOSTICO_COMPLETADO_SIN_CAMBIOS'
    PCAD-Busy $false
    if($apply.Enabled){throw 'GUI selftest: missing recovery evidence allowed apply'}
    $stages=@('Installations','Processes','Services','Catalog','Firewall','Tasks',
              'Historico','Connections','NetworkOverview','PolicyPreview')
    $script:LastReport | Add-Member -NotePropertyName Checks -NotePropertyValue @($stages|ForEach-Object{
        [pscustomobject]@{Section=$_;Status='OK'}
    })
    $script:LastReport.Sections | Add-Member -NotePropertyName Historico -NotePropertyValue @(
        [pscustomobject]@{Recovery=[pscustomobject]@{Status='PARCIAL';NeedsReview=1;Unverified=0}}
    )
    PCAD-Busy $false
    if($apply.Enabled){throw 'GUI selftest: incomplete recovery allowed apply'}
    $script:LastReport.Sections.Historico[0].Recovery.Status='OK'
    $script:LastReport.Sections.Historico[0].Recovery.NeedsReview=0
    PCAD-Busy $false
    if(!$apply.Enabled){throw 'GUI selftest: valid preview did not enable apply'}
    $script:LastExitCode=2
    PCAD-Busy $false
    if($apply.Enabled){throw 'GUI selftest: nonzero child exit allowed apply'}
    $script:LastExitCode=0
    PCAD-Busy $true
    if($apply.Enabled -or $rollback.Enabled -or $monitorStart.Enabled){throw 'GUI selftest: modifications/monitor allowed while busy'}
    Write-Host 'PASS GUI: form initialized, partial diagnostics blocked, valid preview gated and busy state protected.'
    $form.Dispose()
    exit 0
}
[void][Windows.Forms.Application]::Run($form)
