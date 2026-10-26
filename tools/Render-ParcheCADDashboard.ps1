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
$width=1110;$height=870
$visual=$window.Content
$visual.Measure([Windows.Size]::new($width,$height))
$visual.Arrange([Windows.Rect]::new(0,0,$width,$height))
$visual.UpdateLayout()
$bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
$bitmap.Render($visual)
$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new()
$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
if(!$OutputFile){$OutputFile=Join-Path (Split-Path -Parent $PSScriptRoot) 'wpf-dashboard-preview.png'}
$path=[IO.Path]::GetFullPath($OutputFile)
$dir=[IO.Path]::GetDirectoryName($path)
if(!(Test-Path -LiteralPath $dir -PathType Container)){$null=New-Item -ItemType Directory -Path $dir -Force}
$f=[IO.File]::Create($path)
try{$encoder.Save($f)}finally{$f.Dispose()}
if((Get-Item -LiteralPath $path).Length -lt 6000){throw 'Rendered PNG is unexpectedly small'}
$window.Close()
Write-Host ('PASS: WPF screenshot rendered to '+$path)
