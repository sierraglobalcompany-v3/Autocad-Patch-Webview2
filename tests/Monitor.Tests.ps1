# Monitor end-to-end tests on Windows: read-only, no AutoCAD, no firewall mutation.
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'src\ParcheCAD.Monitor.ps1'
$parserTokens=$null;$parserErrors=$null
$null=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$parserTokens,[ref]$parserErrors)
if(@($parserErrors).Count){throw ('Monitor parser failed: '+($parserErrors | Out-String))}
$content=Get-Content -LiteralPath $source -Raw -ErrorAction Stop
if($content -match '(?i)\b(New-NetFirewallRule|Set-NetFirewallRule|Remove-NetFirewallRule|auditpol|Stop-Service|Remove-ItemProperty|Stop-Process)\b'){
    throw 'Monitor must not modify firewall, audit policies, services or applications.'
}
$exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('PCAD-MONITOR-TEST-'+[guid]::NewGuid().ToString('N'))
$session=Join-Path $tmp 'session'
$stopSession=Join-Path $tmp 'stop-session'
$proc=$null
try {
    $null=New-Item -ItemType Directory -Path $tmp -Force
    & $exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File $source -OutputDirectory $session -DurationSeconds 2 -IntervalMilliseconds 500
    if($LASTEXITCODE -ne 0){throw 'Monitor duration exit failure.'}
    $report=Get-Content -LiteralPath (Join-Path $session 'monitor.json') -Raw -ErrorAction Stop | ConvertFrom-Json
    if($report.Schema -cne 'PCAD_MONITOR_1' -or $report.Result -cne 'MONITOREO_COMPLETADO_OBSERVACIONAL' -or
       $report.BlockedTrafficVerified -ne $false -or $report.WebViewIsolationVerified -ne $false -or
       [int]$report.Samples -lt 1 -or [int]$report.IntervalMilliseconds -ne 500){
        throw 'Monitor duration report invalid or falsely certified.'
    }
    $raw=Get-Content -LiteralPath (Join-Path $session 'monitor.json') -Raw
    if($raw -match '(?i)C:\\Users\\|RemoteAddress|CommandLine|--user-data-dir|https?://'){
        throw 'Monitor leaked private paths, command line or addresses.'
    }
    $marker=(Get-Content -LiteralPath (Join-Path $session 'monitor.exitcode') -Raw).Trim()
    if($marker -cne '0'){throw 'Monitor success marker missing.'}
    # A second run must never overwrite evidence.
    $oldPref=$ErrorActionPreference
    try{
        $ErrorActionPreference='Continue'
        & $exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File $source -OutputDirectory $session -DurationSeconds 2 -IntervalMilliseconds 500 *> $null
        $overwrittenExit=$LASTEXITCODE
    }finally{$ErrorActionPreference=$oldPref}
    if($overwrittenExit -eq 0){throw 'Monitor overwrote an existing session.'}
    # Explicit stop should preserve the report instead of killing the child.
    $arguments='-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "{0}" -OutputDirectory "{1}" -DurationSeconds 45 -IntervalMilliseconds 500' -f $source,$stopSession
    $proc=Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -PassThru -ErrorAction Stop
    for($i=0;$i -lt 60 -and !(Test-Path -LiteralPath $stopSession -PathType Container);$i++){Start-Sleep -Milliseconds 250}
    if(!(Test-Path -LiteralPath $stopSession -PathType Container)){throw 'Monitor child never created session directory.'}
    [IO.File]::WriteAllText((Join-Path $stopSession 'detener.solicitud'),'STOP')
    if(!$proc.WaitForExit(30000)){throw 'Monitor did not respond to stop request.'}
    if([int]$proc.ExitCode -ne 0){throw 'Monitor stop did not exit cleanly.'}
    $stopped=Get-Content -LiteralPath (Join-Path $stopSession 'monitor.json') -Raw | ConvertFrom-Json
    if($stopped.StopReason -cne 'USUARIO' -or $stopped.Result -cne 'MONITOREO_COMPLETADO_OBSERVACIONAL'){
        throw 'Explicit stop report missing or invalid.'
    }
    $global:LASTEXITCODE=0
    Write-Host 'PASS Monitor: completed, stop request, private output, no overwrite and no false certification.' -ForegroundColor Green
}finally{
    if($null -ne $proc){
        try{$proc.Refresh();if(!$proc.HasExited){$proc.Kill();$proc.WaitForExit(5000)|Out-Null}}catch{}
        try{$proc.Dispose()}catch{}
    }
    if(Test-Path -LiteralPath $tmp -PathType Container){Remove-Item -LiteralPath $tmp -Recurse -Force}
}
