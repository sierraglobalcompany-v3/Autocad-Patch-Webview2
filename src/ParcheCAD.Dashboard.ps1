# ParcheCAD 4.3 - WPF frontend only. CLI firewall/audit/monitor engines unchanged.
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$SelfTest)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase -ErrorAction Stop
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop

$xaml=Join-Path $PSScriptRoot 'ParcheCAD.Dashboard.xaml'
if(!(Test-Path -LiteralPath $xaml -PathType Leaf)){throw 'Falta el layout WPF.'}
$reader=[Xml.XmlReader]::Create($xaml)
try {$window=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
$names=@('MainWindow','MetricAutoCAD','MetricRules','MetricConflicts',
 'MetricWeb','MetricProbable','TopStatus','StatusDot','FirewallHint','MonitorHint',
 'BtnPreview','BtnApply','BtnRollback','BtnAudit','BtnMonitor','BtnStopMonitor',
 'BtnReports','BtnCancel','BtnExit','ActivityText','Elapsed','Progress',
 'TxtFirewall','TxtWeb','TxtMonitor','ResultTabs','ResultTag')
$ui=@{}
foreach($name in $names){
    $c=$window.FindName($name)
    if($null -eq $c){throw ('WPF incompleto: '+$name)}
    $ui[$name]=$c
}
if($SelfTest){
    if($ui.BtnStopMonitor.IsEnabled -or $ui.BtnCancel.IsEnabled){throw 'WPF: dangerous initial controls.'}
    if($window.Title -notmatch '4.3' -or $ui.BtnPreview.Content -notmatch 'REGLAS' -or
       $ui.BtnAudit.Content -notmatch 'WEBVIEW2'){throw 'WPF: missing dashboard actions.'}
    Write-Host ('PASS WPF 4.3: XAML loaded, {0} named controls, safety defaults, no firewall changes.' -f $names.Count)
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
$script:Working=$false
$script:ShuttingDown=$false

function PCAD-Read([string]$File){
    if($File -and (Test-Path -LiteralPath $File -PathType Leaf)){
        try {return (Get-Content -LiteralPath $File -Raw -ErrorAction Stop).Trim()}catch{}
    }
    return ''
}
function PCAD-Status([string]$Text,[string]$Badge='SOLO LECTURA'){
    $ui.ActivityText.Text=$Text
    $ui.TopStatus.Text=$Badge
}
function PCAD-Refresh {
    $busy=($null -ne $script:Child -or $null -ne $script:Admin)
    $ui.BtnPreview.IsEnabled=(!$busy)
    $ui.BtnAudit.IsEnabled=(!$busy)
    $ui.BtnApply.IsEnabled=(!$busy)
    $ui.BtnRollback.IsEnabled=(!$busy -and (Test-Path -LiteralPath (Join-Path $script:Reports 'operaciones') -PathType Container))
    $ui.BtnCancel.IsEnabled=($null -ne $script:Child)
    $ui.BtnMonitor.IsEnabled=(!$busy -and $null -eq $script:Monitor)
    $ui.BtnStopMonitor.IsEnabled=($null -ne $script:Monitor -and !$script:MonitorStopping)
}
function PCAD-ReportsDir {
    if(!(Test-Path -LiteralPath $script:Reports -PathType Container)){
        $null=New-Item -ItemType Directory -Path $script:Reports -Force -ErrorAction Stop
    }
}
function PCAD-StartChild([string]$Kind){
    if($null -ne $script:Child -or $null -ne $script:Admin){return}
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
    $ui.ResultTag.Text='TRABAJANDO'
    if($Kind -eq 'PREVIEW'){
        $ui.ResultTabs.SelectedIndex=0
        PCAD-Status 'Localizando ejecutables AutoCAD y comprobando reglas, sin modificar Windows...' 'CONSULTA ACTIVA'
    }else{
        $ui.ResultTabs.SelectedIndex=1
        PCAD-Status 'Auditando WebView2: instantánea observacional y atribución probable...' 'CONSULTA ACTIVA'
    }
    PCAD-Refresh
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
    $ui.Progress.Value=100
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
        $ui.ResultTag.Text=if($data.Status -eq 'PREVIEW_COMPLETA'){'CONSULTA CORRECTA'}else{'CATÁLOGO PARCIAL'}
        PCAD-Status 'Reglas AutoCAD consultadas. No se modificó el firewall.' 'SIN CAMBIOS'
    }elseif($kind -eq 'AUDIT' -and $null -ne $data -and
       $data.Schema -ceq 'PCAD_WEBVIEW_AUDIT_1' -and $data.ReadOnly -eq $true -and
       $data.NoFirewallChanges -eq $true -and [int]$data.SafeBlockingCandidates -eq 0){
        $ui.MetricWeb.Text=[string]$data.TotalWebView2
        $ui.MetricProbable.Text=[string]$data.ProbableAutoCAD
        $ui.TxtWeb.Text=('WebView2: {0} | AutoCAD probable: {1} | Indeterminados: {2}' -f
            $data.TotalWebView2,$data.ProbableAutoCAD,$data.Indeterminate)+[Environment]::NewLine+
            'Bloqueables automáticamente: 0. Runtime compartido protegido.'+[Environment]::NewLine+
            'Relación padre/PID observacional; no verifica aislamiento ni bloqueo de tráfico.'+[Environment]::NewLine+
            ('Informe: '+(Join-Path $root $reportName))
        $ui.ResultTag.Text='AUDITORÍA COMPLETA'
        PCAD-Status 'WebView2 auditado. Ningún bloqueo aplicado.' 'SOLO LECTURA'
    }else{
        $ui.Progress.Value=0
        $ui.ResultTag.Text='CONSULTA INCOMPLETA'
        PCAD-Status 'No se pudo verificar la consulta. No se aplicaron reglas.' 'REVISAR INFORME'
        $msg='Resultado incompleto; ver errores locales en: '+$script:ChildErr
        if($kind -eq 'PREVIEW'){$ui.TxtFirewall.Text=$msg}else{$ui.TxtWeb.Text=$msg}
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
        $script:Child=$null;$script:ChildType=''
        $ui.Progress.IsIndeterminate=$false;$ui.Progress.Value=0
        $ui.ResultTag.Text='CANCELADA'
        PCAD-Status 'Consulta cancelada. No se modificó el firewall.' 'SIN CAMBIOS'
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
    $ui.ResultTabs.SelectedIndex=2
    $ui.MonitorHint.Text='Monitor activo · TCP/UDP observacionales · máx. 10 min'
    PCAD-Status 'Monitor activo. Prueba AutoCAD; detén para guardar el informe.' 'MONITOR ACTIVO'
    PCAD-Refresh
}
function PCAD-StopMonitor {
    if($null -eq $script:Monitor -or $script:MonitorStopping){return}
    if(!(Test-Path -LiteralPath $script:MonitorRoot -PathType Container)){
        PCAD-Status 'Monitor iniciando. Reintenta detener cuando exista la sesión.' 'MONITOR ACTIVO'
        return
    }
    [IO.File]::WriteAllText((Join-Path $script:MonitorRoot 'detener.solicitud'),'stop',([Text.UTF8Encoding]::new($false)))
    $script:MonitorStopping=$true
    PCAD-Status 'Deteniendo monitor de forma segura y guardando el registro...' 'MONITOR ACTIVO'
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
       $data.ReadOnly -eq $true -and $data.BlockedTrafficVerified -eq $false -and
       $data.WebViewIsolationVerified -eq $false){
        $ui.TxtMonitor.Text=('Muestras: {0} | Eventos: {1} | TCP: {2} | UDP: {3}' -f
            $data.Samples,@($data.Events).Count,$data.ConnectionEventsTcp,$data.UdpEndpointsObserved)+[Environment]::NewLine+
            'Observación probable; ninguna ausencia de tráfico certificada.'+[Environment]::NewLine+('Informe: '+$path)
        $ui.MonitorHint.Text='Monitor finalizado · informe guardado'
        PCAD-Status 'Monitor finalizado y registro guardado. No certifica bloqueo.' 'SOLO LECTURA'
    }else{
        $ui.TxtMonitor.Text='Monitor parcial. Revisar archivos de informe; no se certifica ausencia de conexiones.'
        PCAD-Status 'Monitor terminó con resultado parcial o error.' 'REVISAR INFORME'
    }
    PCAD-Refresh
}
function PCAD-StartAdmin([string]$Mode,[string]$Manifest=''){
    if($null -ne $script:Child -or $null -ne $script:Admin){return}
    $engine=Join-Path $PSScriptRoot 'ParcheCAD.Reglas.ps1'
    if(!(Test-Path -LiteralPath $engine -PathType Leaf)){throw 'No se encontró motor de reglas.'}
    $args='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode {1} -ConfirmChange' -f $engine,$Mode
    if($Mode -eq 'Rollback'){$args+=' -Manifest "'+$Manifest+'"'}
    $proc=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args -Verb RunAs -PassThru -ErrorAction Stop
    $script:Admin=$proc;$script:AdminStart=Get-Date
    $ui.ResultTag.Text='UAC / CONFIRMACIÓN'
    PCAD-Status 'Operación administrativa en consola. Confirma o cancela allí.' 'CONFIRMACIÓN REQUERIDA'
    PCAD-Refresh
}

$ui.BtnPreview.Add_Click({try{PCAD-StartChild 'PREVIEW'}catch{[Windows.MessageBox]::Show($_.Exception.Message,'Vista previa')|Out-Null}})
$ui.BtnAudit.Add_Click({try{PCAD-StartChild 'AUDIT'}catch{[Windows.MessageBox]::Show($_.Exception.Message,'WebView2')|Out-Null}})
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
$ui.BtnApply.Add_Click({
    $msg='ParcheCAD comprobará ejecutables, rutas, conflictos y respaldos nuevamente.'+[Environment]::NewLine+
         'El bloqueo puede afectar funciones, red y validaciones de licencia de AutoCAD.'+[Environment]::NewLine+
         'No bloqueará WebView2 compartido. Requiere UAC y escribir APLICAR. Continuar?'
    if([Windows.MessageBox]::Show($msg,'Firewall AutoCAD','YesNo','Warning') -eq 'Yes'){
        try{PCAD-StartAdmin 'Apply'}catch{[Windows.MessageBox]::Show($_.Exception.Message,'Permisos de administrador')|Out-Null}
    }
})
$ui.BtnRollback.Add_Click({
    $root=Join-Path $script:Reports 'operaciones'
    if(!(Test-Path -LiteralPath $root -PathType Container)){return}
    $dlg=New-Object Microsoft.Win32.OpenFileDialog
    $dlg.InitialDirectory=$root
    $dlg.Filter='Manifiestos ParcheCAD|PCAD4_*.json'
    if(!$dlg.ShowDialog()){return}
    $file=[IO.Path]::GetFullPath($dlg.FileName)
    if([IO.Path]::GetDirectoryName($file) -ine [IO.Path]::GetFullPath($root) -or
       [IO.Path]::GetFileName($file) -notmatch '^PCAD4_[a-f0-9]{32}\.json$'){
        [Windows.MessageBox]::Show('Selecciona un manifiesto propio válido.','ParcheCAD')|Out-Null
        return
    }
    if([Windows.MessageBox]::Show('Revertir solamente reglas propias de esta operación?','Revertir','YesNo','Warning') -eq 'Yes'){
        try{PCAD-StartAdmin 'Rollback' $file}catch{[Windows.MessageBox]::Show($_.Exception.Message,'Revertir')|Out-Null}
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
                $ui.ResultTag.Text=('OPERACIÓN FINALIZADA · '+$code)
                PCAD-Status 'Revisa la consola y el respaldo antes de concluir que se aplicaron o revirtieron reglas.' 'REVISAR OPERACIÓN'
                PCAD-Refresh
            }
        }
        if($null -ne $script:Monitor){
            $p=$script:Monitor;$p.Refresh()
            if($p.HasExited){PCAD-CompleteMonitor}
        }
    }catch {
        $ui.ActivityText.Text=('Error de seguimiento: '+$_.Exception.GetType().Name)
    }
})
$window.Add_Closing({
    param($sender,$args)
    if($script:ShuttingDown){return}
    if($null -ne $script:Admin){
        $script:Admin.Refresh()
        if(!$script:Admin.HasExited){
            $args.Cancel=$true
            PCAD-Status 'La operación elevada continúa. Espera su finalización.' 'OPERACIÓN ACTIVA'
            return
        }
    }
    if($null -ne $script:Monitor){
        $script:Monitor.Refresh()
        if(!$script:Monitor.HasExited){
            $args.Cancel=$true
            try{PCAD-StopMonitor}catch{}
            PCAD-Status 'Terminando monitor antes de cerrar...' 'MONITOR ACTIVO'
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
PCAD-Refresh
$timer.Start()
$null=$window.ShowDialog()
