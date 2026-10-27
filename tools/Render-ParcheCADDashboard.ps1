# ParcheCAD compact WPF visual smoke: normal viewport has no vertical scroll.
#Requires -Version 5.1
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$xaml=Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'src') 'ParcheCAD.Dashboard.xaml'
$reader=[Xml.XmlReader]::Create($xaml)
try{$window=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
$sample=@{MetricAutoCAD='2027';MetricRules='31';MetricConflicts='0 conflictos';MetricWeb='21';
          MetricProbable='8';ActivityText='Vista previa completada. Ninguna regla aplicada.';
          TopStatus='SOLO LECTURA · EJEMPLO';ResultTag='PREVISUALIZACIÓN'}
foreach($key in @($sample.Keys)){
    $target=$window.FindName($key)
    if($null -eq $target){throw ('Missing WPF name: '+$key)}
    $target.Text=[string]$sample[$key]
}
$window.FindName('TxtFirewall').Text='Ejemplo de vista previa: 31 candidatas, 0 conflictos.'+[Environment]::NewLine+'Datos de demostración; el firewall permanece intacto.'
$window.FindName('Progress').Value=100

function Export-PCADSample([int]$Width,[int]$Height,[bool]$Stress=$false){
    $metrics=$window.FindName('MetricsGrid')
    $usable=[Math]::Max(280.0,([double]$Width-50.0))
    if($usable -ge 790){$metrics.Columns=4}
    elseif($usable -ge 490){$metrics.Columns=2}
    else{$metrics.Columns=1}
    $tabs=$window.FindName('WorkTabs')
    $details=$window.FindName('DetailsExpander')
    $scroll=$window.FindName('MainScroll')
    $preview=$window.FindName('BtnPreview')
    $apply=$window.FindName('BtnApply')
    $activity=$window.FindName('ActivityText')
    $oldActivity=$activity.Text
    $oldPreview=$preview.Content.Text
    $oldApply=$apply.Content.Text
    if($Stress){
        $activity.Text='Operación terminada sin verificación del efecto real; revisa las reglas y los informes de la sesión antes de proceder.'
        $preview.Content.Text='REVISAR TODAS LAS REGLAS DEL PRODUCTO AUTOCAD'
        $apply.Content.Text='VERIFICAR Y APLICAR CON CONFIRMACIÓN ADMINISTRATIVA'
        $preview.Content.FontSize=18
        $apply.Content.FontSize=18
    }
    try{
        $visual=$window.Content
        $tabs.SelectedIndex=0
        $visual.Measure([Windows.Size]::new($Width,$Height))
        $visual.Arrange([Windows.Rect]::new(0,0,$Width,$Height))
        $visual.UpdateLayout()
        if($details.IsExpanded){throw 'Compact details must default collapsed.'}
        if($tabs.Items.Count -ne 2){throw 'Exactly two main task tabs are required.'}
        foreach($btn in @($preview,$apply,$window.FindName('BtnRollback'))){
            if($btn.ActualHeight -lt 37){throw ('Invisible Firewall action: '+$btn.Name+' width '+$Width)}
        }
        $defaultScroll=[double]$scroll.ScrollableHeight
        if(!$Stress -and $Width -ge 1050 -and $Height -ge 665 -and $defaultScroll -gt 1.0){
            throw ('Unexpected scroll on normal window '+$Width+'x'+$Height+': '+$defaultScroll)
        }
        $tabs.SelectedIndex=1
        $visual.UpdateLayout()
        foreach($btn in @($window.FindName('BtnAudit'),$window.FindName('BtnMonitor'),$window.FindName('BtnStopMonitor'),$window.FindName('BtnGenericAutoCAD'),$window.FindName('BtnWebRestoreInfo'))){
            if($btn.ActualHeight -lt 37){throw ('Invisible WebView action: '+$btn.Name+' width '+$Width)}
        }
        $tabs.SelectedIndex=0
        $visual.UpdateLayout()
        $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($Width,$Height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($visual)
        $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $suffix=if($Stress){'-stress'}else{''}
        $path=Join-Path (Split-Path -Parent $PSScriptRoot) ('wpf-dashboard-preview-'+$Width+'x'+$Height+$suffix+'.png')
        $stream=[IO.File]::Create($path)
        try{$encoder.Save($stream)}finally{$stream.Dispose()}
        if((Get-Item -LiteralPath $path).Length -lt 5000){throw 'Rendered PNG is unexpectedly small'}
        Write-Host ('PASS compact layout: {0}x{1}, cards={2}, scroll={3}, stress={4}' -f $Width,$Height,$metrics.Columns,$defaultScroll,$Stress)
    }finally{
        $activity.Text=$oldActivity
        $preview.Content.Text=$oldPreview
        $apply.Content.Text=$oldApply
        $preview.Content.FontSize=13
        $apply.Content.FontSize=13
    }
}
Export-PCADSample 1050 665
Export-PCADSample 1120 720
Export-PCADSample 780 650
Export-PCADSample 580 550
Export-PCADSample 430 480
Export-PCADSample 1050 665 $true
$window.Close()
Write-Host 'PASS: compact dashboard six WPF render scenarios; no-scroll normal window and both task tabs.'
