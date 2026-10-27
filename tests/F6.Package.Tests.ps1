# F6: validates reproducible allowlisted ZIP and extracted scripts on Windows.
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('PCAD-F6-PACK-'+[guid]::NewGuid().ToString('N'))
$dir1=Join-Path $tmp 'build1';$dir2=Join-Path $tmp 'build2';$unpacked=Join-Path $tmp 'unpacked'
$zipName='ParcheCAD_4.3_DEV_NO_RELEASE.zip'
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
    if(@($manifest).Count -lt 20){throw 'Package manifest incomplete'}
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
    # Runtime packages must not reproduce archival stage reports or continuity noise.
    foreach($outdated in @('PROJECT_CONTINUITY_CURRENT.md','docs/V41_CAMBIOS_AUDITORIA.md',
                          'docs/V42_ARQUITECTURA_QA.md','docs/F0_GUIA_USO_Y_QA.md',
                          'docs/F9_WINFORMS_EVENT_QA.md')){
        if(Test-Path -LiteralPath (Join-Path $unpacked $outdated)){
            throw ('Lote C: outdated document leaked into development ZIP: '+$outdated)
        }
    }
    foreach($required in @('README.md','docs/SPEC_MAESTRA.md','docs/V43_DASHBOARD_WPF.md',
                           'docs/F17_PROTOCOLO_QA_INTEGRADA.md','Abrir_ParcheCAD_Clasico.cmd')){
        if(!(Test-Path -LiteralPath (Join-Path $unpacked $required) -PathType Leaf)){
            throw ('Lote C: missing current documentation/fallback: '+$required)
        }
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
    # F17 packaged executable is required for disaster recovery on another PC.
    foreach($required in @('tools\Invoke-ParcheCADF17.ps1',
                           'tools\Invoke-ParcheCADRC12.ps1',
                           'src\ParcheCAD.RCGates.ps1',
                           'src\ParcheCAD.Diagnostico.ps1',
                           'src\ParcheCAD.Monitor.ps1',
        'src\ParcheCAD.WebViewAudit.ps1',
        'src\ParcheCAD.Preview.ps1',
                           'docs\F17_PROTOCOLO_QA_INTEGRADA.md')){
        $p=Join-Path $unpacked $required
        if(!(Test-Path -LiteralPath $p -PathType Leaf)){throw ('F17 missing from extracted ZIP: '+$required)}
    }
    # Synthetic evidence only: smoke the F17 CLI FROM the extracted ZIP, not the source tree.
    # Never call Before/After here: the live hosted-Windows smoke tests those modes.
    $f17session=Join-Path $tmp 'F17-PACKAGED-FIXTURE'
    $pre=Join-Path $f17session 'before\fixture'
    $post=Join-Path $f17session 'after\fixture'
    $null=New-Item -ItemType Directory -Path $pre -Force
    $null=New-Item -ItemType Directory -Path $post -Force
    $stages=@('Installations','Processes','Services','Catalog','Firewall','Tasks',
              'Historico','Connections','NetworkOverview','PolicyPreview')
    $fixture=[ordered]@{
        SchemaVersion=1;Tool='ParcheCAD';GeneratedAt='2026-10-21T09:00:00-05:00'
        ReadOnly=$true;Result='DIAGNOSTICO_COMPLETADO_SIN_CAMBIOS'
        Checks=@($stages|ForEach-Object {[pscustomobject]@{Section=$_;Status='OK'}})
        Sections=[ordered]@{
            Installations=@()
            Historico=@([pscustomobject]@{Recovery=[pscustomobject]@{Status='SIN_RESPALDOS';NeedsReview=0;Unverified=0}})
            Coverage=@([pscustomobject]@{
                Schema='PCAD_COVERAGE_1';ReadOnly=$true;Status='COBERTURA_NO_CERTIFICADA'
                CandidateProgramRules=0;ProgramRulesPresent=0;ProgramRulesMissing=0;ProgramRulesUnknown=0
                AllAutodeskTrafficBlockedVerified=$false
                AutoCADWebViewLaunchPreventedVerified=$false
                WebViewIsolatedFromOtherAppsVerified=$false
            })
        }
    }
    [IO.File]::WriteAllText((Join-Path $pre 'diagnostico.json'),($fixture|ConvertTo-Json -Depth 9))
    $fixture.GeneratedAt='2026-10-21T09:05:00-05:00'
    [IO.File]::WriteAllText((Join-Path $post 'diagnostico.json'),($fixture|ConvertTo-Json -Depth 9))
    & $exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $unpacked 'tools\Invoke-ParcheCADF17.ps1') -Mode Evaluate -SessionDirectory $f17session
    if($LASTEXITCODE -ne 0){throw 'Extracted F17 Evaluate CLI failed on synthetic fixture.'}
    $matrix=Get-Content -LiteralPath (Join-Path $f17session 'evaluacion\F17_MATRIZ_EVIDENCIA.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if($matrix.Decision -cne 'BLOCKED' -or $matrix.ProductionCertified -ne $false -or
       @($matrix.Gates).Count -ne 10 -or !$matrix.ContentsDistinctVerified -or
       !$matrix.TimestampOrderVerified -or $matrix.SameMachineVerified -ne $false){
        throw 'Extracted F17 gave an unsafe or incomplete RC assessment.'
    }
    # From extracted ZIP: run the read-only monitor for a bounded 2-second smoke.
    $monitorDir=Join-Path $tmp 'F17-MONITOR-PACKAGED'
    & $exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $unpacked 'src\ParcheCAD.Monitor.ps1') -OutputDirectory $monitorDir -DurationSeconds 2 -IntervalMilliseconds 500
    if($LASTEXITCODE -ne 0){throw 'Extracted temporary monitor failed.'}
    $mon=Get-Content -LiteralPath (Join-Path $monitorDir 'monitor.json') -Raw | ConvertFrom-Json
    if($mon.Schema -cne 'PCAD_MONITOR_1' -or $mon.BlockedTrafficVerified -ne $false -or
       $mon.WebViewIsolationVerified -ne $false -or $mon.Result -cne 'MONITOREO_COMPLETADO_OBSERVACIONAL'){
        throw 'Extracted monitor failed to preserve observational limits.'
    }

    # V4.3: assets WPF, launcher principal y interfaz clasica de respaldo.
    foreach($item in @('src\ParcheCAD.Dashboard.ps1','src\ParcheCAD.Dashboard.xaml','Abrir_ParcheCAD_Clasico.cmd','docs\V43_DASHBOARD_WPF.md')){
        if(!(Test-Path -LiteralPath (Join-Path $unpacked $item) -PathType Leaf)){throw ('V43 missing asset: '+$item)}
    }
    & $exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $unpacked 'src\ParcheCAD.Dashboard.ps1') -SelfTest
    if($LASTEXITCODE -ne 0){throw 'V43 WPF extracted SelfTest failed.'}
    # V4.1: los PS1 procedentes de ZIP externo pueden tener Mark-of-the-Web.
    # Probar sobre copia extraida, sin quitar marcas ni modificar politicas.
    $cmd=Get-Content -LiteralPath (Join-Path $unpacked 'Abrir_ParcheCAD.cmd') -Raw
    if($cmd -notmatch 'ParcheCAD\.Dashboard\.ps1'){throw 'V43 launcher did not select WPF.'}
    $uiSrc=Get-Content -LiteralPath (Join-Path $unpacked 'src\ParcheCAD.Panel.ps1') -Raw
    if($cmd -notmatch 'ExecutionPolicy Bypass' -or $uiSrc -match 'ExecutionPolicy RemoteSigned' -or
       @([regex]::Matches($uiSrc,'ExecutionPolicy Bypass')).Count -ne 5){
        throw 'V42: launcher y cinco procesos hijos no usan politica temporal.'
    }
    $psScripts=@(Get-ChildItem -LiteralPath (Join-Path $unpacked 'src') -Filter '*.ps1' -File)
    foreach($ps in $psScripts){
        Set-Content -LiteralPath $ps.FullName -Stream Zone.Identifier -Value @('[ZoneTransfer]','ZoneId=3') -ErrorAction Stop
    }
    Push-Location $unpacked
    try{
        & $env:ComSpec /d /c 'Abrir_ParcheCAD.cmd --selftest'
        if($LASTEXITCODE -ne 0){throw 'WPF packaged GUI SelfTest with MOTW failed.'}
        & $exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $unpacked 'src\ParcheCAD.Dashboard.ps1') -StateSelfTest
        if($LASTEXITCODE -ne 0){throw 'WPF packaged StateSelfTest with MOTW failed.'}
    }finally{Pop-Location}
    # V42: auditar WebView2 desde el paquete extraido, sin instalar AutoCAD ni reglas.
    $auditDir=Join-Path $tmp 'WEBVIEW-PACKAGED'
    $null=New-Item -ItemType Directory -Path $auditDir -ErrorAction Stop
    & $exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $unpacked 'src\ParcheCAD.WebViewAudit.ps1') -OutputDirectory $auditDir
    if($LASTEXITCODE -ne 0){throw 'V42: auditoria WebView2 empaquetada fallo'}
    $audit=Get-Content -LiteralPath (Join-Path $auditDir 'webview-audit.json') -Raw | ConvertFrom-Json
    if($audit.Schema -cne 'PCAD_WEBVIEW_AUDIT_1' -or $audit.NoFirewallChanges -ne $true -or
       $audit.SafeBlockingCandidates -ne 0 -or @($audit.Entries | Where-Object {$_.AutomaticFirewallEligible -ne $false}).Count -gt 0){
        throw 'V42: auditoria invento un candidato bloqueable o afirmo modificar firewall'
    }
    # F42: the ZIP must contain a functional and independently executable
    # PREVIEW worker; it must return a marker and an explicitly read-only plan.
    $previewDir=Join-Path $tmp 'AUTOCAD-PREVIEW-PACKAGED'
    $null=New-Item -ItemType Directory -Path $previewDir -ErrorAction Stop
    & $exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $unpacked 'src\ParcheCAD.Preview.ps1') -OutputDirectory $previewDir
    if($LASTEXITCODE -ne 0){throw 'F42: packaged preview worker failed.'}
    $pr=Get-Content -LiteralPath (Join-Path $previewDir 'preview.json') -Raw | ConvertFrom-Json
    $prCode=(Get-Content -LiteralPath (Join-Path $previewDir 'preview.exitcode') -Raw).Trim()
    if($prCode -cne '0' -or $pr.Schema -cne 'PCAD_AUTOCAD_PREVIEW_1' -or
       $pr.ReadOnly -ne $true -or $pr.NoFirewallChanges -ne $true -or
       $pr.WebView2SharedExcluded -ne $true -or
       $pr.Candidates -lt 0 -or $pr.Conflicts -lt 0 -or
       $pr.Status -notin @('PREVIEW_COMPLETA','PREVIEW_PARCIAL')){
        throw 'F42: preview output invalid or reports unsafe changes.'
    }
    $stage=Get-Content -LiteralPath (Join-Path $previewDir 'preview.fase.txt') -Raw
    if($stage -notmatch '3/3'){throw 'F42: preview did not report phase completion.'}
    Write-Host ('PASS F6 package: SHA256, {0} current files, WPF/WinForms fallback, preview/WebView2 and recovery' -f $verified) -ForegroundColor Green
} finally {
    if(Test-Path -LiteralPath $tmp -PathType Container){Remove-Item -LiteralPath $tmp -Recurse -Force}
}
