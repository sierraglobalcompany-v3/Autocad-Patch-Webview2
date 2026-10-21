# ParcheCAD 4.0 F0 - Solo lectura. Windows PowerShell 5.1 compatible.
Set-StrictMode -Version 2.0

function Protect-PCADPath {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    if ($Path -match '^\\\\') { return '[RUTA_RED_OCULTA]' }
    $safe = $Path -replace '(?i)([a-z]:\\Users\\)[^\\\s"'']+', '$1[USUARIO]'
    return ($safe -replace '(?i)(\\Documents and Settings\\)[^\\\s"'']+', '$1[USUARIO]')
}
function Test-PCADAutoCADName {
    param([AllowNull()][string]$Name)
    if (!$Name) { return $false }
    return [bool]($Name -match '^(?:Autodesk\s+)?AutoCAD\s+(202[3-7])(?:\D|$)')
}
function Get-PCADProperty {
    param($Object,[string]$Name)
    if ($null -eq $Object) { return '' }
    $p=$Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return '' }
    return [string]$p.Value
}
function Get-PCADInstallations {
    $candidates=New-Object System.Collections.ArrayList
    foreach ($reg in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($entry in @(Get-ItemProperty -Path $reg -ErrorAction SilentlyContinue)) {
            $name=Get-PCADProperty $entry 'DisplayName'
            if (!(Test-PCADAutoCADName $name)) { continue }
            $year=[int]([regex]::Match($name,'202[3-7]').Value)
            [void]$candidates.Add([pscustomobject]@{
                Year=$year; Dir=(Get-PCADProperty $entry 'InstallLocation');
                Product=$name; Evidence='REGISTRO'
            })
        }
    }
    $roots=@($env:ProgramW6432,$env:ProgramFiles,[Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) |
        Where-Object { $_ } | Select-Object -Unique
    foreach ($root in $roots) {
        foreach ($year in 2023..2027) {
            $dir=Join-Path $root ("Autodesk\AutoCAD {0}" -f $year)
            if (Test-Path -LiteralPath (Join-Path $dir 'acad.exe') -PathType Leaf) {
                [void]$candidates.Add([pscustomobject]@{
                    Year=$year; Dir=$dir; Product=("AutoCAD {0}" -f $year); Evidence='CARPETA'
                })
            }
        }
    }
    $seen=@{}
    $out=New-Object System.Collections.ArrayList
    foreach ($c in $candidates) {
        $dir=([string]$c.Dir).Trim().Trim('"').TrimEnd('\')
        $exe=if ($dir) { Join-Path $dir 'acad.exe' } else { '' }
        $id=if ($exe) { $exe.ToUpperInvariant() } else { ('REG:{0}:{1}' -f $c.Year,$c.Product).ToUpperInvariant() }
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id]=$true
        $found=[bool]($exe -and (Test-Path -LiteralPath $exe -PathType Leaf))
        $version=''; $publisher=''; $signature='NO_VERIFICADA'
        if ($found) {
            try {
                $item=Get-Item -LiteralPath $exe -ErrorAction Stop
                $version=[string]$item.VersionInfo.FileVersion
                $publisher=[string]$item.VersionInfo.CompanyName
            } catch {}
            try { $signature=[string](Get-AuthenticodeSignature -LiteralPath $exe -ErrorAction Stop).Status } catch {}
        }
        [void]$out.Add([pscustomobject]@{
            Year=$c.Year; Product=$c.Product; Path=(Protect-PCADPath $exe)
            Evidence=$c.Evidence; FileFound=$found
            Status=$(if ($found) {'ENCONTRADO'} else {'SOLO_REGISTRO'})
            FileVersion=$version; Publisher=$publisher; Signature=$signature
        })
    }
    return @($out.ToArray() | Sort-Object Year,Path)
}
function Get-PCADProcessClass {
    param([string]$Name,[string]$Path,[string]$Parent,[string]$UserData)
    if ($Name -match '(?i)^msedgewebview2\.exe$') {
        $host='INDETERMINADA'
        if ($Parent -match '(?i)^acad\.exe$' -or $UserData -match '(?i)AutoCAD 202[3-7]') { $host='AUTOCAD_PROBABLE' }
        elseif ($Parent -match '(?i)^(Adsk|Autodesk)') { $host='AUTODESK_COMPARTIDO_PROBABLE' }
        return [pscustomobject]@{Category='WEBVIEW2_COMPARTIDO'; Attribution=$host}
    }
    if ($Name -match '(?i)^acad\.exe$' -or $Path -match '(?i)\\Autodesk\\AutoCAD 202[3-7]\\') {
        return [pscustomobject]@{Category='AUTOCAD_PRODUCTO'; Attribution='RUTA_O_NOMBRE'}
    }
    if ($Name -match '(?i)^(Adsk|Autodesk)' -or $Path -match '(?i)\\Autodesk\\') {
        return [pscustomobject]@{Category='AUTODESK_COMPARTIDO'; Attribution='RUTA_O_NOMBRE'}
    }
    return [pscustomobject]@{Category='DESCONOCIDO'; Attribution='INDETERMINADA'}
}
function Get-PCADProcesses {
    $all=@(Get-CimInstance Win32_Process -ErrorAction Stop)
    $index=@{}
    foreach ($p in $all) { $index[[string]$p.ProcessId]=$p }
    $out=New-Object System.Collections.ArrayList
    foreach ($p in $all) {
        $name=[string]$p.Name; $path=[string]$p.ExecutablePath
        if ($name -notmatch '(?i)^(acad|msedgewebview2|AcWebBrowser)\.exe$' -and
            $name -notmatch '(?i)^(Adsk|Autodesk)' -and $path -notmatch '(?i)\\Autodesk\\') { continue }
        $parent=''
        if ($index.ContainsKey([string]$p.ParentProcessId)) { $parent=[string]$index[[string]$p.ParentProcessId].Name }
        $command=[string]$p.CommandLine
        $udf='';$hostHint=''
        if ($command -match '(?i)--user-data-dir=(?:"([^"]+)"|([^\s]+))') {
            $udf=if ($Matches[1]) {$Matches[1]} else {$Matches[2]}
        }
        if ($command -match '(?i)--webview-exe-name=(?:"([^"]+)"|([^\s]+))') {
            $hostHint=if ($Matches[1]) {$Matches[1]} else {$Matches[2]}
        }
        $class=Get-PCADProcessClass -Name $name -Path $path -Parent $parent -UserData $udf
        [void]$out.Add([pscustomobject]@{
            PID=[int]$p.ProcessId; ParentPID=[int]$p.ParentProcessId
            Name=$name; ParentName=$parent; Started=[string]$p.CreationDate
            ExecutablePath=(Protect-PCADPath $path)
            UserDataFolder=(Protect-PCADPath $udf); HostHint=(Protect-PCADPath $hostHint)
            Classification=$class.Category; Attribution=$class.Attribution
        })
    }
    return @($out.ToArray() | Sort-Object Name,PID)
}
function Get-PCADServices {
    $out=New-Object System.Collections.ArrayList
    foreach ($s in @(Get-CimInstance Win32_Service -ErrorAction Stop)) {
        $name=[string]$s.Name;$display=[string]$s.DisplayName;$path=[string]$s.PathName
        if (('{0} {1} {2}' -f $name,$display,$path) -notmatch '(?i)Autodesk|Adsk|AutoCAD|AdODIS|AdSSO') { continue }
        # Los argumentos de servicio pueden contener datos privados: guardar solo el ejecutable.
        $exe=''
        if ($path -match '^\s*"([^"]+?\.exe)"') { $exe=$Matches[1] }
        elseif ($path -match '^\s*(.+?\.exe)(?:\s|$)') { $exe=$Matches[1] }
        [void]$out.Add([pscustomobject]@{
            Name=$name; DisplayName=$display; State=[string]$s.State
            StartMode=[string]$s.StartMode; ExecutablePath=(Protect-PCADPath $exe)
            Classification='AUTODESK_COMPARTIDO_CANDIDATO'
        })
    }
    return @($out.ToArray() | Sort-Object Name)
}
function Get-PCADLegacyKind {
    param([string]$Name,[string]$DisplayName)
    $s=('{0} {1}' -f $Name,$DisplayName)
    if ($s -match '(?i)PCAD_A_V3_|PCAD_W_V3_|PCAD4_') { return 'PARCHECAD' }
    if ($s -match '(?i)SGC_AUTODESK_BLOCK_V1_|SGC_WEBVIEW2_CONTROL_V1_|SGC_WEBVIEW2_V2_') { return 'HISTORICO_SGC' }
    if ($s -match '(?i)WebView2GlobalBlock|WebView2 Global Block - ChatGPT Fix|Autodesk Block WebView2') { return 'WEBVIEW2_HISTORICO' }
    if ($s -match '(?i)AutodeskBlocker_In|AutodeskBlocker_Out') { return 'REFERENCIA_EXTERNA' }
    if ($s -match '(?i)Autodesk Block:|SGC Autodesk Block') { return 'HISTORICO_AUTODESK' }
    return 'AJENO_O_DESCONOCIDO'
}
function Get-PCADFirewall {
    $rules=@(Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop)
    $byName=@{};$interesting=@{};$programs=@{}
    foreach ($r in $rules) {
        $id=[string]$r.Name;$byName[$id]=$r
        if ((Get-PCADLegacyKind $id ([string]$r.DisplayName)) -ne 'AJENO_O_DESCONOCIDO' -or
            ('{0} {1}' -f $r.DisplayName,$r.DisplayGroup) -match '(?i)Autodesk|AutoCAD|WebView2|ParcheCAD') {
            $interesting[$id]=$true
        }
    }
    foreach ($filter in @(Get-NetFirewallApplicationFilter -PolicyStore ActiveStore -All -ErrorAction Stop)) {
        $path=[string]$filter.Program
        if ($path -notmatch '(?i)Autodesk|AutoCAD|msedgewebview2\.exe|AcWebBrowser\.exe|Adsk') { continue }
        foreach ($r in @(Get-NetFirewallRule -AssociatedNetFirewallApplicationFilter $filter -PolicyStore ActiveStore -ErrorAction Stop)) {
            $id=[string]$r.Name
            $interesting[$id]=$true
            $programs[$id]=$path
        }
    }
    $out=New-Object System.Collections.ArrayList
    foreach ($id in @($interesting.Keys | Sort-Object)) {
        if (!$byName.ContainsKey($id)) { continue }
        $r=$byName[$id]
        $path=''
        if ($programs.ContainsKey($id)) { $path=$programs[$id] }
        else {
            try {
                $filters=@($r | Get-NetFirewallApplicationFilter -ErrorAction Stop)
                if ($filters.Count -gt 0) { $path=[string]$filters[0].Program }
            } catch { $path='[NO_VERIFICADO]' }
        }
        [void]$out.Add([pscustomobject]@{
            Name=$id; DisplayName=[string]$r.DisplayName; Group=[string]$r.DisplayGroup
            Program=(Protect-PCADPath $path); Direction=[string]$r.Direction
            Action=[string]$r.Action; Enabled=[string]$r.Enabled; Profile=[string]$r.Profile
            PolicySource=[string](Get-PCADProperty $r 'PolicyStoreSourceType')
            LegacyKind=(Get-PCADLegacyKind $id ([string]$r.DisplayName))
            Ownership='NO_CONFIRMADA'; TrafficEffect='NO_VERIFICADO'
        })
    }
    return @($out.ToArray())
}
function Get-PCADTasks {
    $out=New-Object System.Collections.ArrayList
    foreach ($task in @(Get-ScheduledTask -ErrorAction Stop)) {
        $related=('{0} {1}' -f $task.TaskName,$task.TaskPath) -match '(?i)Autodesk|WebView2|ParcheCAD|SGC'
        $actions=New-Object System.Collections.ArrayList
        foreach ($a in @($task.Actions)) {
            if ($null -eq $a) { continue }
            $exe=Get-PCADProperty $a 'Execute'
            $arg=Get-PCADProperty $a 'Arguments'
            $hit=[bool](('{0} {1}' -f $exe,$arg) -match '(?i)Autodesk|WebView2|ParcheCAD|setup-webview2-block|autodesk-block-webview2|SGC')
            if ($hit) { $related=$true }
            # Nunca guardar Arguments: pueden incluir tokens, usuarios o claves.
            [void]$actions.Add([pscustomobject]@{Executable=(Protect-PCADPath $exe); Related=$hit})
        }
        if (!$related) { continue }
        [void]$out.Add([pscustomobject]@{
            Name=[string]$task.TaskName; TaskPath=[string]$task.TaskPath
            State=[string]$task.State; Actions=@($actions.ToArray())
            Assessment='DETECTADA_NO_MODIFICADA'
        })
    }
    return @($out.ToArray() | Sort-Object TaskPath,Name)
}
function Get-PCADRemoteScope {
    param([string]$Address)
    $ip=$null
    if ([string]::IsNullOrWhiteSpace($Address) -or
        ![System.Net.IPAddress]::TryParse($Address,[ref]$ip)) { return 'DESCONOCIDO' }
    if ([System.Net.IPAddress]::IsLoopback($ip)) { return 'LOOPBACK' }
    $b=$ip.GetAddressBytes()
    if ($ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
        if ($b[0] -eq 10 -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or
            ($b[0] -eq 192 -and $b[1] -eq 168) -or ($b[0] -eq 169 -and $b[1] -eq 254)) {return 'PRIVADA_LOCAL'}
    } elseif ($ip.IsIPv6LinkLocal -or $ip.IsIPv6SiteLocal -or (($b[0] -band 0xFE) -eq 0xFC)) {
        return 'PRIVADA_LOCAL'
    }
    return 'PUBLICA_O_ESPECIAL'
}
function Get-PCADConnections {
    param([object[]]$Processes)
    $owners=@{};$out=New-Object System.Collections.ArrayList
    foreach ($p in @($Processes)) { $owners[[string]$p.PID]=$p.Name }
    foreach ($c in @(Get-NetTCPConnection -ErrorAction Stop)) {
        if (!$owners.ContainsKey([string]$c.OwningProcess)) {continue}
        [void]$out.Add([pscustomobject]@{
            Protocol='TCP'; PID=[int]$c.OwningProcess; Process=$owners[[string]$c.OwningProcess]
            State=[string]$c.State; RemotePort=[int]$c.RemotePort
            RemoteScope=(Get-PCADRemoteScope -Address ([string]$c.RemoteAddress))
            RemoteAddress='[OCULTA]'; Interpretation='INSTANTANEA_NO_PRUEBA_AUSENCIA'
        })
    }
    foreach ($c in @(Get-NetUDPEndpoint -ErrorAction Stop)) {
        if (!$owners.ContainsKey([string]$c.OwningProcess)) {continue}
        [void]$out.Add([pscustomobject]@{
            Protocol='UDP_ENDPOINT';PID=[int]$c.OwningProcess;Process=$owners[[string]$c.OwningProcess]
            State='';RemotePort=0;RemoteScope='NO_DISPONIBLE'
            RemoteAddress='[NO_DISPONIBLE]';Interpretation='ENDPOINT_NO_ES_DESTINO_REMOTO'
        })
    }
    return @($out.ToArray())
}
