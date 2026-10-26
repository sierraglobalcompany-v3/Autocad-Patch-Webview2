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

# Layout A: capturas sinteticas de cuatro anchos de ventana en DIP.
# Ventana WPF real ajusta estos mismos breakpoints mediante PCAD-Layout.
foreach($width in @(430,580,780,1120,1440)){
    $usable=[Math]::Max(300.0,([double]$width-72.0))
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
    $height=850
    $visual=$window.Content
    $visual.Measure([Windows.Size]::new($width,$height))
    $visual.Arrange([Windows.Rect]::new(0,0,$width,$height))
    $visual.UpdateLayout()
    $parent=$window.FindName('ActionsWrap')
    if($parent.ActualWidth -gt 0 -and ($firewallCard.Width -gt $parent.ActualWidth -or $webCard.Width -gt $parent.ActualWidth)){
        throw ('WPF card exceeds viewport at width '+$width)
    }
    if($window.FindName('BtnApply').ActualHeight -lt 44 -or
       $window.FindName('BtnPreview').ActualHeight -lt 44){
       throw ('WPF buttons too small or clipped at width '+$width)
    }
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $path=Join-Path (Split-Path -Parent $PSScriptRoot) ('wpf-dashboard-preview-'+$width+'.png')
    $f=[IO.File]::Create($path)
    try{$encoder.Save($f)}finally{$f.Dispose()}
    if((Get-Item -LiteralPath $path).Length -lt 6000){throw ('WPF render too small at '+$width)}
    Write-Host ('PASS WPF layout '+$width+' DIP, metric columns '+$metrics.Columns+', card width '+$cardWidth+', screenshot '+$path)
}
$window.Close()
Write-Host ('PASS: WPF screenshot rendered to '+$path)
