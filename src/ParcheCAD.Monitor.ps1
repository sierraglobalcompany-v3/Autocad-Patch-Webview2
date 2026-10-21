# ParcheCAD: temporary read-only process and connection observation.
# Polling cannot see every short-lived process or connection; never certifies blocking.
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [ValidateRange(2,1800)][int]$DurationSeconds=600,
    [ValidateRange(250,5000)][int]$IntervalMilliseconds=1000
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ParcheCAD.Core.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Network.ps1')

$folder=[IO.Path]::GetFullPath($OutputDirectory)
if($folder -match '^\\\\'){throw 'Monitor: no escribir registros en carpetas de red.'}
$cursor=$folder
while($cursor){
    if(Test-Path -LiteralPath $cursor){
        if(((Get-Item -LiteralPath $cursor -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'Monitor: carpeta o padre enlazado/junction no permitido.'
        }
    }
    $parent=[IO.Path]::GetDirectoryName($cursor)
    if(!$parent -or $parent -eq $cursor){break}
    $cursor=$parent
}
if(Test-Path -LiteralPath $folder){throw 'Monitor: usa una carpeta de sesion nueva; no se sobrescriben registros.'}
$null=New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop
$stopPath=Join-Path $folder 'detener.solicitud'
$reportPath=Join-Path $folder 'monitor.json'
$summaryPath=Join-Path $folder 'resumen.txt'
$markerPath=Join-Path $folder 'monitor.exitcode'
$utf8=New-Object Text.UTF8Encoding($false)
$events=New-Object System.Collections.ArrayList
$beforeProc=@{};$beforeConn=@{}
$started=Get-Date;$startClock=[Diagnostics.Stopwatch]::StartNew()
$samples=0;$result='MONITOREO_COMPLETADO_OBSERVACIONAL';$stopReason='DURACION_MAXIMA'
$errorType='';$totalTcp=0;$totalUdp=0
function Add-PCADMonitorRow {
    param([string]$Kind,[string]$Process,[string]$Owner,[string]$Confidence,
        [int]$ProcessId=0,[int]$ParentPID=0,[string]$Protocol='',
        [string]$State='',[int]$RemotePort=0,[string]$RemoteScope='')
    if($events.Count -ge 20000){throw 'MonitorEventLimitExceeded'}
    [void]$events.Add([pscustomobject]@{
        Time=(Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz')
        Event=$Kind;Process=$Process;PID=$ProcessId;ParentPID=$ParentPID
        Attribution=$Owner;Confidence=$Confidence
        Protocol=$Protocol;State=$State;RemotePort=$RemotePort;RemoteScope=$RemoteScope
    })
}
try {
    while($startClock.Elapsed.TotalSeconds -lt $DurationSeconds){
        if(Test-Path -LiteralPath $stopPath -PathType Leaf){$stopReason='USUARIO';break}
        $list=@(Get-PCADProcesses)
        $connections=@(Get-PCADConnections -Processes $list)
        $currentProc=@{};$currentConn=@{}
        foreach($p in $list){
            if($null -eq $p){continue}
            $pidNumber=[int]$p.PID
            $startedValue=[string]$p.Started
            $key=('{0}|{1}|{2}' -f $pidNumber,$startedValue,$p.Name)
            $owner=[string]$p.Classification;$confidence=[string]$p.Attribution
            if([string]$p.Name -ieq 'msedgewebview2.exe'){
                $hostInfo=Get-PCADWebViewHost -WebView $p -Processes $list
                $owner=[string]$hostInfo.Owner;$confidence=[string]$hostInfo.Confidence
            }
            $record=[pscustomobject]@{
                Process=[string]$p.Name;PID=$pidNumber;ParentPID=[int]$p.ParentPID
                Owner=$owner;Confidence=$confidence
            }
            $currentProc[$key]=$record
            if(!$beforeProc.ContainsKey($key)){
                Add-PCADMonitorRow -Kind 'PROCESO_APARECE' -Process $record.Process -Owner $owner -Confidence $confidence -ProcessId $pidNumber -ParentPID $record.ParentPID
            }
        }
        foreach($k in @($beforeProc.Keys)){
            if(!$currentProc.ContainsKey($k)){
                $old=$beforeProc[$k]
                # Disappearance between samples is not proof of process termination.
                Add-PCADMonitorRow -Kind 'PROCESO_NO_OBSERVADO' -Process $old.Process -Owner $old.Owner -Confidence $old.Confidence -ProcessId $old.PID -ParentPID $old.ParentPID
            }
        }
        foreach($c in $connections){
            if($null -eq $c){continue}
            $pidNumber=[int]$c.PID
            $owner='INDETERMINADO';$confidence='INDETERMINADA';$parentPid=0
            $matched=@($currentProc.Values | Where-Object {$_.PID -eq $pidNumber})
            if($matched.Count -gt 0){
                $owner=$matched[0].Owner;$confidence=$matched[0].Confidence
                $parentPid=$matched[0].ParentPID
            }
            $protocol=[string]$c.Protocol;$state=[string]$c.State
            $port=[int]$c.RemotePort;$scope=[string]$c.RemoteScope
            # Deduplicate repeated samples; IP is never written or persisted.
            $key=('{0}|{1}|{2}|{3}|{4}' -f $pidNumber,$protocol,$state,$port,$scope)
            $currentConn[$key]=$true
            if(!$beforeConn.ContainsKey($key)){
                if($protocol -eq 'TCP'){$totalTcp++}
                if($protocol -eq 'UDP_ENDPOINT'){$totalUdp++}
                Add-PCADMonitorRow -Kind 'CONEXION_OBSERVADA' -Process ([string]$c.Process) -Owner $owner -Confidence $confidence -ProcessId $pidNumber -ParentPID $parentPid -Protocol $protocol -State $state -RemotePort $port -RemoteScope $scope
            }
        }
        $beforeProc=$currentProc;$beforeConn=$currentConn;$samples++
        $remaining=[math]::Max(0,$DurationSeconds-$startClock.Elapsed.TotalSeconds)
        if($remaining -le 0){break}
        Start-Sleep -Milliseconds ([int][math]::Min($IntervalMilliseconds,$remaining*1000))
    }
} catch {
    $result='PARCIAL_MONITOREO'
    $stopReason='ERROR_CONSULTA'
    $errorType=$_.Exception.GetType().Name
} finally {
    $startClock.Stop()
    $report=[ordered]@{
        Schema='PCAD_MONITOR_1';Tool='ParcheCAD';ReadOnly=$true
        StartedAt=$started.ToString('yyyy-MM-ddTHH:mm:sszzz')
        FinishedAt=(Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        DurationSeconds=[math]::Round($startClock.Elapsed.TotalSeconds,2)
        IntervalMilliseconds=$IntervalMilliseconds;Samples=$samples
        Result=$result;StopReason=$stopReason;ErrorType=$errorType
        Events=@($events.ToArray())
        ConnectionEventsTcp=$totalTcp;UdpEndpointsObserved=$totalUdp
        BlockedTrafficVerified=$false;WebViewIsolationVerified=$false
        Limit='Sondeo de conexiones TCP y endpoints UDP; NO observa toda llamada ni intentos bloqueados. No prueba ausencia de trafico.'
        Privacy='Sin IP, argumentos, URL, rutas personales ni nombres de usuario. No contiene capturas de paquetes.'
    }
    try {
        [IO.File]::WriteAllText($reportPath,($report | ConvertTo-Json -Depth 7),$utf8)
        $lines=@(
            'ParcheCAD 4.0 - MONITOR TEMPORAL SOLO LECTURA',
            ('Resultado: '+$result),
            ('Motivo de finalizacion: '+$stopReason),
            ('Muestras: '+$samples+' / Eventos: '+$events.Count),
            ('TCP observados (cambios): '+$totalTcp+' / UDP endpoints: '+$totalUdp),
            'WebView2/AutoCAD: ATRIBUCION PROBABLE, no certeza.',
            'Sin IP remotas, URLs, comandos ni rutas privadas.',
            'No se verificaron conexiones bloqueadas ni ausencia absoluta de trafico.',
            'Firewall, antivirus, servicios y programas ajenos: SIN MODIFICACIONES.'
        )
        [IO.File]::WriteAllLines($summaryPath,[string[]]$lines,$utf8)
        [IO.File]::WriteAllText($markerPath,[string]$(if($result -eq 'MONITOREO_COMPLETADO_OBSERVACIONAL'){0}else{2}),$utf8)
    } catch {
        Write-Host 'Monitor: no se pudo completar exportacion; revisar archivo de errores local.' -ForegroundColor Yellow
        exit 2
    }
}
if($result -eq 'MONITOREO_COMPLETADO_OBSERVACIONAL'){
    Write-Host ('Monitor de solo lectura finalizado; informe local, {0} muestras.' -f $samples)
    exit 0
}
Write-Host ('Monitor parcial: {0}; ninguna conclusion sobre ausencia de trafico.' -f $errorType) -ForegroundColor Yellow
exit 2
