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
$script:AdminMode=''
$script:AdminOperationId=''
$script:AdminProgressFile=''
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
                     'MONITORING','MONITOR_STOPPING','ADMIN_WAIT','ADMIN_DONE','CANCELLED',
                     'ADMIN_PREPARING','APPLYING','VERIFYING','RULES_VERIFIED','NOT_APPLIED')]
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
        'ADMIN_PREPARING' {@('PREPARANDO REGLAS','#195CB5')}
        'APPLYING'         {@('APLICANDO REGLAS','#195CB5')}
        'VERIFYING'        {@('VERIFICANDO REGLAS','#195CB5')}
        'RULES_VERIFIED'   {@('REGLAS VERIFICADAS','#0C7140')}
        'NOT_APPLIED'      {@('SIN REGLAS APLICADAS','#995F08')}
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
    }elseif($State -in @('PREVIEW_OK','RULES_VERIFIED')){
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
# Un solo boton Informes: directorio verdadero de la ultima operacion.
function PCAD-CurrentReportFolder {
    if($script:AdminMode -in @('RestoreFirewall','RestoreWebView2')){
        return (Join-Path $env:ProgramData 'ParcheCAD\Recovery')
    }
    if($script:AdminMode -in @('Apply','Rollback')){
        return (Join-Path $env:ProgramData 'ParcheCAD\Operations')
    }
    return $script:Reports
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
    $script:AdminMode=''
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
        $total=[int]$data.Candidates
        $installed=[int]$data.InstalledValid
        $missing=[int]$data.MissingRules
        $unverified=[int]$data.UnverifiedRules
        $countsOK=($total -ge 0 -and $total -le 900 -and
            $installed -ge 0 -and $missing -ge 0 -and $unverified -ge 0 -and
            $installed+$missing+$unverified -eq $total)
        $ui.MetricAutoCAD.Text=if(@($data.Years).Count){@($data.Years) -join ', '}else{'0'}
        $ui.MetricRules.Text=('{0}/{1}' -f $installed,$total)
        $ui.MetricConflicts.Text=('{0} faltantes · {1} sin verificar' -f $missing,$unverified)
        $ui.TxtFirewall.Text=('INSTALADAS Y VERIFICADAS LOCALMENTE: {0}/{1}' -f $installed,$total)+[Environment]::NewLine+
            ('Faltantes: {0} | Conflictos/sin verificar: {1} | Excluidas: {2}' -f $missing,$unverified,$data.Excluded)+[Environment]::NewLine+
            ('Estado de reglas: '+$data.RuleVerificationState+' | Catálogo: '+$data.CatalogStatus)+[Environment]::NewLine+
            'ANÁLISIS SOLO LECTURA: no aplicó cambios. Reglas locales NO garantizan aislamiento del tráfico.'+[Environment]::NewLine+
            ('Informe: '+(Join-Path $root $reportName))
        if(!$countsOK){
            PCAD-Status 'Informe incoherente: no se puede determinar el estado de las reglas.' 'ERROR'
        }elseif($data.Status -ne 'PREVIEW_COMPLETA' -or $data.CatalogStatus -ne 'OK' -or $unverified -gt 0){
            PCAD-Status ('Análisis incompleto: {0}/{1} reglas verificadas; revisar conflictos.' -f $installed,$total) 'PARTIAL'
        }elseif($total -gt 0 -and $installed -eq $total -and [string]$data.RuleVerificationState -ceq 'TODAS_VERIFICADAS'){
            PCAD-Status ('FIREWALL APLICADO Y VERIFICADO LOCALMENTE: {0}/{1} reglas. Tráfico real no certificado.' -f $installed,$total) 'RULES_VERIFIED'
        }elseif($installed -eq 0 -and $unverified -eq 0){
            PCAD-Status ('SIN REGLAS APLICADAS: 0/{0} válidas; hay {1} candidatas pendientes.' -f $total,$missing) 'NOT_APPLIED'
        }else{
            PCAD-Status ('FIREWALL PARCIAL: {0}/{1} reglas verificadas, {2} faltantes.' -f $installed,$total,$missing) 'PARTIAL'
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
            # La consola elevada muestra riesgos y pide APLICAR una sola vez.
            try{PCAD-StartAdmin 'Apply'}catch{
                PCAD-Status ('No se pudo iniciar operacion elevada: '+$_.Exception.Message) 'ERROR'
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
    $script:AdminMode=''
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
# Un journal APPLIED solo acredita verificaciones locales hechas por el motor
# elevado. El codigo de salida 0 o un total de "candidatas" no bastan.
function Test-PCADApplyReceipt($Data,[string]$Id) {
    if($null -eq $Data -or $Id -cnotmatch '^[a-f0-9]{32}$'){return $null}
    if([string]$Data.Schema -cne 'PCAD4_OPERATION_1' -or
       [string]$Data.OperationId -cne $Id -or
       [string]$Data.Status -cne 'APPLIED' -or
       [string]::IsNullOrWhiteSpace([string]$Data.FinishedAt)){return $null}
    $entries=@($Data.Operations)
    if($entries.Count -lt 1 -or $entries.Count -gt 900){return $null}
    $names=@{}
    $created=0
    foreach($entry in $entries){
        $name=[string]$entry.RuleName
        if($name -cnotmatch '^PCAD4_A_[0-9A-F]{24}_OUT$' -or
           [string]$entry.Group -cne 'PCAD4_MANAGED' -or
           $names.ContainsKey($name) -or
           [string]$entry.State -cnotin @('CREATED','ALREADY_PRESENT')){
            return $null
        }
        $names[$name]=$true
        if([string]$entry.State -ceq 'CREATED'){$created++}
    }
    return [pscustomobject]@{
        Verified=$entries.Count;Created=$created;AlreadyPresent=($entries.Count-$created)
    }
}
function PCAD-ReadApplyReceipt([string]$Id) {
    if($Id -cnotmatch '^[a-f0-9]{32}$'){return $null}
    $path=Join-Path (Join-Path $env:ProgramData 'ParcheCAD\Operations') ('PCAD4_'+$Id+'.json')
    try{
        $data=Get-Content -LiteralPath $path -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
        $verified=Test-PCADApplyReceipt -Data $data -Id $Id
        if($null -eq $verified){return $null}
        return [pscustomobject]@{
            Verified=$verified.Verified;Created=$verified.Created
            AlreadyPresent=$verified.AlreadyPresent;Journal=$path
        }
    }catch{return $null}
}
function PCAD-TrackApplyProgress {
    if(!$script:AdminProgressFile){return}
    $data=$null
    try{$data=Get-Content -LiteralPath $script:AdminProgressFile -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop}catch{return}
    if([string]$data.Schema -cne 'PCAD4_APPLY_PROGRESS_1'){return}
    $done=[int]$data.Completed;$total=[int]$data.Total
    if($done -lt 0 -or $total -lt 0 -or $total -gt 900 -or ($total -gt 0 -and $done -gt $total)){return}
    switch([string]$data.Stage){
        'DISCOVERY' { $ui.Progress.IsIndeterminate=$true
            PCAD-Status 'Etapa 1/3: buscando instalaciones y verificando archivos AutoCAD...' 'ADMIN_PREPARING' }
        'CATALOG' { $ui.Progress.IsIndeterminate=$true
            PCAD-Status 'Etapa 2/3: recorriendo ejecutables AutoCAD; puede tardar varios minutos...' 'ADMIN_PREPARING' }
        'RULES' { $ui.Progress.IsIndeterminate=$true
            PCAD-Status 'Etapa 3/3: comprobando reglas y filtros existentes...' 'ADMIN_PREPARING' }
        'AWAIT_CONFIRM' { $ui.Progress.IsIndeterminate=$false;$ui.Progress.Value=0
            PCAD-Status 'Esperando APLICAR en la consola elevada. Ninguna regla nueva creada todavía.' 'ADMIN_WAIT' }
        'APPLY' { $ui.Progress.IsIndeterminate=$false
            if($total -gt 0){$ui.Progress.Value=[int](100*$done/$total)}
            PCAD-Status ('Creando o verificando reglas AutoCAD: {0}/{1}. No cierres el proceso.' -f $done,$total) 'APPLYING' }
        'VERIFYING' { $ui.Progress.IsIndeterminate=$true
            PCAD-Status ('Verificación final de {0} reglas locales en Windows Firewall...' -f $total) 'VERIFYING' }
    }
}
function PCAD-StartAdmin([ValidateSet('Apply','Rollback','RestoreFirewall','RestoreWebView2')][string]$Mode,[string]$Manifest=''){
    if($null -ne $script:Child -or $null -ne $script:Admin){return}
    $engine=Join-Path $PSScriptRoot 'ParcheCAD.Reglas.ps1'
    if(!(Test-Path -LiteralPath $engine -PathType Leaf)){throw 'No se encontró motor de reglas.'}
    $args='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode {1} -ConfirmChange' -f $engine,$Mode
    $id=''
    $progress=''
    if($Mode -eq 'Apply'){
        $id=[guid]::NewGuid().ToString('N')
        $progress=Join-Path (Join-Path $env:ProgramData 'ParcheCAD\Operations') ('PCAD4_PROGRESS_'+$id+'.json')
        $args+=' -OperationId '+$id
    }
    if($Mode -eq 'Rollback'){$args+=' -Manifest "'+$Manifest+'"'}
    if($Mode -in @('RestoreFirewall','RestoreWebView2')){$args+=' -InteractivePause'}
    $proc=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args -Verb RunAs -PassThru -ErrorAction Stop
    $script:Admin=$proc;$script:AdminStart=Get-Date;$script:AdminMode=$Mode
    $script:AdminOperationId=$id
    $script:AdminProgressFile=$progress
    $ui.Elapsed.Text='00:00'
    $ui.Progress.Value=0;$ui.Progress.IsIndeterminate=$true
    if($Mode -eq 'Apply'){
        PCAD-Status 'Etapa 1/3: preparando análisis AutoCAD. La única confirmación será escribir APLICAR en la consola.' 'ADMIN_PREPARING'
    }else{
        PCAD-Status 'Abriendo restauración. Revisa las reglas y confirma en la consola elevada.' 'ADMIN_WAIT'
    }
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
    $target=PCAD-CurrentReportFolder
    if(Test-Path -LiteralPath $target -PathType Container){
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"'+$target+'"')
    }else{[Windows.MessageBox]::Show('Aún no hay informes en '+$target,'ParcheCAD')|Out-Null}
})
function PCAD-ConfirmAutoCADBlock {
    # Una sola operacion elevada para ambos accesos: NO analizador ni reglas WebView2.
    if($null -ne $script:Child -or $null -ne $script:Admin -or $script:CloseRequested){return}
    # Una sola confirmacion escrita en el motor elevado; sin segundo dialogo.
    # UAC autoriza elevar, no sustituye la confirmacion APLICAR.
    try{PCAD-StartAdmin 'Apply'}catch{[Windows.MessageBox]::Show($_.Exception.Message,'Permisos de administrador')|Out-Null}
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
            if(!$p.HasExited -and $script:AdminMode -eq 'Apply'){PCAD-TrackApplyProgress}
            if($p.HasExited){
                $code=2;try{$code=[int]$p.ExitCode}catch{}
                $p.Dispose();$script:Admin=$null
                $notice=if($script:AdminMode -in @('RestoreFirewall','RestoreWebView2')){
                    if($code -eq 0){'El asistente de restauracion termino. Puede no haber quitado reglas; verifica el journal en ProgramData.'}
                    else{'Restauracion cancelada, parcial o fallida; consulta consola y journal. No asumir reparacion.'}
                }elseif($script:AdminMode -eq 'Apply'){
                    $receipt=if($code -eq 0){PCAD-ReadApplyReceipt $script:AdminOperationId}else{$null}
                    if($null -ne $receipt){
                        $ui.MetricRules.Text=('{0}/{0}' -f $receipt.Verified)
                        $ui.MetricConflicts.Text='0 conflictos · reglas locales verificadas'
                        $ui.Progress.IsIndeterminate=$false;$ui.Progress.Value=100
                        $notice=('APLICADO Y VERIFICADO LOCALMENTE: {0}/{0} reglas. Nuevas: {1}; ya existentes: {2}. Tráfico real NO certificado.' -f $receipt.Verified,$receipt.Created,$receipt.AlreadyPresent)
                        $ui.TxtFirewall.Text=$notice+[Environment]::NewLine+'Respaldo: '+$receipt.Journal
                        PCAD-Status $notice 'RULES_VERIFIED'
                    }else{
                        $notice='Aplicación no acreditada: resultado final o respaldo no verificable; puede haber reglas creadas. Ejecuta ANALIZAR FIREWALL antes de cualquier otra acción.'
                        $ui.Progress.IsIndeterminate=$false;$ui.Progress.Value=0
                        $ui.TxtFirewall.Text=$notice+[Environment]::NewLine+
                            ('Informes: '+(PCAD-CurrentReportFolder))
                        PCAD-Status $notice 'PARTIAL'
                    }
                }else{
                    $notice=('Operación no verificada (código '+$code+'). Revisa consola e informes.')
                }
                if($script:AdminMode -ne 'Apply'){
                    $ui.TxtFirewall.Text=$notice+[Environment]::NewLine+
                        ('Directorio del informe: '+(PCAD-CurrentReportFolder))
                    PCAD-Status $notice $(if($code -eq 0){'ADMIN_DONE'}else{'ERROR'})
                }
                $ui.WorkTabs.SelectedIndex=0
                $ui.ResultTabs.SelectedIndex=0
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
        ADMIN_DONE='SIN VERIFICAR';CANCELLED='CANCELADA';
        ADMIN_PREPARING='PREPARANDO';APPLYING='APLICANDO';VERIFYING='VERIFICANDO';
        RULES_VERIFIED='VERIFICADAS';NOT_APPLIED='SIN REGLAS'
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
    $script:AdminMode='RestoreFirewall'
    if((PCAD-CurrentReportFolder) -notlike '*ParcheCAD*Recovery'){throw 'AUDIT10: recovery folder wrong'}
    $script:AdminMode='Apply'
    if((PCAD-CurrentReportFolder) -notlike '*ParcheCAD*Operations'){throw 'AUDIT10: apply folder wrong'}
    $script:AdminMode=''
    if((PCAD-CurrentReportFolder) -ne $script:Reports){throw 'AUDIT10: read-only reports folder wrong'}
    $sampleId=[guid]::NewGuid().ToString('N')
    $sample=[pscustomobject]@{
        Schema='PCAD4_OPERATION_1';OperationId=$sampleId
        Status='APPLIED';FinishedAt=(Get-Date).ToString('o')
        Operations=@(
            [pscustomobject]@{RuleName=('PCAD4_A_'+('A'*24)+'_OUT');Group='PCAD4_MANAGED';State='CREATED'},
            [pscustomobject]@{RuleName=('PCAD4_A_'+('B'*24)+'_OUT');Group='PCAD4_MANAGED';State='ALREADY_PRESENT'}
        )
    }
    $receipt=Test-PCADApplyReceipt -Data $sample -Id $sampleId
    if($null -eq $receipt -or $receipt.Verified -ne 2 -or
       $receipt.Created -ne 1 -or $receipt.AlreadyPresent -ne 1){
        throw 'QA: valid Apply receipt not recognized'
    }
    $sample.Status='ERROR_PARTIAL'
    if($null -ne (Test-PCADApplyReceipt -Data $sample -Id $sampleId)){
        throw 'QA: partial journal incorrectly claimed applied'
    }
    $sample.Status='APPLIED';$sample.Operations[1].State='PENDING'
    if($null -ne (Test-PCADApplyReceipt -Data $sample -Id $sampleId)){
        throw 'QA: pending operation falsely verified'
    }
    $sample.Operations[1].State='CREATED';$sample.Operations[1].RuleName=$sample.Operations[0].RuleName
    if($null -ne (Test-PCADApplyReceipt -Data $sample -Id $sampleId)){
        throw 'QA: duplicate rule IDs accepted'
    }
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
