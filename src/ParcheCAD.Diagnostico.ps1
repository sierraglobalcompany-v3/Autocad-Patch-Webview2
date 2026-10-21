# F0: inventario; no toca firewall, registro, servicios ni tareas.
[CmdletBinding()]
param([string]$OutputDirectory='',[switch]$NoExport)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ParcheCAD.Core.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Catalogo.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Historico.ps1')

$started=Get-Date
$sections=[ordered]@{}
$checks=New-Object System.Collections.ArrayList
$stages=@(
    @{Key='Installations';Label='AutoCAD 2023-2027'},
    @{Key='Processes';Label='Procesos AutoCAD y WebView2'},
    @{Key='Services';Label='Servicios Autodesk'},
    @{Key='Catalog';Label='Catalogo de ejecutables por version'},
    @{Key='Firewall';Label='Reglas heredadas y activas'},
    @{Key='Tasks';Label='Tareas programadas'},
    @{Key='Historico';Label='Resumen de bloqueos anteriores'},
    @{Key='Connections';Label='Conexiones TCP y endpoints UDP'}
)
$i=0
foreach ($stage in $stages) {
    $i++; $key=[string]$stage.Key
    Write-Progress -Activity 'ParcheCAD 4.0 / Diagnostico de solo lectura' -Status ([string]$stage.Label) -PercentComplete ([int](($i-1)*100/$stages.Count))
    Write-Host ('[{0}/{1}] {2}' -f $i,$stages.Count,$stage.Label)
    $t=Get-Date
    try {
        $result=@()
        $stageStatus='OK';$stageDetail=''
        switch ($key) {
            Installations {$result=@(Get-PCADInstallations);break}
            Processes {$result=@(Get-PCADProcesses);break}
            Services {$result=@(Get-PCADServices);break}
            Catalog {
                $catalog=Get-PCADExecutableCatalog -Installations @($sections['Installations']) -Services @($sections['Services'])
                $result=@($catalog.Entries)
                $sections['CatalogWarnings']=@($catalog.Warnings)
                if($catalog.Status -ne 'OK'){$stageStatus='PARCIAL';$stageDetail='Catalogo limitado; ver CatalogWarnings'}
                break
            }
            Firewall {$result=@(Get-PCADFirewall);break}
            Tasks {$result=@(Get-PCADTasks);break}
            Historico {$result=@(Get-PCADLegacyOverview -Firewall @($sections['Firewall']) -Tasks @($sections['Tasks']));break}
            Connections {$result=@(Get-PCADConnections -Processes @($sections['Processes']));break}
        }
        $sections[$key]=@($result)
        [void]$checks.Add([pscustomobject]@{
            Section=$key;Status=$stageStatus;Count=@($result).Count
            Seconds=[math]::Round(((Get-Date)-$t).TotalSeconds,2);Detail=$stageDetail
        })
        if($stageStatus -eq 'OK') { Write-Host ('  OK: {0} elementos' -f @($result).Count) -ForegroundColor Green }
        else { Write-Host ('  PARCIAL: {0} elementos. {1}' -f @($result).Count,$stageDetail) -ForegroundColor Yellow }
    } catch {
        $sections[$key]=@()
        $errorType=$_.Exception.GetType().Name
        [void]$checks.Add([pscustomobject]@{
            Section=$key;Status='ERROR';Count=0
            Seconds=[math]::Round(((Get-Date)-$t).TotalSeconds,2)
            Detail=('Consulta incompleta ({0}); cero no significa ausencia.' -f $errorType)
        })
        Write-Host ('  ERROR: consulta parcial ({0})' -f $errorType) -ForegroundColor Yellow
    }
}
Write-Progress -Activity 'ParcheCAD 4.0 / Diagnostico de solo lectura' -Completed
$errors=@($checks | Where-Object {$_.Status -ne 'OK'}).Count
$overall=if($errors -gt 0){'PARCIAL_NO_VERIFICADO'}else{'DIAGNOSTICO_COMPLETADO_SIN_CAMBIOS'}
$report=[ordered]@{
    SchemaVersion=1;Tool='ParcheCAD';Phase='F0';ReadOnly=$true
    GeneratedAt=(Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    Result=$overall;ElapsedSeconds=[math]::Round(((Get-Date)-$started).TotalSeconds,2)
    Limit='Inventario puntual; NO verifica bloqueo total de trafico ni ausencia de WebView2.'
    Privacy='Sin IP remotas ni argumentos completos. Revisar antes de compartir.'
    Checks=@($checks.ToArray());Sections=$sections
}
$folder=''
if (!$NoExport) {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory=Join-Path (Split-Path -Parent $PSScriptRoot) 'informes'
    }
    try {
        if (!(Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $OutputDirectory -Force -ErrorAction Stop | Out-Null
        }
        $folder=Join-Path $OutputDirectory ((Get-Date).ToString('yyyyMMdd_HHmmss_fff'))
        New-Item -ItemType Directory -Path $folder -ErrorAction Stop | Out-Null
        $utf8=New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText((Join-Path $folder 'diagnostico.json'),($report | ConvertTo-Json -Depth 9),$utf8)
        $lines=New-Object System.Collections.Generic.List[string]
        $lines.Add('ParcheCAD 4.0 F0 - SOLO LECTURA')
        $lines.Add(('Resultado: {0}' -f $overall))
        $lines.Add(('Fecha: {0}' -f $report.GeneratedAt))
        $lines.Add('')
        foreach ($c in $checks) {
            $lines.Add(('{0}: {1} / {2} elementos / {3}s. {4}' -f $c.Section,$c.Status,$c.Count,$c.Seconds,$c.Detail))
        }
        $lines.Add('')
        $lines.Add('No se modifico firewall, registro, tareas ni servicios.')
        $lines.Add('No publicar informes sin revisar datos personales.')
        [IO.File]::WriteAllLines((Join-Path $folder 'resumen.txt'),$lines,$utf8)
    } catch {
        Write-Host ('Error al exportar informe: {0}' -f $_.Exception.GetType().Name) -ForegroundColor Yellow
        $overall='PARCIAL_ERROR_EXPORTACION';$errors++
    }
}
Write-Host ''
Write-Host ('Estado: {0}' -f $overall)
if ($folder) {Write-Host ('Informes locales: {0}' -f $folder)}
Write-Host 'F0 no creo ni retiro ninguna regla de firewall.'
if ($errors -gt 0) {exit 2}
exit 0
