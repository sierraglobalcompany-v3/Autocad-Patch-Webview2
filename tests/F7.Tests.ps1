# F7: no permitir reglas nuevas con journals incompletos o corruptos.
# Solo archivos temporales; no consulta ni escribe el firewall real.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'src\ParcheCAD.Core.ps1')
. (Join-Path $repo 'src\ParcheCAD.Historico.ps1')

function Assert-F7([bool]$ok,[string]$reason){if(!$ok){throw ('F7 FAIL: '+$reason)}}
function Assert-F7ApplyDenied([string]$dir,[string]$reason){
    $denied=$false
    try{$null=Assert-PCADRecoveryReady -JournalDirectory $dir}
    catch{$denied=$true}
    Assert-F7 $denied $reason
}
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('PCAD-F7-'+[guid]::NewGuid().ToString('N'))
$noJournals=Join-Path $tmp 'not-created'
$dir=Join-Path $tmp 'journals'
try{
    $null=New-Item -ItemType Directory -Path $dir -Force
    $empty=Get-PCADRecoveryOverview -JournalDirectory $noJournals
    Assert-F7 ($empty.Status -eq 'SIN_RESPALDOS') 'missing journal directory is safe'
    $null=Assert-PCADRecoveryReady -JournalDirectory $noJournals

    $applied=[pscustomobject]@{
        Schema='PCAD4_OPERATION_1';Status='APPLIED';
        Operations=@([pscustomobject]@{State='CREATED'})
    }
    $good=Join-Path $dir 'PCAD4_good.json'
    $applied|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $good -Encoding UTF8
    $safe=Get-PCADRecoveryOverview -JournalDirectory $dir
    Assert-F7 ($safe.Status -eq 'OK' -and $safe.ActiveRules -eq 1) 'valid committed manifest does not block'
    $null=Assert-PCADRecoveryReady -JournalDirectory $dir

    $crashed=[pscustomobject]@{
        Schema='PCAD4_OPERATION_1';Status='PREPARED';
        Operations=@([pscustomobject]@{State='CREATING'})
    }
    $crashFile=Join-Path $dir 'PCAD4_crashed.json'
    $crashed|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $crashFile -Encoding UTF8
    $state=Get-PCADRecoveryOverview -JournalDirectory $dir
    Assert-F7 ($state.Status -eq 'PARCIAL' -and $state.NeedsReview -eq 1) 'incomplete journal must be partial'
    Assert-F7ApplyDenied $dir 'incomplete journal must reject Apply'
    Remove-Item -LiteralPath $crashFile -Force

    $bad=Join-Path $dir 'PCAD4_corrupt.json'
    [IO.File]::WriteAllText($bad,'not-json')
    $state=Get-PCADRecoveryOverview -JournalDirectory $dir
    Assert-F7 ($state.Status -eq 'PARCIAL' -and $state.Unverified -eq 1) 'corrupt manifest must be partial'
    Assert-F7ApplyDenied $dir 'corrupt manifest must reject Apply'
    Remove-Item -LiteralPath $bad -Force

    $pending=Join-Path $dir 'PCAD4_good.json.pending'
    [IO.File]::WriteAllText($pending,'interrupted-write')
    $state=Get-PCADRecoveryOverview -JournalDirectory $dir
    Assert-F7 ($state.Status -eq 'PARCIAL' -and $state.PendingFiles -eq 1 -and $state.NeedsReview -gt 0) 'pending write detected'
    Assert-F7ApplyDenied $dir 'pending write must reject Apply'
    Remove-Item -LiteralPath $pending -Force

    $backup=Join-Path $dir 'PCAD4_orphan.json.prev'
    [IO.File]::WriteAllText($backup,'old-operation')
    $state=Get-PCADRecoveryOverview -JournalDirectory $dir
    Assert-F7 ($state.Status -eq 'PARCIAL' -and $state.OrphanBackups -eq 1) 'orphan backup detected'
    Assert-F7ApplyDenied $dir 'orphan backup must reject Apply'
    Remove-Item -LiteralPath $backup -Force

    $final=Get-PCADRecoveryOverview -JournalDirectory $dir
    Assert-F7 ($final.Status -eq 'OK' -and $final.NeedsReview -eq 0) 'clean manifest store allows Apply again'
    $null=Assert-PCADRecoveryReady -JournalDirectory $dir
}finally{
    if(Test-Path -LiteralPath $tmp -PathType Container){Remove-Item -LiteralPath $tmp -Recurse -Force}
}
Write-Host 'PASS F7: clean, incomplete, corrupt, pending and orphan journal protections.' -ForegroundColor Green
