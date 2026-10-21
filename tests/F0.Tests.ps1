# Pruebas sin dependencias externas, validas en Windows PowerShell 5.1.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$core=Join-Path $root 'src\ParcheCAD.Core.ps1'
$runner=Join-Path $root 'src\ParcheCAD.Diagnostico.ps1'
foreach($file in @($core,$runner)){
    $tokens=$null;$errors=$null
    $null=[System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {throw ('Error de parser en {0}: {1}' -f $file,($errors|Out-String))}
}
. $core
function Assert-Eq([object]$Actual,[object]$Expected,[string]$Reason){
    if ($Actual -cne $Expected) {throw ('FAIL {0}: {1} != {2}' -f $Reason,$Actual,$Expected)}
}
Assert-Eq (Test-PCADAutoCADName 'AutoCAD 2023 - English') $true '2023'
Assert-Eq (Test-PCADAutoCADName 'Autodesk AutoCAD 2027 - English') $true '2027'
Assert-Eq (Test-PCADAutoCADName 'AutoCAD LT 2027') $false 'sin LT'
Assert-Eq (Test-PCADAutoCADName 'AutoCAD 2022') $false 'limite inferior'
Assert-Eq (Test-PCADAutoCADName 'AutoCAD 2028') $false 'limite superior'
Assert-Eq (Get-PCADLegacyKind 'PCAD_A_V3_abcd' '') 'PARCHECAD' 'historica'
Assert-Eq (Get-PCADLegacyKind 'WebView2GlobalBlock.foo.Inbound' '') 'WEBVIEW2_HISTORICO' 'WebView2 antiguo'
Assert-Eq (Get-PCADLegacyKind 'regla-otra' 'otra aplicacion') 'AJENO_O_DESCONOCIDO' 'regla ajena'
Assert-Eq (Get-PCADProperty ([pscustomobject]@{Execute='powershell.exe'}) 'Arguments') '' 'tarea sin Arguments'
Assert-Eq (Protect-PCADPath 'C:\Users\Felipe\AppData\Local\config') 'C:\Users\[USUARIO]\AppData\Local\config' 'ruta usuario'
Assert-Eq (Protect-PCADPath '\\equipo\usuarios\privado') '[RUTA_RED_OCULTA]' 'ruta UNC'
Assert-Eq (Get-PCADRemoteScope '127.0.0.1') 'LOOPBACK' 'loopback'
Assert-Eq (Get-PCADRemoteScope '192.168.1.1') 'PRIVADA_LOCAL' 'red local'
Assert-Eq (Get-PCADRemoteScope '1.1.1.1') 'PUBLICA_O_ESPECIAL' 'red publica'
$view=Get-PCADProcessClass -Name 'msedgewebview2.exe' -Path 'C:\Microsoft\msedgewebview2.exe' -Parent 'acad.exe' -UserData ''
Assert-Eq $view.Attribution 'AUTOCAD_PROBABLE' 'parent solo probable'
$other=Get-PCADProcessClass -Name 'msedgewebview2.exe' -Path 'C:\Microsoft\msedgewebview2.exe' -Parent 'WhatsApp.exe' -UserData ''
Assert-Eq $other.Attribution 'INDETERMINADA' 'no atribuir apps ajenas'
foreach($file in @($core,$runner)){
    $text=[IO.File]::ReadAllText($file)
    if ($text -match '(?im)\b(?:New|Set|Remove|Disable|Enable|Register|Unregister)-NetFirewallRule\b|\b(?:Set|Remove|Register|Unregister|Disable|Enable)-ScheduledTask\b|\bnetsh\s+advfirewall\b') {
        throw ('Comando de firewall/tareas de mutacion detectado: {0}' -f $file)
    }
}
Write-Host 'PASS: parser, clasificacion, privacidad y prueba negativa de mutaciones.' -ForegroundColor Green
