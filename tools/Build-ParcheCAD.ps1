# Build curated DEVELOPMENT ZIP; no publishing or installing software.
[CmdletBinding()]
param([string]$OutputDirectory='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(!$OutputDirectory){$OutputDirectory=Join-Path $root 'dist'}
$items=@(
    'Abrir_ParcheCAD.cmd',
    'README.md',
    'PROJECT_CONTINUITY_CURRENT.md',
    'src/ParcheCAD.Core.ps1',
    'src/ParcheCAD.Catalogo.ps1',
    'src/ParcheCAD.Historico.ps1',
    'src/ParcheCAD.Network.ps1',
    'src/ParcheCAD.Policy.ps1',
    'src/ParcheCAD.Firewall.ps1',
    'src/ParcheCAD.Evidence.ps1',
    'src/ParcheCAD.Diagnostico.ps1',
    'src/ParcheCAD.Reglas.ps1',
    'src/ParcheCAD.Panel.ps1',
    'src/ParcheCAD.UIState.ps1',
    'docs/SPEC_MAESTRA.md',
    'docs/F0_GUIA_USO_Y_QA.md',
    'docs/F1F2_IMPLEMENTACION_QA.md',
    'docs/F3F4_IMPLEMENTACION_QA.md',
    'docs/F4_INTERFAZ_QA_REAL.md',
    'docs/F5_INTEGRACION_RECUPERACION_QA.md',
    'docs/F6_PAQUETE_PRE_RC.md',
    'docs/F7_FAILCLOSED_GUI_QA.md',
    'docs/F8_UISTATE_QA.md',
    'docs/F9_WINFORMS_EVENT_QA.md',
    'docs/F10_PROCESOS_RECUPERACION_QA.md'
) | Sort-Object
foreach($name in $items){
    if($name -notmatch '^[a-zA-Z0-9_/.-]+$' -or $name -match '(?:^|/)\.\.(?:/|$)') {
        throw "Ruta fuera del allowlist: $name"
    }
    $file=Join-Path $root ($name.Replace('/',[IO.Path]::DirectorySeparatorChar))
    if(!(Test-Path -LiteralPath $file -PathType Leaf)){throw "Archivo faltante: $name"}
}
if(!(Test-Path -LiteralPath $OutputDirectory -PathType Container)){
    $null=New-Item -ItemType Directory -Path $OutputDirectory -Force -ErrorAction Stop
}
$zipName='ParcheCAD_4.0_DEV_NO_RELEASE.zip'
$zipFile=Join-Path $OutputDirectory $zipName
Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
$time=[DateTimeOffset]::Parse('2020-01-01T00:00:00+00:00')
$manifestLines=New-Object 'System.Collections.Generic.List[string]'
$fs=[IO.File]::Open($zipFile,[IO.FileMode]::Create,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {
    $zip=[IO.Compression.ZipArchive]::new($fs,[IO.Compression.ZipArchiveMode]::Create,$true)
    try {
        foreach($name in $items){
            $file=Join-Path $root ($name.Replace('/',[IO.Path]::DirectorySeparatorChar))
            $hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            $manifestLines.Add("$hash  $name")
            $entry=$zip.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime=$time
            $inputFile=[IO.File]::OpenRead($file)
            try {
                $outputStream=$entry.Open()
                try {$inputFile.CopyTo($outputStream)}
                finally {$outputStream.Dispose()}
            } finally {$inputFile.Dispose()}
        }
        $manifest=$zip.CreateEntry('SHA256SUMS.txt',[IO.Compression.CompressionLevel]::Optimal)
        $manifest.LastWriteTime=$time
        $stream=$manifest.Open()
        try {
            $writer=[IO.StreamWriter]::new($stream,([Text.UTF8Encoding]::new($false)))
            try {$writer.Write(($manifestLines -join [Environment]::NewLine)+[Environment]::NewLine)}
            finally {$writer.Dispose()}
        } finally {$stream.Dispose()}
    } finally {$zip.Dispose()}
} finally {$fs.Dispose()}
$zipHash=(Get-FileHash -LiteralPath $zipFile -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $OutputDirectory ($zipName+'.sha256')),("$zipHash  $zipName"+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
Write-Host ('PASS: curated development ZIP ({0} files) SHA256 {1}' -f ($items.Count+1),$zipHash) -ForegroundColor Green
Write-Host $zipFile
