# ParcheCAD 4.0 - diagnóstico no bloqueante; modificaciones solo con UAC y confirmación.
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
$script:Started=Get-Date
$script:LastReport=$null
$script:LastExitCode=$null
$script:AdminProc=$null
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
function PCAD-Button([string]$Text,[int]$X,[int]$Y,[int]$W) {
    $o=New-Object Windows.Forms.Button
    $o.Text=$Text;$o.Location=New-Object Drawing.Point($X,$Y)
    $o.Size=New-Object Drawing.Size($W,44)
    return $o
}
$form=New-Object Windows.Forms.Form
$form.Text='ParcheCAD 4.0 | Diagnostico AutoCAD 2023-2027'
$form.ClientSize=New-Object Drawing.Size(945,715)
$form.MinimumSize=New-Object Drawing.Size(955,755)
$form.FormBorderStyle='FixedSingle';$form.MaximizeBox=$false
$form.StartPosition='CenterScreen';$form.BackColor=[Drawing.Color]::White
$form.Font=New-Object Drawing.Font('Segoe UI',10)
$header=PCAD-Label 'ParcheCAD 4.0 | Control y diagnostico' 20 18 905 38 18
$sub=PCAD-Label 'Diagnostico de solo lectura. Los cambios requieren autorizacion administrativa expresa.' 20 61 905 28
$sub.ForeColor=[Drawing.Color]::DimGray
$installed=PCAD-Label 'AutoCAD 2023-2027: pendiente de detectar' 20 109 905 31 12
$webview=PCAD-Label 'WebView2 compartido: pendiente de detectar' 20 147 905 30
$rules=PCAD-Label 'Reglas heredadas: pendiente de detectar' 20 184 905 31
$why=PCAD-Label 'ATENCION: WebView2 tambien lo usan WhatsApp y Correo; una regla global puede afectar esas aplicaciones.' 20 220 905 40
$why.ForeColor=[Drawing.Color]::DarkRed
$start=PCAD-Button 'ANALIZAR SISTEMA' 20 275 345
$open=PCAD-Button 'ABRIR INFORMES' 378 275 250
$cancel=PCAD-Button 'CANCELAR' 642 275 135
$exit=PCAD-Button 'SALIR' 790 275 135
$preview=PCAD-Button 'VISTA PREVIA DE BLOQUEOS' 20 334 295
$apply=PCAD-Button 'APLICAR CON CONFIRMACION' 328 334 300
$rollback=PCAD-Button 'REVERTIR OPERACION PROPIA' 642 334 283
$progressLabel=PCAD-Label 'Listo para iniciar' 20 399 905 30
$bar=New-Object Windows.Forms.ProgressBar
$bar.Location=New-Object Drawing.Point(20,432);$bar.Size=New-Object Drawing.Size(905,19)
$bar.Minimum=0;$bar.Maximum=100
$status=PCAD-Label 'Estado: pendiente de diagnostico' 20 464 905 30 11
$details=New-Object Windows.Forms.TextBox
$details.Location=New-Object Drawing.Point(20,500);$details.Size=New-Object Drawing.Size(905,158)
$details.Multiline=$true;$details.ScrollBars='Both'
$details.ReadOnly=$true;$details.WordWrap=$false
$details.Font=New-Object Drawing.Font('Consolas',9)
$details.Text='ParcheCAD 4.0: inventario por version, reglas y procesos WebView2.'
$foot=PCAD-Label 'Los cambios requieren administrador y confirmacion escrita; se guardan respaldos locales.' 20 670 905 28 9
$foot.ForeColor=[Drawing.Color]::DimGray
$form.Controls.AddRange(@($header,$sub,$installed,$webview,$rules,$why,$start,$open,$cancel,$exit,$preview,$apply,$rollback,$progressLabel,$bar,$status,$details,$foot))
$cancel.Enabled=$false
$preview.Enabled=$false;$apply.Enabled=$false;$rollback.Enabled=$false
function PCAD-Busy([bool]$Busy) {
    $script:start.Enabled=-not $Busy
    $script:open.Enabled=-not $Busy
    $script:cancel.Enabled=$Busy -and ($null -eq $script:AdminProc)
    $ui=Get-PCADReportUiState -Report $script:LastReport -ExitCode $script:LastExitCode
    $script:preview.Enabled=(-not $Busy) -and $ui.CanPreview
    $script:apply.Enabled=(-not $Busy) -and ($null -eq $script:AdminProc) -and $ui.CanApply -and
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'ParcheCAD.Reglas.ps1') -PathType Leaf)
    $script:rollback.Enabled=(-not $Busy) -and (Test-Path -LiteralPath (Join-Path $script:Reports 'operaciones') -PathType Container)
}
function PCAD-ReadLog([string]$File) {
    try {if(Test-Path -LiteralPath $File -PathType Leaf) {return (Get-Content -LiteralPath $File -ErrorAction Stop) -join [Environment]::NewLine}}
    catch {}
    return ''
}
function PCAD-Finish {
    $timer.Stop()
    $p=$script:Proc
    if($null -eq $p){return}
    $script:Proc=$null
    $p.Refresh();$code=$p.ExitCode;$p.Dispose()
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
    $webview.Text=("WebView2 observado: {0} procesos; atribuibles probablemente a AutoCAD: {1}" -f $web.Count,$acadWeb.Count)
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
    $network=@(Get-PCADReportRows -Object $ui.Sections -Name 'NetworkOverview')
    if($network.Count -gt 0 -and $null -ne $network[0]) {
        $lines.Add(('Atribucion F3: {0} WebView2 observados, {1} AutoCAD probable(s), aislamiento NO VERIFICADO' -f $network[0].TotalWebView2,$network[0].ProbableAutoCAD))
    }
    $planRows=@(Get-PCADReportRows -Object $ui.Sections -Name 'PolicyPreview')
    if($planRows.Count -gt 0 -and $null -ne $planRows[0]) {
        $lines.Add(('Vista previa F4: {0} reglas candidatas, {1} conflictos, {2} excluidos; NINGUNA regla aplicada' -f $planRows[0].Count,$planRows[0].Conflicts,@($planRows[0].Excluded).Count))
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
    PCAD-Busy $false
}
$timer=New-Object Windows.Forms.Timer
$timer.Interval=400
$timer.Add_Tick({
    if($null -ne $script:AdminProc){
        $script:AdminProc.Refresh()
        if($script:AdminProc.HasExited){
            $code=$script:AdminProc.ExitCode
            $script:AdminProc.Dispose();$script:AdminProc=$null
            PCAD-Busy $false
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
        $arguments='-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "{0}" -OutputDirectory "{1}"' -f $script:Runner,$script:RunRoot
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
        $args='-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "{0}" -Mode {1} -ConfirmChange' -f $engine,$Mode
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
    if($null -ne $script:Proc -or $null -ne $script:AdminProc -or !$ui.CanApply){return}
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
$open.Add_Click({
    if(Test-Path -LiteralPath $script:Reports -PathType Container){
        Start-Process -FilePath explorer.exe -ArgumentList ('"'+$script:Reports+'"')
    }else{[void][Windows.Forms.MessageBox]::Show('Todavia no existen informes.','ParcheCAD')}
})
$cancel.Add_Click({
    if($null -eq $script:Proc){return}
    if(!$InteractionSelfTest -and [Windows.Forms.MessageBox]::Show('Cancelar consulta? No se modifica Windows.','ParcheCAD','YesNo','Question') -ne 'Yes'){return}
    $timer.Stop()
    try{$script:Proc.Refresh();if(!$script:Proc.HasExited){$script:Proc.Kill()}}catch{}
    try{$script:Proc.Dispose()}catch{}
    $script:Proc=$null
    PCAD-Busy $false
    $bar.Style='Continuous';$bar.Value=0
    $status.Text='CANCELADO. No se modifico el firewall.'
})
$exit.Add_Click({$form.Close()})
$form.Add_FormClosing({
    param($sender,$e)
    if($null -ne $script:AdminProc){$script:AdminProc.Refresh();if(!$script:AdminProc.HasExited){$e.Cancel=$true;return}}
    $timer.Stop()
    if($null -ne $script:Proc){
        try{$script:Proc.Refresh();if(!$script:Proc.HasExited){$script:Proc.Kill()}}catch{}
        try{$script:Proc.Dispose()}catch{}
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
        PCAD-Finish
        if($null -eq $script:LastReport -or $null -eq $script:LastExitCode){throw 'F9: no report or exit code'}
        $ui=Get-PCADReportUiState -Report $script:LastReport -ExitCode $script:LastExitCode
        if(!$start.Enabled -or $cancel.Enabled -or $apply.Enabled){throw 'F9: wrong controls after read-only diagnostic on clean runner'}
        if($status.Text -cne $ui.Description){throw 'F9: GUI header disagrees with validator'}
        Write-Host ('F9 PASS: Analyze handler -> read-only Windows child -> report -> safe status ({0}).' -f $ui.Result)

        Write-Host 'F9: dispatch Cancel handler against an owned dummy sleeping process.'
        $script:LastReport=$null;$script:LastExitCode=$null
        $script:Proc=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList '-NoLogo -NoProfile -Command "Start-Sleep -Seconds 30"' -PassThru -WindowStyle Hidden -ErrorAction Stop
        PCAD-Busy $true
        if(!$cancel.Enabled -or $apply.Enabled){throw 'F9: cancel disabled while read-only child running'}
        Invoke-PCADClick -Button $cancel
        if($null -ne $script:Proc -or $cancel.Enabled -or $apply.Enabled -or $status.Text -notmatch 'CANCELADO'){
            throw 'F9: cancel handler failed to release owned process and reset controls'
        }
        Write-Host 'F9 PASS: Cancel handler closed only its owned dummy child.'

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
        Write-Host 'PASS F9: WinForms event handlers validated headlessly, UAC/visual QA remain pending.' -ForegroundColor Green
        exit 0
    } finally {
        $timer.Stop()
        foreach($name in @('Proc','AdminProc')){
            $p=Get-Variable -Name $name -Scope Script -ValueOnly -ErrorAction SilentlyContinue
            if($null -ne $p){
                try {$p.Refresh();if(!$p.HasExited){$p.Kill();$p.WaitForExit(5000)|Out-Null}}catch{}
                try {$p.Dispose()}catch{}
                Set-Variable -Name $name -Scope Script -Value $null
            }
        }
        if(!$form.IsDisposed){$form.Dispose()}
        if($createdRunRoot -and (Test-Path -LiteralPath $createdRunRoot -PathType Container)){
            Remove-Item -LiteralPath $createdRunRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
if($SelfTest){
    if(!$form.Controls.Contains($preview) -or !$form.Controls.Contains($apply) -or
       !$form.Controls.Contains($rollback) -or $apply.Enabled -or $rollback.Enabled){throw 'GUI selftest: controls missing or dangerous startup state'}
    $script:LastExitCode=0
    $script:LastReport=[pscustomobject]@{
        Tool='ParcheCAD';SchemaVersion=1;ReadOnly=$true;Result='PARCIAL_NO_VERIFICADO'
        Sections=[pscustomobject]@{
            PolicyPreview=@([pscustomobject]@{Count=2;Conflicts=0;State='PLAN_NO_APLICADO'})
        }
    }
    PCAD-Busy $false
    if($apply.Enabled){throw 'GUI selftest: partial diagnostics allowed apply'}
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
    if($apply.Enabled -or $rollback.Enabled){throw 'GUI selftest: modifications allowed while busy'}
    Write-Host 'PASS GUI: form initialized, partial diagnostics blocked, valid preview gated and busy state protected.'
    $form.Dispose()
    exit 0
}
[void][Windows.Forms.Application]::Run($form)
