# F12: evaluator for diagnostic snapshots; READ ONLY, NO firewall or network changes.
# Never certify RC1 based on two inventory snapshots.
Set-StrictMode -Version 2.0

function Get-PCADGateField {
    [CmdletBinding()]
    param($Object,[string]$Name)
    if($null -eq $Object){return $null}
    if($Object -is [System.Collections.IDictionary]){
        if($Object.Contains($Name)){return $Object[$Name]}
        return $null
    }
    $property=$Object.PSObject.Properties[$Name]
    if($null -eq $property){return $null}
    return $property.Value
}
function Get-PCADGateRows {
    [CmdletBinding()]
    param($Object,[string]$Name)
    $value=Get-PCADGateField -Object $Object -Name $Name
    foreach($item in @($value)){if($null -ne $item){Write-Output $item}}
}
function Get-PCADGateSnapshot {
    [CmdletBinding()]
    param($Report)
    $expected=@('Installations','Processes','Services','Catalog','Firewall',
        'Tasks','Historico','Connections','NetworkOverview','PolicyPreview')
    $checks=@(Get-PCADGateRows -Object $Report -Name 'Checks')
    $section=Get-PCADGateField -Object $Report -Name 'Sections'
    $seen=@{}
    $stageValid=($checks.Count -eq $expected.Count)
    foreach($check in $checks){
        $name=[string](Get-PCADGateField -Object $check -Name 'Section')
        $state=[string](Get-PCADGateField -Object $check -Name 'Status')
        if($name -notin $expected -or $seen.ContainsKey($name) -or $state -cne 'OK'){
            $stageValid=$false
        }
        $seen[$name]=$true
    }
    $baseValid=([string](Get-PCADGateField -Object $Report -Name 'Tool') -ceq 'ParcheCAD' -and
        [string](Get-PCADGateField -Object $Report -Name 'Result') -ceq 'DIAGNOSTICO_COMPLETADO_SIN_CAMBIOS' -and
        [int](Get-PCADGateField -Object $Report -Name 'SchemaVersion') -eq 1 -and
        (Get-PCADGateField -Object $Report -Name 'ReadOnly') -ceq $true)
    $hist=@(Get-PCADGateRows -Object $section -Name 'Historico')
    $recovery=if($hist.Count -eq 1){Get-PCADGateField -Object $hist[0] -Name 'Recovery'}else{$null}
    $recoveryOK=($null -ne $recovery -and
        [string](Get-PCADGateField -Object $recovery -Name 'Status') -in @('OK','SIN_RESPALDOS') -and
        [int](Get-PCADGateField -Object $recovery -Name 'NeedsReview') -eq 0 -and
        [int](Get-PCADGateField -Object $recovery -Name 'Unverified') -eq 0)
    $coverageRows=@(Get-PCADGateRows -Object $section -Name 'Coverage')
    $coverage=if($coverageRows.Count -eq 1){$coverageRows[0]}else{$null}
    $coverageOK=($null -ne $coverage -and
        [string](Get-PCADGateField -Object $coverage -Name 'Schema') -ceq 'PCAD_COVERAGE_1' -and
        [string](Get-PCADGateField -Object $coverage -Name 'Status') -ceq 'COBERTURA_NO_CERTIFICADA' -and
        (Get-PCADGateField -Object $coverage -Name 'ReadOnly') -ceq $true -and
        (Get-PCADGateField -Object $coverage -Name 'AllAutodeskTrafficBlockedVerified') -ceq $false -and
        (Get-PCADGateField -Object $coverage -Name 'AutoCADWebViewLaunchPreventedVerified') -ceq $false -and
        (Get-PCADGateField -Object $coverage -Name 'WebViewIsolatedFromOtherAppsVerified') -ceq $false)
    $inst=@(Get-PCADGateRows -Object $section -Name 'Installations')
    $present=@($inst | Where-Object {(Get-PCADGateField -Object $_ -Name 'FileFound') -eq $true -and
        [int](Get-PCADGateField -Object $_ -Name 'Year') -ge 2023 -and
        [int](Get-PCADGateField -Object $_ -Name 'Year') -le 2027})
    $versions=@($present | ForEach-Object {[int](Get-PCADGateField -Object $_ -Name 'Year')} | Sort-Object -Unique)
    $candidate=if($coverageOK){[int](Get-PCADGateField -Object $coverage -Name 'CandidateProgramRules')}else{0}
    $configured=if($coverageOK){[int](Get-PCADGateField -Object $coverage -Name 'ProgramRulesPresent')}else{0}
    $missing=if($coverageOK){[int](Get-PCADGateField -Object $coverage -Name 'ProgramRulesMissing')}else{0}
    $unknown=if($coverageOK){[int](Get-PCADGateField -Object $coverage -Name 'ProgramRulesUnknown')}else{0}
    $countsOK=($candidate -ge 0 -and $configured -ge 0 -and $missing -ge 0 -and
        $unknown -ge 0 -and ($configured+$missing+$unknown) -le $candidate)
    return [pscustomobject]@{
        Valid=($baseValid -and $stageValid -and $recoveryOK -and $coverageOK -and $countsOK)
        ChecksValid=$stageValid
        RecoveryValid=$recoveryOK
        CoverageValid=$coverageOK
        Years=$versions
        InstallationsFound=$present.Count
        ProgramRuleCandidates=$candidate
        ProgramRulesConfigured=$configured
        ProgramRulesMissing=$missing
        ProgramRulesUnknown=$unknown
    }
}
function Get-PCADRC12Assessment {
    [CmdletBinding()]
    param($Before,$After)
    $pre=Get-PCADGateSnapshot -Report $Before
    $post=Get-PCADGateSnapshot -Report $After
    $rows=New-Object System.Collections.ArrayList
    function Add-PCADGate {
        param([string]$Id,[string]$State,[string]$Evidence,[string]$Reason)
        [void]$rows.Add([pscustomobject]@{Gate=$Id;Status=$State;Evidence=$Evidence;Reason=$Reason})
    }
    $snapshotsOK=($pre.Valid -and $post.Valid)
    Add-PCADGate 'DIAGNOSTICOS' $(if($snapshotsOK){'PASS'}else{'BLOCKED'}) 'JSON F11 sin rutas/IP' 'Exigir dos informes validos de diez etapas y recuperacion sana.'
    $installOK=($snapshotsOK -and $post.InstallationsFound -gt 0)
    Add-PCADGate 'AUTOCAD_INSTALADO' $(if($installOK){'OBSERVADO'}else{'BLOCKED'}) 'Registro y archivo acad.exe detectados' 'La presencia del archivo no demuestra firma, autenticidad ni funcionamiento de AutoCAD.'
    $configOK=($installOK -and $post.ProgramRuleCandidates -gt 0 -and
        $post.ProgramRulesConfigured -eq $post.ProgramRuleCandidates -and
        $post.ProgramRulesMissing -eq 0 -and $post.ProgramRulesUnknown -eq 0)
    Add-PCADGate 'REGLAS_SALIENTES' $(if($configOK){'CONFIGURACION_OBSERVADA'}else{'BLOCKED'}) 'Estado de regla por ruta y grupo PCAD4' 'Las reglas no demuestran que todo el trafico de Autodesk este bloqueado.'
    Add-PCADGate 'TRAFICO_AUTODESK' 'BLOCKED' 'No hay prueba de conectividad repetida antes/despues' 'Faltan TCP/UDP IPv4/IPv6, servicios y proxies; una instantanea no basta.'
    Add-PCADGate 'WEBVIEW2_AUTOCAD' 'BLOCKED' 'No probado' 'No se ha demostrado que AutoCAD no lance WebView2 ni que este aislado del runtime compartido.'
    Add-PCADGate 'OTRAS_APLICACIONES' 'BLOCKED' 'No probado' 'WhatsApp, Outlook y otras aplicaciones con WebView2 deben seguir funcionando.'
    Add-PCADGate 'GUI_UAC' 'BLOCKED' 'WinForms sin escritorio real' 'Falta UAC aceptada/denegada, DPI, clics, errores y evidencia visual.'
    Add-PCADGate 'REINICIO_Y_ROLLBACK' 'BLOCKED' 'Recuperacion de segundo PowerShell solamente' 'Falta reinicio/apagado del sistema durante operacion y restauracion comprobada.'
    Add-PCADGate 'AVG_ACTIVO' 'BLOCKED' 'No probado en PC objetivo' 'Se requiere validar sin desactivar el antivirus.'
    Add-PCADGate 'AUTOCAD_FUNCIONAL' 'BLOCKED' 'No probado con AutoCAD real' 'Registrar funciones que se pierden por operar sin conexion y aceptacion del alcance.'
    return [pscustomobject]@{
        Schema='PCAD_RC12_GATES_1'
        ReadOnly=$true
        Decision='BLOCKED'
        ProductionCertified=$false
        AllAutodeskTrafficBlockedVerified=$false
        WebViewIsolatedVerified=$false
        Before=$pre
        After=$post
        Gates=@($rows.ToArray())
        Limit='Evaluacion solo lectura. No aprobar RC1 con estas evidencias. Sin rutas privadas ni IP.'
    }
}
