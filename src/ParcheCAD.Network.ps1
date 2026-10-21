# F3 - atribucion observacional de procesos y conexiones, solo lectura.
# Ninguna coincidencia PID/PPID demuestra ausencia de otras conexiones ni identidad absoluta.
Set-StrictMode -Version 2.0

function Get-PCADWebViewHost {
    [CmdletBinding()]
    param([object]$WebView,[AllowEmptyCollection()][object[]]$Processes=@())
    $name=[string]$WebView.Name
    if($name -ine 'msedgewebview2.exe') {
        return [pscustomobject]@{Owner='NO_WEBVIEW2';Year=0;Confidence='NO_APLICA';Evidence='No es msedgewebview2.exe'}
    }
    $byPid=@{}
    foreach($p in @($Processes)) { if($null -ne $p) {$byPid[[string]$p.PID]=$p} }
    $year=0;$signals=New-Object System.Collections.ArrayList
    $hint=('{0} {1}' -f [string]$WebView.UserDataFolder,[string]$WebView.HostHint)
    $m=[regex]::Match($hint,'(?i)AutoCAD\s+(202[3-7])')
    if($m.Success) {
        $year=[int]$m.Groups[1].Value
        [void]$signals.Add('UDF/host hint AutoCAD')
    }
    $parentId=[string]$WebView.ParentPID
    $visited=@{}; $depth=0
    while($parentId -and $parentId -ne '0' -and $depth -lt 12) {
        if($visited.ContainsKey($parentId)) {break}
        $visited[$parentId]=$true
        if(!$byPid.ContainsKey($parentId)) {break}
        $parent=$byPid[$parentId]
        if([string]$parent.Name -ieq 'acad.exe') {
            $match=[regex]::Match([string]$parent.ExecutablePath,'(?i)AutoCAD\s+(202[3-7])')
            $parentYear=if($match.Success){[int]$match.Groups[1].Value}else{0}
            if($year -and $parentYear -and $year -ne $parentYear) {
                return [pscustomobject]@{Owner='CONFLICTO';Year=0;Confidence='INDETERMINADA';Evidence='UDF y proceso anfitrion no coinciden'}
            }
            if($parentYear){$year=$parentYear}
            [void]$signals.Add('Arbol PID actual hacia acad.exe')
            break
        }
        $parentId=[string]$parent.ParentPID
        $depth++
    }
    if($signals.Count -gt 0){
        return [pscustomobject]@{
            Owner='AUTOCAD_PROBABLE';Year=$year;Confidence='PROBABLE'
            Evidence=($signals -join ' + ')
        }
    }
    return [pscustomobject]@{Owner='INDETERMINADO';Year=0;Confidence='INDETERMINADA';Evidence='Sin cadena padre/UDF concluyente'}
}
function Get-PCADNetworkOverview {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Processes=@(),[AllowEmptyCollection()][object[]]$Connections=@())
    $web=New-Object System.Collections.ArrayList;$warnings=New-Object System.Collections.ArrayList
    $owners=@{}
    foreach($p in @($Processes)) {
        if($null -eq $p){continue}
        $owners[[string]$p.PID]=$p
        if([string]$p.Name -ine 'msedgewebview2.exe') {continue}
        $hostInfo=Get-PCADWebViewHost -WebView $p -Processes $Processes
        $tcp=@($Connections | Where-Object {$_ -and $_.Protocol -eq 'TCP' -and [string]$_.PID -eq [string]$p.PID})
        $udp=@($Connections | Where-Object {$_ -and $_.Protocol -eq 'UDP_ENDPOINT' -and [string]$_.PID -eq [string]$p.PID})
        [void]$web.Add([pscustomobject]@{
            PID=[int]$p.PID;ParentPID=[int]$p.ParentPID
            Owner=$hostInfo.Owner;Year=$hostInfo.Year;Confidence=$hostInfo.Confidence
            Evidence=$hostInfo.Evidence;ObservedTcpConnections=$tcp.Count
            ObservedUdpEndpoints=$udp.Count;BlockedConnectionVerified=$false
        })
    }
    $otherTCP=@($Connections | Where-Object {
        if($null -eq $_ -or [string]$_.Protocol -ne 'TCP'){return $false}
        $pidKey=[string]$_.PID
        if(!$owners.ContainsKey($pidKey)){return $false}
        return ([string]$owners[$pidKey].Classification -like 'AUTOCAD*' -or
                [string]$owners[$pidKey].Classification -like 'AUTODESK*')
    })
    [void]$warnings.Add('Instantanea de conexiones; no demuestra ausencia de trafico. TCP y UDP tienen cobertura diferente.')
    [void]$warnings.Add('Proceso padre/UDF: atribucion probable; PID pueden cambiar o reutilizarse.')
    [void]$warnings.Add('WebView2 compartido no debe bloquearse globalmente para otras aplicaciones.')
    return [pscustomobject]@{
        TotalWebView2=@($web.ToArray()).Count
        ProbableAutoCAD=@($web.ToArray() | Where-Object {$_.Owner -eq 'AUTOCAD_PROBABLE'}).Count
        WebViewIndeterminate=@($web.ToArray() | Where-Object {$_.Owner -eq 'INDETERMINADO'}).Count
        AutodeskOwnedTcpSnapshot=$otherTCP.Count
        WebViewSessions=@($web.ToArray());Warnings=@($warnings.ToArray())
        IsolationVerified=$false;TrafficAbsenceVerified=$false
        Status='OBSERVACION_SIN_BLOQUEO'
    }
}
