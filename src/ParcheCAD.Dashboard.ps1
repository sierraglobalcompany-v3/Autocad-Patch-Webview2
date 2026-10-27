# ParcheCAD 4.3 - WPF frontend only. CLI firewall/audit/monitor engines unchanged.
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$SelfTest,[switch]$StateSelfTest)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase -ErrorAction Stop
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop

$xaml=Join-Path $PSScriptRoot 'ParcheCAD.Dashboard.xaml'
if(!(Test-Path -LiteralPath $xaml -PathType Leaf)){throw 'Falta el layout WPF.'}
# Respetar WorkArea real (en DIPs) para que 150%/200% no coloque la ventana
# fuera de la zona visible; el contenido se desplaza verticalmente.
$reader=[Xml.XmlReader]::Create($xaml)
try {$window=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
$work=[Windows.SystemParameters]::WorkArea
if($work.Width -gt 0 -and $work.Height -gt 0){
    $window.MaxWidth=[Math]::Max(320.0,($work.Width-18.0))
    $window.MaxHeight=[Math]::Max(260.0,($work.Height-18.0))
    if($window.MinWidth -gt $window.MaxWidth){$window.MinWidth=$window.MaxWidth}
    if($window.MinHeight -gt $window.MaxHeight){$window.MinHeight=$window.MaxHeight}
    $window.Width=[Math]::Min($window.Width,$window.MaxWidth)
    $window.Height=[Math]::Min($window.Height,$window.MaxHeight)
}
$names=@('MainWindow','MetricAutoCAD','MetricRules','MetricConflicts',
 'MetricWeb','MetricProbable','MetricsGrid','WorkTabs','DetailsExpander','FirewallCard','WebCard','TopStatus','StatusDot','FirewallHint','MonitorHint',
 'BtnPreview','BtnApply','BtnRollback','BtnAudit','BtnMonitor','BtnStopMonitor','BtnAuditedBlock','BtnGenericAutoCAD','BtnWebRestoreInfo',
 'BtnReports','BtnCancel','BtnExit','ActivityText','Elapsed','Progress',
 'TxtFirewall','TxtWeb','TxtMonitor','ResultTabs','ResultTag')
$ui=@{}
foreach($name in $names){
    $c=$window.FindName($name)
    if($null -eq $c){throw ('WPF incompleto: '+$name)}
    $ui[$name]=$c
}

# Layout compacto: una tarea visible por pestaña; solo cambian las columnas KPI.
# WPF adapta filas y botones sin cálculos manuales de tamaño o DPI.
function PCAD-Layout([double]$WindowWidth) {
    $usable=[Math]::Max(280.0,($WindowWidth - 50.0))
    if($usable -ge 790){$ui.MetricsGrid.Columns=4}
    elseif($usable -ge 490){$ui.MetricsGrid.Columns=2}
    else {$ui.MetricsGrid.Columns=1}
}
$window.Add_SizeChanged({PCAD-Layout -WindowWidth $window.ActualWidth})
PCAD-Layout -WindowWidth ([double]$window.Width)
if($SelfTest){
    if($ui.BtnStopMonitor.IsEnabled -or $ui.BtnCancel.IsEnabled -or $ui.BtnAuditedBlock.IsEnabled){throw 'WPF: dangerous initial controls.'}
    if($window.Title -notmatch '4.3' -or $ui.BtnPreview.Content.Text -notmatch 'ANALIZAR FIREWALL' -or
       $ui.BtnAudit.Content.Text -notmatch 'ANALIZAR WEBVIEW2'){throw 'WPF: missing dashboard actions.'}
    foreach($w in @(430.0,580.0,780.0,1120.0,1440.0)){
        PCAD-Layout -WindowWidth $w
        $cols=if($w -ge 840){4}elseif($w -ge 540){2}else{1}
        if($ui.MetricsGrid.Columns -ne $cols){throw ('WPF responsive metrics failed at '+$w)}
        if($ui.WorkTabs.Items.Count -ne 2 -or $ui.DetailsExpander.IsExpanded){
            throw ('WPF compact tabs or default details failed at '+$w)
        }
    }
    Write-Host ('PASS WPF 4.3: XAML loaded, {0} named controls, compact tabs, responsive 430/580/780/1120/1440 and safety defaults.' -f $names.Count)
    $window.Close()
    exit 0
}
$script:Reports=Join-Path (Split-Path -Parent $PSScriptRoot) 'informes'
$script:Child=$null
$script:ChildType=''
$script:ChildRoot=''
$script:ChildStart=Get-Date
$script:ChildLog=''
$script:ChildErr=''
$script:Monitor=$null
$script:MonitorRoot=''
$script:MonitorStopping=$false
$script:MonitorStart=Get-Date
$script:Admin=$null
$script:AdminStart=Get-Date
$script:AuditReady=$false
$script:AuditedApplyPending=$false
$script:CloseRequested=$false
$script:CloseQueued=$false
$script:ShuttingDown=$false

function PCAD-Read([string]$File){
    if($File -and (Test-Path -LiteralPath $File -PathType Leaf)){
        try {return (Get-Content -LiteralPath $File -Raw -ErrorAction Stop).Trim()}catch{}
    }
    return ''
}
# Una unica representacion visual de los estados; no altera los gates del motor.
function PCAD-Status {
    param([string]$Text,
        [ValidateSet('IDLE','CONSULTING','PREVIEW_OK','PARTIAL','ERROR',
                     'MONITORING','MONITOR_STOPPING','ADMIN_WAIT','ADMIN_DONE','CANCELLED')]
        [string]$State='IDLE')
    $visual=switch($State){
        'IDLE'             {@('LISTO · SIN CAMBIOS','#0C7140')}
        'CONSULTING'       {@('CONSULTANDO','#195CB5')}
        'PREVIEW_OK'       {@('VISTA PREVIA LISTA','#0C7140')}
        'PARTIAL'          {@('RESULTADO PARCIAL','#995F08')}
        'ERROR'            {@('ERROR · VER INFORME','#A22D34')}
        'MONITORING'       {@('MONITOR ACTIVO','#195CB5')}
        'MONITOR_STOPPING' {@('GUARDANDO REGISTRO','#995F08')}
        'ADMIN_WAIT'       {@('CONFIRMACIÓN PENDIENTE','#995F08')}
        'ADMIN_DONE'       {@('TERMINÓ · SIN VERIFICAR','#995F08')}
        'CANCELLED'        {@('CONSULTA CANCELADA','#52657E')}
    }
    $brush=[Windows.Media.BrushConverter]::new().ConvertFromString([string]$visual[1])
    $ui.ActivityText.Text=$Text
    $ui.TopStatus.Text=[string]$visual[0]
    $ui.TopStatus.Foreground=$brush
    $ui.StatusDot.Fill=$brush
    $ui.ResultTag.Text=[string]$visual[0]
    $ui.ResultTag.Foreground=$brush
    if($State -in @('ERROR','PARTIAL','CANCELLED')){
        $ui.Progress.IsIndeterminate=$false
        $ui.Progress.Value=0
    }elseif($State -eq 'PREVIEW_OK'){
        $ui.Progress.IsIndeterminate=$false
        $ui.Progress.Value=100
    }
}
function PCAD-Refresh {
    $busy=($script:CloseRequested -or $null -ne $script:Child -or $null -ne $script:Admin)
    $ui.BtnPreview.IsEnabled=(!$busy)
    $ui.BtnAudit.IsEnabled=(!$busy)
    $ui.BtnApply.IsEnabled=(!$busy)
    $ui.BtnGenericAutoCAD.IsEnabled=(!$busy)
    $ui.BtnAuditedBlock.IsEnabled=(!$busy -and $null -eq $script:Monitor -and $script:AuditReady)
    $ui.BtnWebRestoreInfo.IsEnabled=(!$busy)
    $ui.BtnRollback.IsEnabled=(!$busy)
    $ui.BtnCancel.IsEnabled=($null -ne $script:Child)
    $ui.BtnMonitor.IsEnabled=(!$busy -and $null -eq $script:Monitor)
    $ui.BtnStopMonitor.IsEnabled=($null -ne $script:Monitor -and !$script:MonitorStopping -and !$script:CloseRequested)
    $ui.BtnExit.IsEnabled=(!$script:CloseRequested)
}
function PCAD-ReportsDir {
    if(!(Test-Path -LiteralPath $script:Reports -PathType Container)){
        $null=New-Item -ItemType Directory -Path $script:Reports -Force -ErrorAction Stop
    }
}
function PCAD-StartChild([string]$Kind){
    if($null -ne $script:Child -or $null -ne $script:Admin){return}
    if($Kind -eq 'AUDIT'){
        $script:AuditReady=$false
        $ui.MetricWeb.Text='—';$ui.MetricProbable.Text='—'
        $ui.TxtWeb.Text='Nuevo análisis en curso. Aún no existe un resultado verificado.'
    }
    $scriptFile=switch($Kind){
        'PREVIEW' {'ParcheCAD.Preview.ps1'}
        'AUDIT' {'ParcheCAD.WebViewAudit.ps1'}
        default {throw 'Tipo de consulta no permitido.'}
    }
    $file=Join-Path $PSScriptRoot $scriptFile
    if(!(Test-Path -LiteralPath $file -PathType Leaf)){throw ('Falta script: '+$scriptFile)}
    PCAD-ReportsDir
    $dir=Join-Path $script:Reports ($Kind.ToLowerInvariant()+'_'+[guid]::NewGuid().ToString('N'))
    $null=New-Item -ItemType Directory -Path $dir -ErrorAction Stop
    $out=Join-Path $dir 'stdout.log'
    $err=Join-Path $dir 'stderr.log'
    $exe=Join-Path $PSHOME 'powershell.exe'
    $args='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -OutputDirectory "{1}"' -f $file,$dir
    $proc=Start-Process -FilePath $exe -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -ErrorAction Stop
    $script:Child=$proc
    $script:ChildType=$Kind
    $script:ChildRoot=$dir
    $script:ChildLog=$out
    $script:ChildErr=$err
    $script:ChildStart=Get-Date
    $ui.Progress.IsIndeterminate=$true
    $ui.Elapsed.Text='00:00'
        if($Kind -eq 'PREVIEW'){
        $ui.WorkTabs.SelectedIndex=0
        $ui.ResultTabs.SelectedIndex=0
        PCAD-Status 'Localizando ejecutables AutoCAD y comprobando reglas, sin modificar Windows...' 'CONSULTING'
    }else{
        $ui.WorkTabs.SelectedIndex=1
        $ui.ResultTabs.SelectedIndex=1
        PCAD-Status 'Analizando WebView2: procesos y conexiones, sin cambios en el firewall...' 'CONSULTING'
    }
    PCAD-Refresh
}
# Gate puro: no usa PID ni parentesco WebView2 como elegibilidad del firewall.
# El informe WebView solo habilita la evaluacion; la segunda lectura del plan
# AutoCAD debe ser completa y vuelve a verificarse en el proceso elevado.
# Validacion estricta de la salida de WebView2 antes de habilitar acciones.
# Ni un estado inesperado ni datos incoherentes habilitan el siguiente paso.
function Test-PCADWebAuditComplete($Data) {
    if($null -eq $Data){return $false}
    if([string]$Data.Schema -cne 'PCAD_WEBVIEW_AUDIT_1' -or
       [string]$Data.Status -cne 'AUDITORIA_WEBVIEW_COMPLETADA' -or
       $Data.ReadOnly -ne $true -or $Data.NoFirewallChanges -ne $true -or
       $Data.IsolationVerified -ne $false -or
       $Data.BlockedTrafficVerified -ne $false -or
       [int]$Data.SafeBlockingCandidates -ne 0){return $false}
    $rows=@($Data.Entries | Where-Object {$null -ne $_})
    $count=[int]$Data.TotalWebView2
    $probable=[int]$Data.ProbableAutoCAD
    $other=[int]$Data.Indeterminate
    if($count -lt 0 -or $count -gt 30000 -or
       $probable -lt 0 -or $other -lt 0 -or
       $rows.Count -ne $count -or $probable+$other -ne $count){return $false}
    foreach($row in $rows){
        if($row.AutomaticFirewallEligible -ne $false -or
           [string]$row.Runtime -cne 'WEBVIEW2_MICROSOFT_COMPARTIDO' -or
           [string]$row.Attribution -notin @('AUTOCAD_PROBABLE','COMPARTIDO_O_INDETERMINADO')){
            return $false
        }
    }
    return $true
}
function Test-PCADAuditedPlan($Data) {
    if($null -eq $Data){return $false}
    return ([string]$Data.Schema -ceq 'PCAD_AUTOCAD_PREVIEW_1' -and
        $Data.ReadOnly -eq $true -and $Data.NoFirewallChanges -eq $true -and
        $Data.WebView2SharedExcluded -eq $true -and
        [string]$Data.Status -ceq 'PREVIEW_COMPLETA' -and
        [string]$Data.CatalogStatus -ceq 'OK' -and
        [string]$Data.PlanState -ceq 'PLAN_NO_APLICADO' -and
        [int]$Data.Candidates -ge 1 -and [int]$Data.Candidates -le 900 -and
        [int]$Data.Conflicts -eq 0)
}
function PCAD-CompleteChild {
    $kind=$script:ChildType
    $root=$script:ChildRoot
    $proc=$script:Child
    if($null -eq $proc){return}
    $code=2
    try {$proc.Refresh();$code=[int]$proc.ExitCode}catch{}
    $proc.Dispose();$script:Child=$null;$script:ChildType=''
    $marker=if($kind -eq 'PREVIEW'){'preview.exitcode'}else{'webview-audit.exitcode'}
    $mark=PCAD-Read (Join-Path $root $marker)
    $reportName=if($kind -eq 'PREVIEW'){'preview.json'}else{'webview-audit.json'}
    $data=$null
    if($code -eq 0 -and $mark -ceq '0'){
        try{$data=Get-Content -LiteralPath (Join-Path $root $reportName) -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop}catch{}
    }
    $ui.Progress.IsIndeterminate=$false
    $ui.Progress.Value=0
    if($kind -eq 'PREVIEW' -and $null -ne $data -and
       $data.Schema -ceq 'PCAD_AUTOCAD_PREVIEW_1' -and $data.ReadOnly -eq $true -and
       $data.NoFirewallChanges -eq $true -and $data.WebView2SharedExcluded -eq $true -and
       $data.Status -in @('PREVIEW_COMPLETA','PREVIEW_PARCIAL') -and
       [int]$data.Candidates -ge 0 -and [int]$data.Conflicts -ge 0){
        $ui.MetricAutoCAD.Text=if(@($data.Years).Count){@($data.Years) -join ', '}else{'0'}
        $ui.MetricRules.Text=[string]$data.Candidates
        $ui.MetricConflicts.Text=([string]$data.Conflicts+' conflictos')
        $ui.TxtFirewall.Text=('Instalaciones: {0} | Candidatas: {1} | Conflictos: {2} | Excluidas: {3}' -f
            $data.Installations,$data.Candidates,$data.Conflicts,$data.Excluded)+[Environment]::NewLine+
            ('Catálogo: '+$data.CatalogStatus)+[Environment]::NewLine+
            'PREVISUALIZACIÓN. Ninguna regla aplicada. WebView2 compartido excluido.'+[Environment]::NewLine+
            ('Informe: '+(Join-Path $root $reportName))
        if($data.Status -eq 'PREVIEW_COMPLETA' -and
           [string]$data.CatalogStatus -ceq 'OK' -and
           [string]$data.PlanState -ceq 'PLAN_NO_APLICADO' -and
           [int]$data.Conflicts -eq 0){
            PCAD-Status 'Análisis de firewall completo. No se modificó el firewall.' 'PREVIEW_OK'
        }else{
            PCAD-Status 'Catálogo AutoCAD parcial. No se aplicó ninguna regla; revisa el informe.' 'PARTIAL'
        }
    }elseif($kind -eq 'AUDIT' -and (Test-PCADWebAuditComplete $data)){
        $ui.MetricWeb.Text=[string]$data.TotalWebView2
        $ui.MetricProbable.Text=[string]$data.ProbableAutoCAD
        $ui.TxtWeb.Text=('WebView2: {0} | AutoCAD probable: {1} | Indeterminados: {2}' -f
            $data.TotalWebView2,$data.ProbableAutoCAD,$data.Indeterminate)+[Environment]::NewLine+
            'Bloqueables automáticamente: 0. Runtime compartido protegido.'+[Environment]::NewLine+
            'Relación padre/PID observacional; no verifica aislamiento ni bloqueo de tráfico.'+[Environment]::NewLine+
            ('Informe: '+(Join-Path $root $reportName))
        $script:AuditReady=$true
        PCAD-Status 'WebView2 analizado. Si deseas, evalúa bloqueo auditado solo de ejecutables AutoCAD.' 'PREVIEW_OK'
    }else{
        if($kind -eq 'AUDIT'){$script:AuditReady=$false}
        PCAD-Status 'No se pudo verificar la consulta. No se aplicaron reglas.' 'ERROR'
        $msg='Resultado incompleto; ver errores locales en: '+$script:ChildErr
        if($kind -eq 'PREVIEW'){$ui.TxtFirewall.Text=$msg}else{$ui.TxtWeb.Text=$msg}
    }
    if($kind -eq 'PREVIEW' -and $script:AuditedApplyPending){
        $script:AuditedApplyPending=$false
        $ui.WorkTabs.SelectedIndex=1
        if(!(Test-PCADAuditedPlan $data)){
            PCAD-Status 'Bloqueo auditado NO elegible: AutoCAD ausente, plan parcial o conflicto. WebView2 permanece intacto.' 'PARTIAL'
            $ui.TxtWeb.Text+=''+[Environment]::NewLine+
                'Bloqueo auditado no autorizado: sin plan AutoCAD completo y libre de conflictos.'
        }else{
            $msg=('Evaluacion completada: {0} ejecutables AutoCAD, 0 conflictos.' -f [int]$data.Candidates)+
                 [Environment]::NewLine+'El analisis WebView2 NO encontro candidatos bloqueables exclusivos: runtime compartido.'+
                 [Environment]::NewLine+'Este boton SOLO bloquea ejecutables AutoCAD del plan que el motor elevado revalidara.'+
                 [Environment]::NewLine+'Puede afectar funciones y comprobaciones de licencia. Requiere UAC y escribir APLICAR.'+
                 [Environment]::NewLine+'¿Deseas continuar con el bloqueo de ejecutables AutoCAD?'
            if([Windows.MessageBox]::Show($msg,'Bloqueo auditado AutoCAD','YesNo','Warning') -eq 'Yes'){
                try{PCAD-StartAdmin 'Apply'}catch{
                    PCAD-Status ('No se pudo iniciar operacion elevada: '+$_.Exception.Message) 'ERROR'
                }
            }else{
                PCAD-Status 'Evaluacion auditada terminada. Bloqueo cancelado; no se modificaron reglas.' 'IDLE'
            }
        }
    }
    PCAD-Refresh
}
function PCAD-CancelChild {
    if($null -eq $script:Child){return}
    $p=$script:Child
    try {
        $p.Refresh()
        if(!$p.HasExited){
            $p.Kill()
            if(!$p.WaitForExit(5000)){throw 'El proceso de consulta no finalizó.'}
        }
        $p.Dispose()
        if($script:ChildType -eq 'AUDIT'){$script:AuditReady=$false}
        $script:Child=$null;$script:ChildType=''
        $script:AuditedApplyPending=$false
        PCAD-Status 'Consulta cancelada. No se modificó el firewall.' 'CANCELLED'
    }catch {
        PCAD-Status ('No se pudo detener la consulta: '+$_.Exception.Message) 'ERROR'
    }
    PCAD-Refresh
}
function PCAD-StartMonitor {
    if($null -ne $script:Monitor -or $null -ne $script:Child -or $null -ne $script:Admin){return}
    $path=Join-Path $PSScriptRoot 'ParcheCAD.Monitor.ps1'
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Falta monitor.'}
    PCAD-ReportsDir
    $folder=Join-Path $script:Reports ('monitor_'+[guid]::NewGuid().ToString('N'))
    $stdout=$folder+'.stdout.log'
    $stderr=$folder+'.stderr.log'
    $args='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -OutputDirectory "{1}" -DurationSeconds 600 -IntervalMilliseconds 1000' -f $path,$folder
    $p=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -ErrorAction Stop
    $script:Monitor=$p;$script:MonitorRoot=$folder;$script:MonitorStopping=$false;$script:MonitorStart=Get-Date
    $ui.WorkTabs.SelectedIndex=1
    $ui.ResultTabs.SelectedIndex=2
    $ui.MonitorHint.Text='Monitor activo · TCP/UDP observacionales · máx. 10 min'
    PCAD-Status 'Monitor activo. Prueba AutoCAD; detén para guardar el informe.' 'MONITORING'
    PCAD-Refresh
}
function PCAD-StopMonitor {
    if($null -eq $script:Monitor -or $script:MonitorStopping){return}
    if(!(Test-Path -LiteralPath $script:MonitorRoot -PathType Container)){
        PCAD-Status 'Monitor iniciando. Se solicitará detener al crearse la sesión.' 'MONITOR_STOPPING'
        return
    }
    [IO.File]::WriteAllText((Join-Path $script:MonitorRoot 'detener.solicitud'),'stop',([Text.UTF8Encoding]::new($false)))
    $script:MonitorStopping=$true
    PCAD-Status 'Deteniendo monitor de forma segura y guardando el registro...' 'MONITOR_STOPPING'
    PCAD-Refresh
}
function PCAD-CompleteMonitor {
    $p=$script:Monitor
    if($null -eq $p){return}
    $code=2
    try{$p.Refresh();$code=[int]$p.ExitCode}catch{}
    $p.Dispose();$script:Monitor=$null;$script:MonitorStopping=$false
    $path=Join-Path $script:MonitorRoot 'monitor.json'
    $mark=PCAD-Read (Join-Path $script:MonitorRoot 'monitor.exitcode')
    $data=$null
    if($code -eq 0 -and $mark -ceq '0'){
        try{$data=Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop}catch{}
    }
    if($null -ne $data -and $data.Schema -ceq 'PCAD_MONITOR_1' -and
       [string]$data.Result -ceq 'MONITOREO_COMPLETADO_OBSERVACIONAL' -and
       [string]$data.StopReason -in @('USUARIO','DURACION_MAXIMA') -and
       [int]$data.Samples -ge 0 -and
       $data.ReadOnly -eq $true -and $data.BlockedTrafficVerified -eq $false -and
       $data.WebViewIsolationVerified -eq $false){
        $ui.TxtMonitor.Text=('Muestras: {0} | Eventos: {1} | TCP: {2} | UDP: {3}' -f
            $data.Samples,@($data.Events).Count,$data.ConnectionEventsTcp,$data.UdpEndpointsObserved)+[Environment]::NewLine+
            'Observación probable; ninguna ausencia de tráfico certificada.'+[Environment]::NewLine+('Informe: '+$path)
        $ui.MonitorHint.Text='Monitor finalizado · informe guardado'
        PCAD-Status 'Monitor finalizado y registro guardado. No certifica bloqueo.' 'IDLE'
    }else{
        $ui.TxtMonitor.Text='Monitor parcial. Revisar archivos de informe; no se certifica ausencia de conexiones.'
        PCAD-Status 'Monitor terminó con resultado parcial o error.' 'PARTIAL'
    }
    PCAD-Refresh
    if($script:CloseRequested -and $null -eq $script:Monitor -and
       $null -eq $script:Admin -and !$script:CloseQueued){
        $script:CloseQueued=$true
        # No invocar Close dentro de Closing/Tick antes de soltar el handle.
        $null=$window.Dispatcher.BeginInvoke([Action]{ $window.Close() })
    }
}
function PCAD-StartAdmin([ValidateSet('Apply','Rollback','RestoreFirewall','RestoreWebView2')][string]$Mode,[string]$Manifest=''){
    if($null -ne $script:Child -or $null -ne $script:Admin){return}
    $engine=Join-Path $PSScriptRoot 'ParcheCAD.Reglas.ps1'
    if(!(Test-Path -LiteralPath $engine -PathType Leaf)){throw 'No se encontró motor de reglas.'}
    $args='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode {1} -ConfirmChange' -f $engine,$Mode
    if($Mode -eq 'Rollback'){$args+=' -Manifest "'+$Manifest+'"'}
    if($Mode -in @('RestoreFirewall','RestoreWebView2')){$args+=' -InteractivePause'}
    $proc=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args -Verb RunAs -PassThru -ErrorAction Stop
    $script:Admin=$proc;$script:AdminStart=Get-Date;$script:AdminMode=$Mode
    PCAD-Status 'Analizando reglas del sistema. Confirma cualquier restauracion en la consola elevada.' 'ADMIN_WAIT'
    PCAD-Refresh
}

$ui.BtnPreview.Add_Click({try{PCAD-StartChild 'PREVIEW'}catch{[Windows.MessageBox]::Show($_.Exception.Message,'Analizar firewall')|Out-Null}})
$ui.BtnAudit.Add_Click({try{PCAD-StartChild 'AUDIT'}catch{[Windows.MessageBox]::Show($_.Exception.Message,'WebView2')|Out-Null}})
$ui.BtnAuditedBlock.Add_Click({
    if(!$script:AuditReady -or $null -ne $script:Child -or
       $null -ne $script:Admin -or $null -ne $script:Monitor -or $script:CloseRequested){return}
    $script:AuditedApplyPending=$true
    try{
        PCAD-StartChild 'PREVIEW'
    }catch{
        $script:AuditedApplyPending=$false
        [Windows.MessageBox]::Show('No se pudo evaluar el plan AutoCAD: '+$_.Exception.Message,
            'Bloqueo auditado')|Out-Null
    }
})
$ui.BtnMonitor.Add_Click({
    $warning='El monitor observa conexiones y procesos; no verifica ausencia absoluta de tráfico. Iniciar ahora?'
    if([Windows.MessageBox]::Show($warning,'Monitor WebView2','YesNo','Information') -eq 'Yes'){
        try{PCAD-StartMonitor}catch{[Windows.MessageBox]::Show($_.Exception.Message,'Monitor')|Out-Null}
    }
})
$ui.BtnStopMonitor.Add_Click({try{PCAD-StopMonitor}catch{[Windows.MessageBox]::Show($_.Exception.Message,'Monitor')|Out-Null}})
$ui.BtnCancel.Add_Click({PCAD-CancelChild})
$ui.BtnReports.Add_Click({
    if(Test-Path -LiteralPath $script:Reports -PathType Container){
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"'+$script:Reports+'"')
    }else{[Windows.MessageBox]::Show('Aún no hay informes.','ParcheCAD')|Out-Null}
})
function PCAD-ConfirmAutoCADBlock {
    # Una sola operacion elevada para ambos accesos: NO analizador ni reglas WebView2.
    if($null -ne $script:Child -or $null -ne $script:Admin -or $script:CloseRequested){return}
    $msg='BLOQUEO GENERAL SOLO AUTOCAD: el motor verificará rutas, conflictos y respaldos antes de aplicar.'+
         [Environment]::NewLine+'No necesitas analizar WebView2. NO bloqueará el runtime Microsoft compartido.'+
         [Environment]::NewLine+'Puede afectar funciones online y comprobaciones de licencia de AutoCAD.'+
         [Environment]::NewLine+'Se solicitará UAC y escribir APLICAR. ¿Deseas continuar?'
    if([Windows.MessageBox]::Show($msg,'Bloqueo general AutoCAD','YesNo','Warning') -eq 'Yes'){
        try{PCAD-StartAdmin 'Apply'}catch{[Windows.MessageBox]::Show($_.Exception.Message,'Permisos de administrador')|Out-Null}
    }
}
$ui.BtnApply.Add_Click({PCAD-ConfirmAutoCADBlock})
$ui.BtnGenericAutoCAD.Add_Click({PCAD-ConfirmAutoCADBlock})
$ui.BtnWebRestoreInfo.Add_Click({
    $msg='RESTAURAR WEBVIEW2 AUTODESK: busca reglas historicas con ID/nombre vinculado a Autodesk y filtro msedgewebview2.exe.'+
         [Environment]::NewLine+'No muestra ni elimina bloqueos WebView2 generales o de otras aplicaciones.'+
         [Environment]::NewLine+'La vinculacion del nombre NO demuestra aislamiento: quitar una regla global puede afectar otras apps que compartan WebView2.'+
         [Environment]::NewLine+'Debes escoger una regla por su NOMBRE exacto.'+
         [Environment]::NewLine+'Antes de retirar una regla creara una copia de la politica en ProgramData. Continuar?'
    if([Windows.MessageBox]::Show($msg,'Restaurar WebView2','YesNo','Warning') -eq 'Yes'){
        try{PCAD-StartAdmin 'RestoreWebView2'}catch{[Windows.MessageBox]::Show($_.Exception.Message,'Restaurar WebView2')|Out-Null}
    }
})
$ui.BtnRollback.Add_Click({
    $msg='RESTAURAR FIREWALL: analiza bloqueos activos de ejecutables AutoCAD en Windows Firewall.'+
         [Environment]::NewLine+'Puede restaurar reglas PCAD4 verificadas aunque borraste la carpeta o los informes.'+
         [Environment]::NewLine+'Otros bloqueos AutoCAD se muestran y exigen seleccion individual y confirmacion.'+
         [Environment]::NewLine+'Se guarda una copia independiente en ProgramData antes de cualquier eliminacion. Continuar?'
    if([Windows.MessageBox]::Show($msg,'Restaurar Firewall AutoCAD','YesNo','Warning') -eq 'Yes'){
        try{PCAD-StartAdmin 'RestoreFirewall'}catch{[Windows.MessageBox]::Show($_.Exception.Message,'Restaurar Firewall')|Out-Null}
    }
})
$ui.BtnExit.Add_Click({$window.Close()})
$timer=[Windows.Threading.DispatcherTimer]::new()
$timer.Interval=[TimeSpan]::FromMilliseconds(400)
$timer.Add_Tick({
    try{
        $active=$null
        if($null -ne $script:Child){$active=$script:ChildStart}
        elseif($null -ne $script:Admin){$active=$script:AdminStart}
        elseif($null -ne $script:Monitor){$active=$script:MonitorStart}
        if($null -ne $active){
            $span=(Get-Date)-$active
            $ui.Elapsed.Text=('{0:00}:{1:00}' -f [int]$span.TotalMinutes,$span.Seconds)
        }
        if($null -ne $script:Child){
            $p=$script:Child
            $p.Refresh()
            if($p.HasExited){PCAD-CompleteChild}
            elseif($script:ChildType -eq 'PREVIEW'){
                $stage=PCAD-Read (Join-Path $script:ChildRoot 'preview.fase.txt')
                if($stage){$ui.ActivityText.Text=$stage+' · consulta en curso (sin cambios)'}
            }
        }
        if($null -ne $script:Admin){
            $p=$script:Admin;$p.Refresh()
            if($p.HasExited){
                $code=2;try{$code=[int]$p.ExitCode}catch{}
                $p.Dispose();$script:Admin=$null
                $notice=if($script:AdminMode -in @('RestoreFirewall','RestoreWebView2')){
                    if($code -eq 0){'Restauracion terminada en consola. Verifica reglas, journal y copia en ProgramData.'}
                    else{'Restauracion cancelada, parcial o fallida; consulta consola y journal. No asumir reparacion.'}
                }elseif($code -eq 0){
                    'El proceso administrativo terminó (código 0). Aún debes verificar las reglas y el respaldo.'
                }else{
                    ('Operación no verificada (código '+$code+'). Consulta la consola y el informe; no se presupone bloqueo.')
                }
                $ui.TxtFirewall.Text=$notice+[Environment]::NewLine+
                    'Abre informes para revisar el journal de esta operación.'
                $ui.WorkTabs.SelectedIndex=0
                $ui.ResultTabs.SelectedIndex=0
                PCAD-Status $notice $(if($code -eq 0){'ADMIN_DONE'}else{'ERROR'})
                PCAD-Refresh
            }
        }
        if($null -ne $script:Monitor){
            $p=$script:Monitor;$p.Refresh()
            if($p.HasExited){PCAD-CompleteMonitor}
            elseif($script:CloseRequested -and !$script:MonitorStopping){
                # Si el monitor aun creaba la carpeta, reintenta la señal con cada tick.
                try{PCAD-StopMonitor}catch{
                    PCAD-Status ('No se pudo solicitar la parada: '+$_.Exception.Message) 'ERROR'
                }
            }
        }
    }catch {
        PCAD-Status ('Error de seguimiento: '+$_.Exception.GetType().Name) 'ERROR'
    }
})
$window.Add_Closing({
    param($sender,$args)
    if($script:ShuttingDown){return}
    if($null -ne $script:Admin){
        $script:Admin.Refresh()
        if(!$script:Admin.HasExited){
            $args.Cancel=$true
            PCAD-Status 'La operación elevada continúa. Espera su finalización.' 'ADMIN_WAIT'
            return
        }
    }
    if($null -ne $script:Monitor){
        $script:Monitor.Refresh()
        if($script:Monitor.HasExited){
            PCAD-CompleteMonitor
        }else{
            $args.Cancel=$true
            $script:CloseRequested=$true
            try{PCAD-StopMonitor}catch{
                PCAD-Status ('No se pudo solicitar el cierre seguro: '+$_.Exception.Message) 'ERROR'
            }
            if($script:MonitorStopping){
                PCAD-Status 'Cerrando cuando el monitor guarde el informe...' 'MONITOR_STOPPING'
            }
            PCAD-Refresh
            return
        }
    }
    if($null -ne $script:Child){
        PCAD-CancelChild
        if($null -ne $script:Child){$args.Cancel=$true;return}
    }
    $script:ShuttingDown=$true
    $timer.Stop()
})
if($StateSelfTest){
    $expected=@{
        IDLE='LISTO';CONSULTING='CONSULTANDO';PREVIEW_OK='VISTA PREVIA';
        PARTIAL='PARCIAL';ERROR='ERROR';MONITORING='MONITOR';
        MONITOR_STOPPING='GUARDANDO';ADMIN_WAIT='CONFIRMACIÓN';
        ADMIN_DONE='SIN VERIFICAR';CANCELLED='CANCELADA'
    }
    foreach($state in @($expected.Keys)){
        PCAD-Status ('Prueba '+$state) $state
        if($ui.TopStatus.Text -notmatch $expected[$state] -or
           $ui.ResultTag.Text -cne $ui.TopStatus.Text -or
           $ui.StatusDot.Fill.Color -ne $ui.TopStatus.Foreground.Color){
            throw ('V43 Lote B: estado visual inconsistente '+$state)
        }
    }
    PCAD-Status 'Prueba parcial' 'PARTIAL'
    if($ui.Progress.Value -ne 0 -or $ui.Progress.IsIndeterminate){throw 'V43 Lote B: resultado parcial aparece completo'}
    PCAD-Status 'Prueba exitosa' 'PREVIEW_OK'
    if($ui.Progress.Value -ne 100){throw 'V43 Lote B: estado exitoso sin progreso final'}
    PCAD-Refresh
    if(!$ui.BtnApply.IsEnabled -or !$ui.BtnRollback.IsEnabled -or !$ui.BtnWebRestoreInfo.IsEnabled -or !$ui.BtnGenericAutoCAD.IsEnabled -or $ui.BtnAuditedBlock.IsEnabled -or $ui.BtnCancel.IsEnabled){throw 'V43: controles de inicio inconsistentes'}
    $script:AuditReady=$true;PCAD-Refresh
    if(!$ui.BtnAuditedBlock.IsEnabled){throw 'V43: no habilita evaluacion tras auditoria valida'}
    $script:CloseRequested=$true;PCAD-Refresh
    if($ui.BtnApply.IsEnabled -or $ui.BtnGenericAutoCAD.IsEnabled -or $ui.BtnAuditedBlock.IsEnabled -or $ui.BtnWebRestoreInfo.IsEnabled -or $ui.BtnPreview.IsEnabled -or $ui.BtnExit.IsEnabled){throw 'V43: no bloquea acciones al cerrar'}
    $script:AuditReady=$false
    $script:CloseRequested=$false
    $valid=[pscustomobject]@{
        Schema='PCAD_AUTOCAD_PREVIEW_1';ReadOnly=$true;NoFirewallChanges=$true
        WebView2SharedExcluded=$true;Status='PREVIEW_COMPLETA';CatalogStatus='OK'
        PlanState='PLAN_NO_APLICADO';Candidates=2;Conflicts=0
    }
    if(!(Test-PCADAuditedPlan $valid)){throw 'V43: rechaza plan sintético elegible'}
    $valid.Conflicts=1
    if(Test-PCADAuditedPlan $valid){throw 'V43: acepta plan con conflicto'}
    $valid.Conflicts=0;$valid.WebView2SharedExcluded=$false
    if(Test-PCADAuditedPlan $valid){throw 'V43: acepta bloquear WebView2 compartido'}
    $valid.WebView2SharedExcluded=$true;$valid.Status='PREVIEW_PARCIAL'
    if(Test-PCADAuditedPlan $valid){throw 'V43: acepta plan parcial'}
    $auditValid=[pscustomobject]@{
        Schema='PCAD_WEBVIEW_AUDIT_1';Status='AUDITORIA_WEBVIEW_COMPLETADA'
        ReadOnly=$true;NoFirewallChanges=$true;IsolationVerified=$false
        BlockedTrafficVerified=$false;SafeBlockingCandidates=0
        TotalWebView2=0;ProbableAutoCAD=0;Indeterminate=0;Entries=@()
    }
    if(!(Test-PCADWebAuditComplete $auditValid)){throw 'AUDIT10: valid empty WebView audit refused'}
    $auditValid.Status='PARCIAL'
    if(Test-PCADWebAuditComplete $auditValid){throw 'AUDIT10: partial WebView audit accepted'}
    $auditValid.Status='AUDITORIA_WEBVIEW_COMPLETADA';$auditValid.TotalWebView2=1
    if(Test-PCADWebAuditComplete $auditValid){throw 'AUDIT10: WebView audit counts inconsistent'}
    $auditValid.TotalWebView2=0;$auditValid.SafeBlockingCandidates=1
    if(Test-PCADWebAuditComplete $auditValid){throw 'AUDIT10: shared WebView2 marked blockable'}
    $window.Close()
    Write-Host 'PASS V43 external AUDIT10: states, negative WebView audit fixtures, plan gates, close behavior.'
    exit 0
}
PCAD-Status 'Listo para consultar AutoCAD y WebView2, sin modificar el firewall.' 'IDLE'
PCAD-Refresh
$timer.Start()
$null=$window.ShowDialog()
