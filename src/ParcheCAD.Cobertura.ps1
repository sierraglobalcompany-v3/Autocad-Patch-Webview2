# F11 — Matriz de cobertura informativa. NO aplica reglas ni acredita trafico bloqueado.
# Mantener las diez etapas del diagnostico; esta matriz es una seccion adicional.
Set-StrictMode -Version 2.0

function Get-PCADCoverageName {
    [CmdletBinding()]
    param([AllowNull()][string]$Name)
    if(!$Name){return 'NO_IDENTIFICADO'}
    $leaf=[IO.Path]::GetFileName($Name)
    if(!$leaf){return 'NO_IDENTIFICADO'}
    $leaf=[regex]::Replace($leaf,'[\x00-\x1f\x7f]','')
    if($leaf.Length -gt 90){return ($leaf.Substring(0,90)+'...')}
    return $leaf
}
function Get-PCADCoverageReport {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Catalog=@(),
        [AllowEmptyCollection()][object[]]$Services=@(),
        [AllowEmptyCollection()][object[]]$Processes=@(),
        [AllowEmptyCollection()][object[]]$Connections=@(),
        $Plan=$null,
        $NetworkOverview=$null
    )
    $rows=New-Object System.Collections.ArrayList
    $groups=@(
        @{Category='AUTOCAD_PRODUCTO';Policy='CANDIDATO_EXE';Reason='Solo ejecutables que pertenecen a instalacion confirmada; regla no demuestra ausencia de trafico'},
        @{Category='AUTODESK_COMPARTIDO';Policy='EXCLUIDO_AUTOMATICO';Reason='Componente o servicio compartido; el alcance requiere evaluar otras aplicaciones Autodesk'},
        @{Category='WEBVIEW2_COMPARTIDO';Policy='EXCLUIDO_AUTOMATICO';Reason='Microsoft Edge WebView2 es compartido con otras aplicaciones; nunca bloquear por EXE global'},
        @{Category='DESCONOCIDO';Policy='NO_CLASIFICADO';Reason='No se atribuye exclusivamente a AutoCAD; revisar sin agregar reglas'},
        @{Category='SERVICIOS_AUTODESK';Policy='INVENTARIO_NO_BLOQUEADO';Reason='Servicio inventariado no equivale a un EXE de producto ni certifica aislamiento'},
        @{Category='PROCESOS_OBSERVADOS';Policy='INSTANTANEA';Reason='PID y conexiones observados son temporales; UDP endpoint no demuestra comunicacion remota'}
    )
    $list=@($Catalog | Where-Object {$null -ne $_})
    $svcs=@($Services | Where-Object {$null -ne $_})
    $procs=@($Processes | Where-Object {$null -ne $_})
    $conns=@($Connections | Where-Object {$null -ne $_})
    $entries=@()
    if($null -ne $Plan){$entries=@($Plan.Entries | Where-Object {$null -ne $_})}
    $rulePresent=@($entries | Where-Object {$_.Existing -eq 'EXISTS_VALID'}).Count
    $ruleUnknown=@($entries | Where-Object {$_.Existing -notin @('EXISTS_VALID','MISSING')}).Count
    $ruleMissing=@($entries | Where-Object {$_.Existing -eq 'MISSING'}).Count
    $candidates=$entries.Count
    foreach($g in $groups){
        $group=[string]$g.Category
        $members=@()
        if($group -eq 'SERVICIOS_AUTODESK'){$members=$svcs}
        elseif($group -eq 'PROCESOS_OBSERVADOS'){$members=$procs}
        else{$members=@($list | Where-Object {[string]$_.Classification -eq $group})}
        $names=@($members | ForEach-Object {
            $raw=if($group -eq 'SERVICIOS_AUTODESK') {[string]$_.Name}
                 elseif($group -eq 'PROCESOS_OBSERVADOS') {[string]$_.Name}
                 else {[string]$_.Name}
            Get-PCADCoverageName -Name $raw
        } | Sort-Object -Unique)
        # Limit names to avoid unbounded reports and user-specific paths.
        $namesShown=@($names | Select-Object -First 80)
        $row=[pscustomobject]@{
            Category=$group;Count=$members.Count;Policy=[string]$g.Policy
            Evidence='INVENTARIO_O_INSTANTANEA_NO_CERTIFICADA'
            Names=$namesShown;NamesTruncated=($names.Count -gt 80)
            Rationale=[string]$g.Reason
        }
        [void]$rows.Add($row)
    }
    $index=@{}
    foreach($p in $procs){$index[[string]$p.PID]=[string]$p.Classification}
    $observedTcp=0;$observedUdp=0;$uncertainTcp=0
    foreach($c in $conns){
        $protocol=[string]$c.Protocol
        $pidKey=[string]$c.PID
        if($protocol -eq 'TCP'){
            $observedTcp++
            if(!$index.ContainsKey($pidKey) -or $index[$pidKey] -in @('DESCONOCIDO','WEBVIEW2_COMPARTIDO')){
                $uncertainTcp++
            }
        } elseif($protocol -eq 'UDP_ENDPOINT'){$observedUdp++}
    }
    $webView=@($procs | Where-Object {[string]$_.Classification -eq 'WEBVIEW2_COMPARTIDO'}).Count
    $webProbable=0
    if($null -ne $NetworkOverview){$webProbable=[int]$NetworkOverview.ProbableAutoCAD}
    $warnings=@(
        'La cobertura del inventario es parcial: EXE fuera de carpetas detectadas, otros servicios y procesos pueden faltar.',
        'Una regla de firewall presente y valida NO equivale a trafico externo bloqueado y no distingue trafico LAN.',
        'Las conexiones son una instantanea de PID; no detectar TCP ahora NO significa ausencia de conexiones.',
        'UDP_ENDPOINT representa un puerto local, NO un destino remoto ni prueba de aislamiento UDP.',
        'WebView2 compartido excluido; la atribucion AUTOCAD_PROBABLE NO permite aislarlo en el firewall por anfitrion.',
        'No hay validacion de AutoCAD instalado ni pruebas de funcionalidad/licencia y red bajo carga.',
        'No compartir rutas privadas, manifiestos ni identificadores personales; solo nombres de ejecutable/servicio.'
    )
    return [pscustomobject]@{
        Schema='PCAD_COVERAGE_1';ReadOnly=$true;Status='COBERTURA_NO_CERTIFICADA'
        Rows=@($rows.ToArray())
        CandidateProgramRules=$candidates
        ProgramRulesPresent=$rulePresent
        ProgramRulesMissing=$ruleMissing
        ProgramRulesUnknown=$ruleUnknown
        AutodeskServicesInventoried=$svcs.Count
        TcpEntriesObserved=$observedTcp
        TcpEntriesUnattributed=$uncertainTcp
        UdpEndpointsObserved=$observedUdp
        WebViewProcessesObserved=$webView
        WebViewProbableAutoCAD=$webProbable
        AllAutodeskTrafficBlockedVerified=$false
        AutoCADWebViewLaunchPreventedVerified=$false
        WebViewIsolatedFromOtherAppsVerified=$false
        Warnings=$warnings
    }
}
