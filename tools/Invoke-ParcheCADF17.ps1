# F17: orchestrate a single LAB read-only before/after capture and F12 evaluation.
# Never applies firewall rules, changes Windows policy, launches AutoCAD or certifies RC1.
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Before','After','Evaluate')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$SessionDirectory
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\ParcheCAD.RCGates.ps1') # F12 single read-only snapshot validator
$session=[IO.Path]::GetFullPath($SessionDirectory).TrimEnd([char]'\')
$repo=[IO.Path]::GetFullPath($root).TrimEnd([char]'\')
if($session -match '^\\\\' -or $session -match '^[A-Za-z]:$' -or
   $session.Equals($repo,[StringComparison]::OrdinalIgnoreCase) -or
   $session.StartsWith(($repo+'\'),[StringComparison]::OrdinalIgnoreCase)){
    throw 'La sesion F17 debe estar fuera del repositorio, en carpeta local independiente.'
}
# Reject existing symlink/junction components in the evidence destination.
$cursor=$session
while($cursor){
    if(Test-Path -LiteralPath $cursor){
        $attributes=(Get-Item -LiteralPath $cursor -Force -ErrorAction Stop).Attributes
        if(($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'Directorio de evidencia con junction o enlace: abortar.'
        }
    }
    $parent=[IO.Path]::GetDirectoryName($cursor)
    if([string]::IsNullOrEmpty($parent) -or $parent -eq $cursor){break}
    $cursor=$parent
}
function Get-PCADF17Snapshot([string]$Phase){
    $folder=Join-Path $session $Phase
    if(!(Test-Path -LiteralPath $folder -PathType Container)){
        throw ('Falta captura independiente de la etapa '+$Phase)
    }
    $matches=@(Get-ChildItem -LiteralPath $folder -File -Recurse -Filter 'diagnostico.json' -ErrorAction Stop)
    if($matches.Count -ne 1){throw ('F17 requiere exactamente un diagnostico.json en '+$Phase)}
    # A phase may contain nested folders; reject redirected evidence locations.
    $part=$matches[0].FullName
    while($part -and $part.StartsWith(($session+'\'),[StringComparison]::OrdinalIgnoreCase)){
        $entry=Get-Item -LiteralPath $part -Force -ErrorAction Stop
        if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'Ruta de diagnostico con enlace/junction; evidencia no aceptada.'
        }
        $part=[IO.Path]::GetDirectoryName($part)
    }
    return $matches[0].FullName
}
function Get-PCADF17Capture([string]$Path){
    if((Get-Item -LiteralPath $Path -ErrorAction Stop).Length -gt 12MB){
        throw 'Informe de diagnostico demasiado grande para evaluar.'
    }
    $report=Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $snapshot=Get-PCADGateSnapshot -Report $report
    if(!$snapshot.Valid){throw 'Captura F17 parcial o inconsistente; STOP, no comparar.'}
    $stamp=[DateTimeOffset]::MinValue
    if(![DateTimeOffset]::TryParseExact([string]$report.GeneratedAt,'yyyy-MM-ddTHH:mm:sszzz',
        [Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$stamp)){
        throw 'Captura sin GeneratedAt valido; no hay evidencia temporal.'
    }
    return [pscustomobject]@{Time=$stamp;Hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash}
}
$psExe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if(!(Test-Path -LiteralPath $psExe -PathType Leaf)){
    throw 'F17 requiere Windows con PowerShell 5.1.'
}
if($Mode -eq 'Before' -or $Mode -eq 'After'){
    if($Mode -eq 'After'){$null=Get-PCADF17Capture (Get-PCADF17Snapshot 'before')}
    $phase=$Mode.ToLowerInvariant()
    $destination=Join-Path $session $phase
    if(Test-Path -LiteralPath $destination){throw ('Captura ya existe; no sobrescribir: '+$phase)}
    $null=New-Item -ItemType Directory -Path $destination -Force -ErrorAction Stop
    # The child diagnostic is read-only and writes local reports under the phase folder.
    & $psExe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $root 'src\ParcheCAD.Diagnostico.ps1') -OutputDirectory $destination
    if($LASTEXITCODE -ne 0){throw ('Diagnostico '+$phase+' parcial o fallido; STOP, revisar localmente.')}
    $null=Get-PCADF17Capture (Get-PCADF17Snapshot $phase)
    Write-Host ('F17 '+$phase+': captura de solo lectura guardada LOCALMENTE; no demuestra bloqueo.') -ForegroundColor Green
    return
}
$before=Get-PCADF17Snapshot 'before'
$after=Get-PCADF17Snapshot 'after'
if($before.Equals($after,[StringComparison]::OrdinalIgnoreCase)){
    throw 'F17 exige archivos antes/despues separados.'
}
$beforeEvidence=Get-PCADF17Capture $before
$afterEvidence=Get-PCADF17Capture $after
if($beforeEvidence.Hash -ceq $afterEvidence.Hash){
    throw 'Dos rutas con el mismo contenido no son dos capturas independientes; STOP.'
}
if($afterEvidence.Time -le $beforeEvidence.Time){
    throw 'Fecha de After debe ser posterior a Before; revisar reloj o captura duplicada.'
}
$resultDir=Join-Path $session 'evaluacion'
if(Test-Path -LiteralPath $resultDir){
    throw 'La evaluacion ya existe; crear una nueva sesion para evitar sobrescribir evidencia.'
}
$null=New-Item -ItemType Directory -Path $resultDir -Force -ErrorAction Stop
& $psExe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $root 'tools\Invoke-ParcheCADRC12.ps1') -Before $before -After $after -OutputDirectory $resultDir
if($LASTEXITCODE -ne 0){throw 'Evaluacion F12 fallida; ninguna aprobacion permitida.'}
$assessment=Get-Content -LiteralPath (Join-Path $resultDir 'RC12_EVALUACION.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
if($assessment.Decision -cne 'BLOCKED' -or $assessment.ProductionCertified -ne $false -or
    @($assessment.Gates).Count -ne 10){
    throw 'F17 STOP: evaluador F12 inesperadamente no seguro.'
}
# These are EVIDENCE REQUIREMENTS, not attestations; private captures stay outside GitHub.
$needs=@{
    DIAGNOSTICOS='Dos capturas diferentes, entorno/tiempo y recuperacion sana'
    AUTOCAD_INSTALADO='Autenticidad y ejecucion de cada version instalada'
    REGLAS_SALIENTES='Reglas propias y politica efectiva, sin conflictos'
    TRAFICO_AUTODESK='Trazas autorizadas TCP/UDP IPv4/IPv6 por proceso/servicio antes/durante/despues'
    WEBVIEW2_AUTOCAD='Observacion del host y trafico WebView2 sin bloqueo global del runtime'
    OTRAS_APLICACIONES='Outlook/WhatsApp antes y despues; sin regresion'
    GUI_UAC='Capturas y acciones UAC aceptada/denegada, foco, DPI y cancelacion'
    REINICIO_Y_ROLLBACK='Snapshot, reinicio real, recuperacion y reversibilidad verificadas'
    AVG_ACTIVO='AV activo sin alertas no resueltas; no desactivarlo'
    AUTOCAD_FUNCIONAL='Funciones autorizadas y consecuencias documentadas sin red'
}
$rows=@($assessment.Gates | ForEach-Object {
    [pscustomobject]@{
        Gate=[string]$_.Gate
        F12Status=[string]$_.Status
        ExternalEvidence='PENDING_REVIEW'
        RequiredEvidence=[string]$needs[[string]$_.Gate]
    }
})
$matrix=[pscustomobject]@{
    Schema='PCAD_F17_EVIDENCE_1'
    Scope='LAB_ONLY'
    ReadOnly=$true
    Decision='BLOCKED'
    ProductionCertified=$false
    EvidenceReviewed=$false
    CapturesSeparate=$true
    ContentsDistinctVerified=$true
    TimestampOrderVerified=$true
    SameMachineVerified=$false
    Gates=$rows
    Limit='Las capturas F0/F12 son instantaneas; no certifican trafico, UAC, AVG, WebView2 ni reboot.'
    Privacy='No adjuntar trazas crudas, IP, credenciales, usuarios, seriales ni rutas privadas a GitHub.'
}
[IO.File]::WriteAllText((Join-Path $resultDir 'F17_MATRIZ_EVIDENCIA.json'),
    ($matrix | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
Write-Host 'F17: matriz de 10 puertas generada. RC1 BLOCKED hasta QA fisica, evidencias y revision.' -ForegroundColor Yellow
