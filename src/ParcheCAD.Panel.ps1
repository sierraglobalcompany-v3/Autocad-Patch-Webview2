# ParcheCAD 4.0 F2 - panel diagnostico no bloqueante. SOLO LECTURA.
#Requires -Version 5.1
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
$form.ClientSize=New-Object Drawing.Size(945,660)
$form.MinimumSize=New-Object Drawing.Size(955,700)
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
$progressLabel=PCAD-Label 'Listo para iniciar' 20 337 905 30
$bar=New-Object Windows.Forms.ProgressBar
$bar.Location=New-Object Drawing.Point(20,369);$bar.Size=New-Object Drawing.Size(905,19)
$bar.Minimum=0;$bar.Maximum=100
$status=PCAD-Label 'Estado: pendiente de diagnostico' 20 400 905 30 11
$details=New-Object Windows.Forms.TextBox
$details.Location=New-Object Drawing.Point(20,438);$details.Size=New-Object Drawing.Size(905,168)
$details.Multiline=$true;$details.ScrollBars='Both'
$details.ReadOnly=$true;$details.WordWrap=$false
$details.Font=New-Object Drawing.Font('Consolas',9)
$details.Text='ParcheCAD 4.0: inventario por version, reglas y procesos WebView2.'
$foot=PCAD-Label 'La gestion reversible del firewall se incorporara despues del QA del motor de reglas.' 20 619 905 28 9
$foot.ForeColor=[Drawing.Color]::DimGray
$form.Controls.AddRange(@($header,$sub,$installed,$webview,$rules,$why,$start,$open,$cancel,$exit,$progressLabel,$bar,$status,$details,$foot))
$cancel.Enabled=$false
function PCAD-Busy([bool]$Busy) {
    $start.Enabled=-not $Busy
    $open.Enabled=-not $Busy
    $cancel.Enabled=$Busy
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
    foreach($c in @($data.Checks)){$lines.Add(("{0}: {1} ({2}) {3}" -f $c.Section,$c.Status,$c.Count,$c.Detail))}
    $lines.Add('WebView2 de AutoCAD aislado: NO VERIFICADO.')
    $lines.Add(("Informe: {0}" -f $file))
    $details.Text=$lines -join [Environment]::NewLine
}
$timer=New-Object Windows.Forms.Timer
$timer.Interval=400
$timer.Add_Tick({
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
    if($null -ne $script:Proc){return}
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
