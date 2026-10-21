# F0: inventario; no toca firewall, registro, servicios ni tareas.
[CmdletBinding()]
param([string]$OutputDirectory='',[switch]$NoExport,[switch]$WriteExitMarker)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if($WriteExitMarker -and ($NoExport -or [string]::IsNullOrWhiteSpace($OutputDirectory))) {
    throw 'WriteExitMarker requiere directorio de salida y exportacion habilitada.'
}
. (Join-Path $PSScriptRoot 'ParcheCAD.Core.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Catalogo.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Historico.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Network.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Policy.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Evidence.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Cobertura.ps1')

$started=Get-Date
$sections=[ordered]@{}
$privateInstallations=@()
$privateCatalog=@()
$checks=New-Object System.Collections.ArrayList
$stages=@(
    @{Key='Installations';Label='AutoCAD 2023-2027'},
    @{Key='Processes';Label='Procesos AutoCAD y WebView2'},
    @{Key='Services';Label='Servicios Autodesk'},
    @{Key='Catalog';Label='Catalogo de ejecutables por version'},
    @{Key='Firewall';Label='Reglas heredadas y activas'},
    @{Key='Tasks';Label='Tareas programadas'},
    @{Key='Historico';Label='Resumen de bloqueos anteriores'},
    @{Key='Connections';Label='Conexiones TCP y endpoints UDP'},
    @{Key='NetworkOverview';Label='Atribucion WebView2 y conexiones'},
    @{Key='PolicyPreview';Label='Vista previa de reglas salientes'}
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
            Installations {
                $privateInstallations=@(Get-PCADInstallations -InternalPaths)
                $result=@($privateInstallations | ForEach-Object {ConvertTo-PCADSafeRecord -Record $_ -PathFields @('Path')})
                break
            }
            Processes {$result=@(Get-PCADProcesses);break}
            Services {$result=@(Get-PCADServices);break}
            Catalog {
                $catalog=Get-PCADExecutableCatalog -Installations $privateInstallations -Services @($sections['Services']) -InternalPaths
                $privateCatalog=@($catalog.Entries)
                $result=@($privateCatalog | ForEach-Object {ConvertTo-PCADSafeRecord -Record $_ -PathFields @('Path','InstallationRoot')})
                $sections['CatalogWarnings']=@($catalog.Warnings)
                $sections['CatalogScope']=@([pscustomobject]@{
                    ProductStatus=$catalog.Status
                    SharedStatus=$catalog.SharedStatus
                    SharedAutomaticBlocking=$false
                    InventoryOnly=$true
                })
                if($catalog.Status -ne 'OK'){$stageStatus='PARCIAL';$stageDetail='Catalogo limitado; ver CatalogWarnings'}
                break
            }
            Firewall {$result=@(Get-PCADFirewall);break}
            Tasks {$result=@(Get-PCADTasks);break}
            Historico {
                $journalDirectory=Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'informes') 'operaciones'
                $result=@(Get-PCADLegacyOverview -Firewall @($sections['Firewall']) -Tasks @($sections['Tasks']) -JournalDirectory $journalDirectory)
                if($result.Count -ne 1 -or $result[0].Recovery.Status -notin @('OK','SIN_RESPALDOS') -or
                   [int]$result[0].Recovery.NeedsReview -gt 0 -or [int]$result[0].Recovery.Unverified -gt 0) {
                    $stageStatus='PARCIAL'
                    $stageDetail='Recuperacion o respaldos sin verificar: revisar antes de aplicar nuevas reglas.'
                }
                break
            }
            Connections {$result=@(Get-PCADConnections -Processes @($sections['Processes']));break}
            NetworkOverview {$result=@(Get-PCADNetworkOverview -Processes @($sections['Processes']) -Connections @($sections['Connections']));break}
            PolicyPreview {
                $internalPlan=New-PCADRulePlan -Catalog $privateCatalog -CheckExisting
                $result=@(ConvertTo-PCADSafePlan -Plan $internalPlan)
                # Seccion F11 adicional de solo lectura; SIN modificar las diez etapas,
                # los permisos o las condiciones del control Apply.
                $networkRows=@($sections['NetworkOverview'])
                $networkInfo=if($networkRows.Count -gt 0){$networkRows[0]}else{$null}
                $sections['Coverage']=@(Get-PCADCoverageReport `
                    -Catalog $privateCatalog -Services @($sections['Services']) `
                    -Processes @($sections['Processes']) -Connections @($sections['Connections']) `
                    -Plan $internalPlan -NetworkOverview $networkInfo)
                break
            }
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
    SchemaVersion=1;Tool='ParcheCAD';Phase='F0-F5_DIAGNOSTICO';ReadOnly=$true
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
        $lines.Add('ParcheCAD 4.0 - DIAGNOSTICO SOLO LECTURA')
        $lines.Add(('Resultado: {0}' -f $overall))
        $lines.Add(('Fecha: {0}' -f $report.GeneratedAt))
        $lines.Add('')
        foreach ($c in $checks) {
            $lines.Add(('{0}: {1} / {2} elementos / {3}s. {4}' -f $c.Section,$c.Status,$c.Count,$c.Seconds,$c.Detail))
        }
        $lines.Add('')
        $coverageRows=@($sections['Coverage'])
        if($coverageRows.Count -gt 0){
            $cov=$coverageRows[0]
            $lines.Add('F11 MATRIZ DE COBERTURA: NO CERTIFICADA / SOLO OBSERVACIONAL')
            $lines.Add(('EXE candidatos: {0}; regla presente: {1}; ausente: {2}; desconocida: {3}' -f $cov.CandidateProgramRules,$cov.ProgramRulesPresent,$cov.ProgramRulesMissing,$cov.ProgramRulesUnknown))
            $lines.Add(('Servicios Autodesk inventariados: {0}; TCP observados: {1}; endpoints UDP: {2}' -f $cov.AutodeskServicesInventoried,$cov.TcpEntriesObserved,$cov.UdpEndpointsObserved))
            foreach($row in @($cov.Rows)){
                $lines.Add(('{0}: {1} / {2} / {3}' -f $row.Category,$row.Count,$row.Policy,($row.Names -join ', ')))
            }
            $lines.Add('Ausencia de trafico y aislamiento de WebView2: NO VERIFICADOS')
            $lines.Add('')
        }
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
Write-Host 'ParcheCAD F0-F4 no creo ni retiro ninguna regla durante este diagnostico.'
$exitCode=if($errors -gt 0){2}else{0}
if($WriteExitMarker){
    try {
        # Unique per-run directory supplied by Panel; this is an explicit
        # completion protocol, not a firewall modification or arbitrary path.
        $marker=Join-Path $OutputDirectory 'diagnostico.exitcode'
        [IO.File]::WriteAllText($marker,[string]$exitCode,(New-Object Text.UTF8Encoding($false)))
    } catch {
        Write-Warning 'No se pudo registrar el final del diagnostico; el panel debe marcarlo parcial.'
        $exitCode=2
    }
}
exit $exitCode
