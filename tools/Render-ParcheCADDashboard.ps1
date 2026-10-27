# Render WPF dashboard to a PNG offscreen (CI evidence only; no firewall or GUI interaction).
#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputFile='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase -ErrorAction Stop
$xaml=Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'src') 'ParcheCAD.Dashboard.xaml'
$reader=[Xml.XmlReader]::Create($xaml)
try{$window=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
$rows=@{
    MetricAutoCAD='2027';MetricRules='31';MetricConflicts='0 conflictos';
    MetricWeb='21';MetricProbable='8';ActivityText='Reglas AutoCAD verificadas. Sin cambios en firewall.'
    TopStatus='SOLO LECTURA · EJEMPLO'
    ResultTag='VISTA PREVIA DE DISEÑO'
}
foreach($key in $rows.Keys){
    $target=$window.FindName($key)
    if($null -eq $target){throw ('Missing visual target: '+$key)}
    $target.Text=[string]$rows[$key]
}
$window.FindName('TxtFirewall').Text='Instalaciones: 1 | Candidatas: 31 | Conflictos: 0 | Excluidas: 0'+[Environment]::NewLine+
'Estos valores son una muestra visual, NO una captura del equipo del usuario.'+[Environment]::NewLine+
'VISTA PREVIA. Ninguna regla aplicada. WebView2 compartido excluido.'
$window.FindName('Progress').Value=100

# Lote C: un renderizador, dos escenarios. Sin duplicar la lógica operativa.
# Los casos STRESS prueban textos extendidos y fuente mayor; NO simulan DPI físico.
function Export-PCADSample([int]$Width,[bool]$Stress=$false) {
    $usable=[Math]::Max(300.0,([double]$Width-72.0))
    $metrics=$window.FindName('MetricsGrid')
    if($usable -ge 1020){$metrics.Columns=4}
    elseif($usable -ge 570){$metrics.Columns=2}
    else{$metrics.Columns=1}
    $two=$usable -ge 880
    $cardWidth=if($two){[Math]::Floor(($usable-18)/2)}else{[Math]::Floor($usable-16)}
    $firewallCard=$window.FindName('FirewallCard')
    $webCard=$window.FindName('WebCard')
    $firewallCard.Width=$cardWidth
    $webCard.Width=$cardWidth
    $previewButton=$window.FindName('BtnPreview')
    $applyButton=$window.FindName('BtnApply')
    $status=$window.FindName('TopStatus')
    $activity=$window.FindName('ActivityText')
    $conflicts=$window.FindName('MetricConflicts')
    $previewLabel=$previewButton.Content
    $applyLabel=$applyButton.Content
    if($Stress){
        $status.Text='OPERACIÓN ADMINISTRATIVA TERMINADA, EFECTO AÚN SIN VERIFICAR'
        $activity.Text='Comprobando una lista especialmente larga de instalaciones y reglas existentes. El resultado parcial no acredita ningún bloqueo de tráfico.'
        $conflicts.Text='0 conflictos; algunos datos requieren inspección manual'
        $previewLabel.Text='CONSULTAR TODAS LAS REGLAS EXISTENTES DE AUTOCAD'
        $applyLabel.Text='VERIFICAR Y APLICAR SOLO CON CONFIRMACIÓN'
        $previewLabel.FontSize=18
        $applyLabel.FontSize=18
    }
    try{
        $height=850
        $visual=$window.Content
        $visual.Measure([Windows.Size]::new($Width,$height))
        $visual.Arrange([Windows.Rect]::new(0,0,$Width,$height))
        $visual.UpdateLayout()
        $parent=$window.FindName('ActionsWrap')
        if($parent.ActualWidth -gt 0 -and ($firewallCard.Width -gt $parent.ActualWidth -or $webCard.Width -gt $parent.ActualWidth)){
            throw ('WPF card exceeds viewport at '+$Width+' DIP')
        }
        foreach($button in @($previewButton,$applyButton,$window.FindName('BtnAudit'),$window.FindName('BtnMonitor'))){
            if($button.ActualHeight -lt 44){
                throw ('WPF button too short or clipped at '+$Width+' DIP: '+$button.Name)
            }
            if($button.Content -is [Windows.Controls.TextBlock] -and
                $button.Content.TextWrapping -ne [Windows.TextWrapping]::Wrap){
                throw ('WPF action label not wrapping: '+$button.Name)
            }
        }
        if($Width -le 580 -and $window.FindName('MainScroll').ScrollableHeight -le 0){
            throw ('WPF narrow window missing vertical scroll at '+$Width+' DIP')
        }
        $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($Width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($visual)
        $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $suffix=if($Stress){'-stress'}else{''}
        $path=Join-Path (Split-Path -Parent $PSScriptRoot) ('wpf-dashboard-preview-'+$Width+$suffix+'.png')
        $f=[IO.File]::Create($path)
        try{$encoder.Save($f)}finally{$f.Dispose()}
        if((Get-Item -LiteralPath $path).Length -lt 6000){
            throw ('WPF render too small at '+$Width+' DIP')
        }
        Write-Host ('PASS WPF: {0} DIP, {1} metric columns, stress={2}' -f $Width,$metrics.Columns,$Stress)
    }finally{
        if($Stress){
            $status.Text='SOLO LECTURA · EJEMPLO'
            $activity.Text='Reglas AutoCAD verificadas. Sin cambios en firewall.'
            $conflicts.Text='0 conflictos'
            $previewLabel.Text='VER REGLAS AUTOCAD'
            $applyLabel.Text='VERIFICAR Y APLICAR'
            $previewLabel.FontSize=13
            $applyLabel.FontSize=13
        }
    }
}
foreach($width in @(430,580,780,1120,1440)){
    Export-PCADSample -Width $width
}
Export-PCADSample -Width 580 -Stress $true
Export-PCADSample -Width 1120 -Stress $true
$window.Close()
Write-Host 'PASS: WPF screenshots, 5 widths and 2 long-text/font-stress cases (synthetic DPI-independent layout).' -ForegroundColor Green
