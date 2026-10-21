# ParcheCAD 4.0 F2 - panel diagnostico no bloqueante. SOLO LECTURA.
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$SelfTest)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:Runner=Join-Path $PSScriptRoot 'ParcheCAD.Diagnostico.ps1'
$script:Reports=Join-Path (Split-Path -Parent $PSScriptRoot) 'informes'
$script:Proc=$null
$script:RunRoot=''
$script:LogOut=''
$script:LogErr=''
$script:Started=Get-Date
$script:LastReport=$null
$script:AdminProc=$null
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
$sub=PCAD-Label 'F1/F2 - Sin modificaciones al firewall, registro, servicios ni tareas.' 20 61 905 28
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
    $start.Enabled=-not $Busy
    $open.Enabled=-not $Busy
    $cancel.Enabled=$Busy -and ($null -eq $script:AdminProc)
    $preview.Enabled=(-not $Busy) -and ($null -ne $script:LastReport)
    $plans=@()
    if($null -ne $script:LastReport){$plans=@($script:LastReport.Sections.PolicyPreview | Where-Object {$null -ne $_})}
    $ready=($plans.Count -gt 0 -and [int]$plans[0].Count -gt 0 -and [int]$plans[0].Conflicts -eq 0)
    $apply.Enabled=(-not $Busy) -and $ready -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'ParcheCAD.Reglas.ps1') -PathType Leaf)
    $rollback.Enabled=(-not $Busy) -and (Test-Path -LiteralPath (Join-Path $script:Reports 'operaciones') -PathType Container)
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
    $inst=@($data.Sections.Installations | Where-Object {$null -ne $_ -and $_.FileFound})
    $years=@($inst | ForEach-Object {$_.Year} | Sort-Object -Unique)
    $installed.Text='AutoCAD detectados: '+$(if($years.Count){$years -join ', '}else{'ninguno'})
    $web=@($data.Sections.Processes | Where-Object {$_.Classification -eq 'WEBVIEW2_COMPARTIDO'})
    $acadWeb=@($web | Where-Object {$_.Attribution -eq 'AUTOCAD_PROBABLE'})
    $webview.Text=("WebView2 observado: {0} procesos; atribuibles probablemente a AutoCAD: {1}" -f $web.Count,$acadWeb.Count)
    $historical=@($data.Sections.Historico)
    if($historical.Count -gt 0 -and $null -ne $historical[0]){
        $h=$historical[0]
        $rules.Text=("Firewall Autodesk: {0}; WebView2 global: {1}; tareas sospechosas: {2}" -f $h.AutoCADAndAutodeskActiveRules,$h.WebView2ActiveRules,$h.SuspectedTasks)
    }
    $status.Text=$(if($code -eq 0){'DIAGNOSTICO COMPLETO (sin cambios)'}else{'DIAGNOSTICO PARCIAL; revisa errores'})
    $status.ForeColor=$(if($code -eq 0){[Drawing.Color]::ForestGreen}else{[Drawing.Color]::Firebrick})
    $progressLabel.Text=("Terminado en {0}s; informe guardado." -f $data.ElapsedSeconds)
    $lines=New-Object System.Collections.Generic.List[string]
    $lines.Add(("Resultado: {0}" -f $data.Result))
    $lines.Add(("Catalogo: {0} ejecutables" -f @($data.Sections.Catalog).Count))
    $network=@($data.Sections.NetworkOverview)
    if($network.Count -gt 0 -and $null -ne $network[0]) {
        $lines.Add(('Atribucion F3: {0} WebView2 observados, {1} AutoCAD probable(s), aislamiento NO VERIFICADO' -f $network[0].TotalWebView2,$network[0].ProbableAutoCAD))
    }
    $preview=@($data.Sections.PolicyPreview)
    if($preview.Count -gt 0 -and $null -ne $preview[0]) {
        $lines.Add(('Vista previa F4: {0} reglas candidatas, {1} conflictos, {2} excluidos; NINGUNA regla aplicada' -f $preview[0].Count,$preview[0].Conflicts,@($preview[0].Excluded).Count))
    }
    foreach($c in @($data.Checks)){$lines.Add(("{0}: {1} ({2}) {3}" -f $c.Section,$c.Status,$c.Count,$c.Detail))}
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
function PCAD-LaunchAdmin([string]$Mode,[string]$Manifest='') {
    if($null -ne $script:Proc -or $null -ne $script:AdminProc){return}
    $engine=Join-Path $PSScriptRoot 'ParcheCAD.Reglas.ps1'
    if(!(Test-Path -LiteralPath $engine -PathType Leaf)){
        [void][Windows.Forms.MessageBox]::Show('No existe motor de reglas. Descarga el paquete completo.','ParcheCAD')
        return
    }
    try {
        $args='-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "{0}" -Mode {1} -ConfirmChange' -f $engine,$Mode
        if($Mode -eq 'Rollback') {$args+=' -Manifest "'+$Manifest+'"'}
        $script:AdminProc=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args -Verb RunAs -PassThru -ErrorAction Stop
        PCAD-Busy $true
        $cancel.Enabled=$false
        $status.Text='OPERACION ADMINISTRATIVA: pendiente del resultado de la consola elevada.'
        $progressLabel.Text='Confirma o cancela en la consola elevada; espera hasta finalizar.'
        $timer.Start()
    } catch {
        $script:AdminProc=$null
        PCAD-Busy $false
        $status.Text='No se inicio la operacion administrativa.'
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Operacion cancelada/no autorizada')
    }
}
$preview.Add_Click({
    if($null -eq $script:LastReport){return}
    $p=@($script:LastReport.Sections.PolicyPreview)
    if($p.Count -eq 0 -or $null -eq $p[0]){return}
    $nl=[Environment]::NewLine
    $message=("Plan F4 (solo lectura):"+$nl+"Candidatos: {0}"+$nl+"Conflictos: {1}"+$nl+"Excluidos: {2}"+$nl+$nl+"WebView2 compartido no incluido. Tambien afecta LAN. No se crea ninguna regla." -f $p[0].Count,$p[0].Conflicts,@($p[0].Excluded).Count)
    [void][Windows.Forms.MessageBox]::Show($message,'Vista previa de bloqueos','OK','Information')
})
$apply.Add_Click({
    if($null -eq $script:LastReport -or $script:LastReport.Result -ne 'DIAGNOSTICO_COMPLETADO_SIN_CAMBIOS') {
        [void][Windows.Forms.MessageBox]::Show('Realiza un diagnostico completo antes de aplicar reglas.','ParcheCAD')
        return
    }
    $p=@($script:LastReport.Sections.PolicyPreview)
    if($p.Count -ne 1 -or [int]$p[0].Count -le 0 -or [int]$p[0].Conflicts -gt 0){return}
    $checks=@($script:LastReport.Checks|Where-Object {$_.Status -ne 'OK'})
    if($checks.Count -gt 0){[void][Windows.Forms.MessageBox]::Show('Diagnostico parcial: no se aplica.','ParcheCAD');return}
    $prompt=("Se propondran {0} reglas de salida para EXE AutoCAD 2023-2027. Puede afectar LAN, licencias y funciones online. NO incluye WebView2 compartido ni servicios Autodesk. Debes confirmar otra vez en consola elevada. Continuar?" -f $p[0].Count)
    if([Windows.Forms.MessageBox]::Show($prompt,'Aplicar reglas de AutoCAD','YesNo','Warning') -ne 'Yes'){return}
    PCAD-LaunchAdmin -Mode 'Apply'
})
$rollback.Add_Click({
    $folder=Join-Path $script:Reports 'operaciones'
    if(!(Test-Path -LiteralPath $folder -PathType Container)){return}
    $dlg=New-Object Windows.Forms.OpenFileDialog
    $dlg.Title='Selecciona un respaldo propio de ParcheCAD para revertir'
    $dlg.Filter='Operaciones de ParcheCAD (PCAD4_*.json)|PCAD4_*.json'
    $dlg.InitialDirectory=$folder
    $dlg.Multiselect=$false
    if($dlg.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){$dlg.Dispose();return}
    $selected=$dlg.FileName;$dlg.Dispose()
    $resolved=[IO.Path]::GetFullPath($selected)
    if([IO.Path]::GetDirectoryName($resolved) -ine [IO.Path]::GetFullPath($folder) -or
        [IO.Path]::GetFileName($resolved) -notmatch '^PCAD4_[0-9a-f]{32}\.json
$open.Add_Click({
    if(Test-Path -LiteralPath $script:Reports -PathType Container){
        Start-Process -FilePath explorer.exe -ArgumentList ('"'+$script:Reports+'"')
    }else{[void][Windows.Forms.MessageBox]::Show('Todavia no existen informes.','ParcheCAD')}
})
$cancel.Add_Click({
    if($null -eq $script:Proc){return}
    if([Windows.Forms.MessageBox]::Show('Cancelar consulta? No se modifica Windows.','ParcheCAD','YesNo','Question') -ne 'Yes'){return}
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
    param($sender,$eventArgs)
    if($null -ne $script:AdminProc){
        $script:AdminProc.Refresh()
        if(!$script:AdminProc.HasExited){
            $eventArgs.Cancel=$true
            [void][Windows.Forms.MessageBox]::Show('Espera a que termine la operacion elevada antes de cerrar el panel.','ParcheCAD')
            return
        }
    }
    $timer.Stop()
    if($null -ne $script:Proc){
        try{$script:Proc.Refresh();if(!$script:Proc.HasExited){$script:Proc.Kill()}}catch{}
        try{$script:Proc.Dispose()}catch{}
    }
})
$form.Add_Shown({PCAD-Begin})
if($SelfTest) {
    if(!$form.Controls.Contains($preview) -or !$form.Controls.Contains($apply) -or
       !$form.Controls.Contains($rollback) -or $apply.Enabled -or $rollback.Enabled) {
        throw 'SELFTEST FAIL: faltan controles o existe alguna accion administrativa habilitada antes de analizar.'
    }
    Write-Host 'PASS GUI: WinForms inicializado y cambios administrativos deshabilitados antes de analizar.'
    $form.Dispose()
    exit 0
}
[void][Windows.Forms.Application]::Run($form)
) {
        [void][Windows.Forms.MessageBox]::Show('Respaldo no valido o fuera del directorio esperado.','ParcheCAD')
        return
    }
    if([Windows.Forms.MessageBox]::Show('Revertir solo las reglas nuevas registradas en esta operacion? Requiere administrador y confirmacion en consola.','Revertir reglas','YesNo','Warning') -ne 'Yes'){return}
    PCAD-LaunchAdmin -Mode 'Rollback' -Manifest $resolved
})
$start.Add_Click({PCAD-Begin})
$open.Add_Click({
    if(Test-Path -LiteralPath $script:Reports -PathType Container){
        Start-Process -FilePath explorer.exe -ArgumentList ('"'+$script:Reports+'"')
    }else{[void][Windows.Forms.MessageBox]::Show('Todavia no existen informes.','ParcheCAD')}
})
$cancel.Add_Click({
    if($null -eq $script:Proc){return}
    if([Windows.Forms.MessageBox]::Show('Cancelar consulta? No se modifica Windows.','ParcheCAD','YesNo','Question') -ne 'Yes'){return}
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
    $timer.Stop()
    if($null -ne $script:Proc){
        try{$script:Proc.Refresh();if(!$script:Proc.HasExited){$script:Proc.Kill()}}catch{}
        try{$script:Proc.Dispose()}catch{}
    }
})
$form.Add_Shown({PCAD-Begin})
[void][Windows.Forms.Application]::Run($form)
