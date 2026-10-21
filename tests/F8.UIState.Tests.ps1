# F8: comprobar el modelo unico de estado WinForms con informes falsos, incompletos y contradicciones.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$uiScript=Join-Path $root 'src\ParcheCAD.UIState.ps1'
$panelScript=Join-Path $root 'src\ParcheCAD.Panel.ps1'
foreach($file in @($uiScript,$panelScript)){
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    if(@($errors).Count){throw ('F8 parser failed: '+$file+' '+($errors|Out-String))}
}
. $uiScript
function Assert-F8([bool]$Test,[string]$Label) {if(!$Test){throw ('F8 FAIL: '+$Label)}}
$stages=@('Installations','Processes','Services','Catalog','Firewall','Tasks',
          'Historico','Connections','NetworkOverview','PolicyPreview')
function New-F8GoodReport {
    $checks=@($stages | ForEach-Object{[pscustomobject]@{Section=$_;Status='OK';Count=0;Detail=''}})
    [pscustomobject]@{
        SchemaVersion=1;Tool='ParcheCAD';Phase='F0-F5_DIAGNOSTICO';ReadOnly=$true
        Result='DIAGNOSTICO_COMPLETADO_SIN_CAMBIOS';ElapsedSeconds=0.1
        Checks=$checks
        Sections=[pscustomobject]@{
            PolicyPreview=@([pscustomobject]@{State='PLAN_NO_APLICADO';Count=2;Conflicts=0;Excluded=@();Entries=@()})
            Historico=@([pscustomobject]@{Recovery=[pscustomobject]@{Status='OK';NeedsReview=0;Unverified=0}})
        }
    }
}
$none=Get-PCADReportUiState -Report $null -ExitCode $null
Assert-F8 (!$none.Complete -and !$none.CanApply) 'no report must be invalid'
$empty=Get-PCADReportUiState -Report ([pscustomobject]@{Result='DIAGNOSTICO_COMPLETADO_SIN_CAMBIOS'}) -ExitCode 0
Assert-F8 (!$empty.Complete -and !$empty.CanApply) 'incomplete report denied'
$good=New-F8GoodReport
$ok=Get-PCADReportUiState -Report $good -ExitCode 0
Assert-F8 ($ok.Complete -and $ok.CanApply -and $ok.CanPreview -and $ok.ChecksOK -and $ok.RecoveryOK) 'good 10 stage report'
$badExit=Get-PCADReportUiState -Report $good -ExitCode 2
Assert-F8 (!$badExit.Complete -and !$badExit.CanApply) 'exit code contradicts report'
$missingExit=Get-PCADReportUiState -Report $good
Assert-F8 (!$missingExit.Complete -and !$missingExit.CanApply) 'no process result'
$good.Result='PARCIAL_NO_VERIFICADO'
Assert-F8 (!(Get-PCADReportUiState -Report $good -ExitCode 0).Complete) 'reported partial despite exit zero'
$good.Result='DIAGNOSTICO_COMPLETADO_SIN_CAMBIOS'
$good.Sections.Historico[0].Recovery.Status='PARCIAL'
$pending=Get-PCADReportUiState -Report $good -ExitCode 0
Assert-F8 (!$pending.CanApply -and !$pending.Complete) 'rollback pending must not be shown COMPLETE'
$good.Sections.Historico[0].Recovery.Status='OK'
$good.Sections.PolicyPreview[0].Conflicts=1
Assert-F8 (!(Get-PCADReportUiState -Report $good -ExitCode 0).CanApply) 'plan collision'
$good.Sections.PolicyPreview[0].Conflicts=0
$good.Checks[0].Status='ERROR'
Assert-F8 (!(Get-PCADReportUiState -Report $good -ExitCode 0).Complete) 'one stage error'
$good.Checks[0].Status='OK'
$good.Checks[0].Section='PolicyPreview'
Assert-F8 (!(Get-PCADReportUiState -Report $good -ExitCode 0).ChecksOK) 'duplicate stage replacing installation'
$good.Checks[0].Section='Installations'
$good.Tool='UNKNOWN'
Assert-F8 (!(Get-PCADReportUiState -Report $good -ExitCode 0).Complete) 'wrong tool'
$good.Tool='ParcheCAD'
$good.ReadOnly=$false
Assert-F8 (!(Get-PCADReportUiState -Report $good -ExitCode 0).Complete) 'mutating report not accepted'
$good.ReadOnly=$true
$good.Sections.Historico=@()
Assert-F8 (!(Get-PCADReportUiState -Report $good -ExitCode 0).CanApply) 'missing recovery info'
$good.Sections.Historico=@([pscustomobject]@{Recovery=[pscustomobject]@{Status='OK';NeedsReview=0;Unverified=0}})
$good.Sections.PolicyPreview=@()
Assert-F8 (!(Get-PCADReportUiState -Report $good -ExitCode 0).CanApply) 'missing plan'
# Legacy or corrupt serialized objects should be handled as read-only/incomplete, never throw.
$unknown=@('{}','[]','{"Result":"DIAGNOSTICO_COMPLETADO_SIN_CAMBIOS"}','{"Checks":null}')
foreach($json in $unknown){
    $report=ConvertFrom-Json -InputObject $json
    $ui=Get-PCADReportUiState -Report $report -ExitCode 0
    Assert-F8 (!$ui.CanApply) 'untrusted json cannot enable apply'
}
Write-Host 'PASS F8: report schema, stage identities, conflicting exit codes, missing fields, recovery and plan eligibility.' -ForegroundColor Green
