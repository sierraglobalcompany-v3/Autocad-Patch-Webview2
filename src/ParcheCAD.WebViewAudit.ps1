# ParcheCAD 4.2: auditoria puntual SOLO de WebView2.
# No crea reglas, no mata procesos ni modifica servicios o firewall.
#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ParcheCAD.Core.ps1')
. (Join-Path $PSScriptRoot 'ParcheCAD.Network.ps1')
$dest=[IO.Path]::GetFullPath($OutputDirectory)
if($dest -match '^\\\\'){throw 'No se permiten carpetas de red.'}
$walk=$dest
while($walk){
    if(Test-Path -LiteralPath $walk){
        if(((Get-Item -LiteralPath $walk -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'Directorio enlazado o junction no permitido.'
        }
    }
    $up=[IO.Path]::GetDirectoryName($walk)
    if(!$up -or $up -eq $walk){break}
    $walk=$up
}
if(!(Test-Path -LiteralPath $dest -PathType Container)){throw 'Directorio de sesion inexistente.'}
$reportFile=Join-Path $dest 'webview-audit.json'
$summaryFile=Join-Path $dest 'webview-resumen.txt'
$marker=Join-Path $dest 'webview-audit.exitcode'
foreach($file in @($reportFile,$summaryFile,$marker)){
    if(Test-Path -LiteralPath $file){throw 'Auditoria existente: no sobrescribir.'}
}
$utf8=New-Object Text.UTF8Encoding($false)
try{
    $processes=@(Get-PCADProcesses)
    $connections=@(Get-PCADConnections -Processes $processes)
    $overview=Get-PCADNetworkOverview -Processes $processes -Connections $connections
    $rows=New-Object System.Collections.ArrayList
    foreach($w in @($overview.WebViewSessions)){
        $category=if($w.Owner -eq 'AUTOCAD_PROBABLE'){'AUTOCAD_PROBABLE'}else{'COMPARTIDO_O_INDETERMINADO'}
        [void]$rows.Add([pscustomobject]@{
            PID=[int]$w.PID
            ParentPID=[int]$w.ParentPID
            Attribution=$category
            Confidence=[string]$w.Confidence
            Evidence=[string]$w.Evidence
            TCPObserved=[int]$w.ObservedTcpConnections
            UDPEndpointsObserved=[int]$w.ObservedUdpEndpoints
            Runtime='WEBVIEW2_MICROSOFT_COMPARTIDO'
            AutomaticFirewallEligible=$false
            Reason='Ruta de runtime compartida: PID/padre no son identidad persistente para una regla.'
        })
    }
    $report=[ordered]@{
        Schema='PCAD_WEBVIEW_AUDIT_1';Tool='ParcheCAD';Version='4.2'
        ReadOnly=$true;GeneratedAt=(Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        Status='AUDITORIA_WEBVIEW_COMPLETADA'
        TotalWebView2=$rows.Count
        ProbableAutoCAD=@($rows.ToArray()|Where-Object {$_.Attribution -eq 'AUTOCAD_PROBABLE'}).Count
        Indeterminate=@($rows.ToArray()|Where-Object {$_.Attribution -ne 'AUTOCAD_PROBABLE'}).Count
        SafeBlockingCandidates=0
        NoFirewallChanges=$true
        IsolationVerified=$false
        BlockedTrafficVerified=$false
        Entries=@($rows.ToArray())
        Limit='Instantanea y relacion probable; no prueba bloqueo o ausencia de trafico. Nunca bloquear runtime compartido por PID.'
    }
    [IO.File]::WriteAllText($reportFile,($report|ConvertTo-Json -Depth 8),$utf8)
    $message=@(
        'ParcheCAD 4.2 - AUDITORIA WEBVIEW2 (SOLO LECTURA)'
        ('WebView2 observados: {0}; AutoCAD probable: {1}; indeterminados: {2}' -f $rows.Count,$report.ProbableAutoCAD,$report.Indeterminate)
        'Candidatos de bloqueo seguro: 0. WebView2 compartido excluido.'
        'El proceso padre/PID no autorizan bloqueo selectivo; no se aplicaron reglas.'
        'NO CERTIFICADO: bloqueo de trafico, aislamiento de WebView2 y ausencia de otras llamadas.'
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText($summaryFile,$message,$utf8)
    [IO.File]::WriteAllText($marker,'0',$utf8)
    Write-Host $message
    exit 0
}catch{
    try{[IO.File]::WriteAllText($marker,'2',$utf8)}catch{}
    Write-Error ('Auditoria WebView2 parcial: '+$_.Exception.Message)
    exit 2
}
