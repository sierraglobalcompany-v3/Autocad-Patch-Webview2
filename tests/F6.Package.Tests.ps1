# F6: validates reproducible allowlisted ZIP and extracted scripts on Windows.
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('PCAD-F6-PACK-'+[guid]::NewGuid().ToString('N'))
$dir1=Join-Path $tmp 'build1';$dir2=Join-Path $tmp 'build2';$unpacked=Join-Path $tmp 'unpacked'
$zipName='ParcheCAD_4.0_DEV_NO_RELEASE.zip'
try {
    $null=New-Item -ItemType Directory -Path $tmp -Force
    & (Join-Path $repo 'tools\Build-ParcheCAD.ps1') -OutputDirectory $dir1
    & (Join-Path $repo 'tools\Build-ParcheCAD.ps1') -OutputDirectory $dir2
    $p1=Join-Path $dir1 $zipName;$p2=Join-Path $dir2 $zipName
    $hash1=(Get-FileHash -LiteralPath $p1 -Algorithm SHA256).Hash
    $hash2=(Get-FileHash -LiteralPath $p2 -Algorithm SHA256).Hash
    if($hash1 -ne $hash2){throw 'Non-deterministic ZIP build: hashes differ'}
    $external=Get-Content -LiteralPath ($p1+'.sha256') -Raw
    if(!$external.StartsWith($hash1.ToLowerInvariant()+'  ')){throw 'External ZIP checksum mismatch'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    [IO.Compression.ZipFile]::ExtractToDirectory($p1,$unpacked)
    $manifest=Get-Content -LiteralPath (Join-Path $unpacked 'SHA256SUMS.txt') -ErrorAction Stop
    if(@($manifest).Count -lt 16){throw 'Package manifest incomplete'}
    $verified=0
    foreach($line in $manifest){
        $m=[regex]::Match($line,'^([a-f0-9]{64})  ([A-Za-z0-9_./-]+)$')
        if(!$m.Success){throw 'Invalid internal SHA256 manifest line'}
        $relative=$m.Groups[2].Value
        if($relative -match '(?:^|/)\.\.(?:/|$)'){throw 'Unsafe path inside package'}
        $file=Join-Path $unpacked ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
        if(!(Test-Path -LiteralPath $file -PathType Leaf)){throw 'Missing packaged file'}
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $m.Groups[1].Value){
            throw 'Packaged-file SHA256 mismatch'
        }
        $verified++
    }
    if(@(Get-ChildItem -LiteralPath $unpacked -Recurse -File | Where-Object {$_.FullName -match '(?i)\\informes\\|\\\.git\\|password|secret|credential'}).Count -ne 0){
        throw 'Forbidden sensitive path in package'
    }
    $sources=@(Get-ChildItem -LiteralPath (Join-Path $unpacked 'src') -Filter '*.ps1' -File)
    foreach($script in $sources){
        $tokens=$null;$errors=$null
        $null=[Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$errors)
        if(@($errors).Count){throw ('Packaged script does not parse: '+$script.Name)}
    }
    # Independently run the packed CLI in a new PS 5.1 process, read-only.
    $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $exe -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $unpacked 'src\ParcheCAD.Reglas.ps1') -Mode Preview
    if($LASTEXITCODE -ne 0){throw 'Extracted package preview failed'}
    & $exe -NoProfile -STA -File (Join-Path $unpacked 'src\ParcheCAD.Panel.ps1') -SelfTest
    if($LASTEXITCODE -ne 0){throw 'Extracted package WinForms selftest failed'}
    Write-Host ('PASS F6 package: deterministic SHA256, {0} files, extracted CLI and WinForms' -f $verified) -ForegroundColor Green
} finally {
    if(Test-Path -LiteralPath $tmp -PathType Container){Remove-Item -LiteralPath $tmp -Recurse -Force}
}
