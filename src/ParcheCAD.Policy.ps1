# F4 - planificador puro de reglas, sin ninguna modificacion del sistema.
Set-StrictMode -Version 2.0

function Get-PCADCanonicalProgram {
    [CmdletBinding()]
    param([string]$Path)
    if([string]::IsNullOrWhiteSpace($Path) -or $Path -match '\[(USUARIO|RUTA_RED_OCULTA)\]') {
        throw 'Ruta vacia o saneada no apta para reglas.'
    }
    if($Path -match '[\r\n"'']') {throw 'Ruta no aceptada para una regla por programa.'}
    if(![IO.Path]::IsPathRooted($Path) -or $Path -match '^\\\\') {throw 'Solo rutas locales absolutas.'}
    $full=[IO.Path]::GetFullPath($Path)
    if([IO.Path]::GetExtension($full) -ine '.exe') {throw 'El objetivo debe ser un EXE.'}
    return $full.TrimEnd([char]'\')
}

# Path-containment is NOT physical containment when a junction/symlink
# redirects one of the intermediate directories. Reject all existing
# reparse components from drive root through the final executable BEFORE
# generating or applying a block rule. The path is inspected again just
# before New-NetFirewallRule to reduce time-of-check/time-of-use gaps.
function Assert-PCADNoReparseComponents {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Program)
    $full=Get-PCADCanonicalProgram -Path $Program
    $dir=$full
    $steps=0
    while($dir){
        $steps++
        if($steps -gt 64){throw 'Ruta excesivamente profunda o ciclica.'}
        if(!(Test-Path -LiteralPath $dir)){
            throw 'Componente de ruta inexistente; no se crea regla.'
        }
        $entry=Get-Item -LiteralPath $dir -Force -ErrorAction Stop
        if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'La ruta contiene enlace simbolico o junction; no aplicar regla.'
        }
        $parent=[IO.Path]::GetDirectoryName($dir.TrimEnd([char]'\'))
        if([string]::IsNullOrWhiteSpace($parent) -or $parent -ieq $dir){break}
        $dir=$parent
    }
    return $true
}

function Assert-PCADProgramInstallRoot {
    [CmdletBinding()]
    param([string]$Program,[int]$Year,[string]$InstallRoot,[switch]$AllowMissing)
    $path=Get-PCADCanonicalProgram -Path $Program
    if($Year -lt 2023 -or $Year -gt 2027){throw 'Version de AutoCAD fuera del soporte 2023-2027.'}
    if([string]::IsNullOrWhiteSpace($InstallRoot)){
        if($path -notmatch ('(?i)\\AutoCAD '+$Year+'\\')) {
            throw 'Falta raiz de instalacion para una ruta personalizada.'
        }
        if(!$AllowMissing){$null=Assert-PCADNoReparseComponents -Program $path}
        return $path
    }
    if(![IO.Path]::IsPathRooted($InstallRoot) -or $InstallRoot -match '^\\\\' -or
       $InstallRoot -match '\[(USUARIO|RUTA_RED_OCULTA)\]') {
        throw 'La raiz de instalacion no es local o no se puede verificar.'
    }
    $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd([char]'\')
    if(!$path.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase)) {
        throw 'El EXE no pertenece a la raiz de AutoCAD seleccionada.'
    }
    if(!$AllowMissing -and !(Test-Path -LiteralPath (Join-Path $root 'acad.exe') -PathType Leaf)) {
        throw 'No se comprobo acad.exe dentro de la raiz de instalacion.'
    }
    if(!$AllowMissing){$null=Assert-PCADNoReparseComponents -Program $path}
    # During rollback an executable or parent directory may have been moved,
    # uninstalled or replaced. Only the exact owned firewall rule is deleted;
    # do not refuse its recovery because a file path changed after Apply.
    return $path
}
function Get-PCADRuleName {
    [CmdletBinding()]
    param([string]$Program)
    $path=(Get-PCADCanonicalProgram -Path $Program).ToLowerInvariant()
    $inputText=('PCAD4|OUT|'+$path)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        $bytes=[Text.Encoding]::UTF8.GetBytes($inputText)
        $hash=$sha.ComputeHash($bytes)
        $hex=[BitConverter]::ToString($hash).Replace('-','').Substring(0,24)
        return 'PCAD4_A_'+$hex+'_OUT'
    } finally { $sha.Dispose() }
}
# A single unrestricted filter value is required; e.g. "Any".
# Missing, multiple, or narrowed values must never be accepted as a complete
# ParcheCAD block rule. The caller owns the Windows NetSecurity objects.
function Test-PCADFirewallFilterAny {
    [CmdletBinding()]
    param($Value)
    if($null -eq $Value){return $false}
    $items=@($Value)
    return ($items.Count -eq 1 -and [string]$items[0] -ieq 'Any')
}
function Get-PCADActualRuleStatus {
    [CmdletBinding()]
    param([string]$RuleName,[string]$Program)
    $rule=$null
    try {
        $rule=Get-NetFirewallRule -Name $RuleName -PolicyStore PersistentStore -ErrorAction Stop
    } catch {
        if($_.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::ObjectNotFound -or
           $_.FullyQualifiedErrorId -match 'ObjectNotFound|NoMatching|NotFound') {
            return [pscustomobject]@{State='MISSING';Description='No existe regla local con ese Name'}
        }
        throw
    }
    if($null -eq $rule) {return [pscustomobject]@{State='MISSING';Description='No existe regla local con ese Name'}}
    $matches=@($rule)
    if($matches.Count -ne 1) {
        return [pscustomobject]@{State='CONFLICT';Description='Nombre duplicado o ambiguo'}
    }
    $one=$matches[0]
    $filter=@($one | Get-NetFirewallApplicationFilter -ErrorAction Stop)
    if($filter.Count -ne 1) {
        return [pscustomobject]@{State='CONFLICT';Description='No hay un filtro de programa unico'}
    }
    $expected=(Get-PCADCanonicalProgram -Path $Program)
    $samePath=([string]$filter[0].Program -ieq $expected)
    $sameGroup=([string]$one.Group -eq 'PCAD4_MANAGED')
    $sameAction=([string]$one.Action -eq 'Block')
    $sameDirection=([string]$one.Direction -eq 'Outbound')
    $sameEnabled=([string]$one.Enabled -eq 'True')
    $sameProfile=([string]$one.Profile -eq 'Any')
    if(!($samePath -and $sameGroup -and $sameAction -and $sameDirection -and $sameEnabled -and $sameProfile)) {
        return [pscustomobject]@{State='CONFLICT';Description='Regla con nombre ocupado o configuracion distinta: no modificar'}
    }

    # F16: Windows Firewall rules contain independent NetSecurity filters.
    # A rule with a valid EXE path may still be TCP-only, remote-IP-only or
    # service-only. Do not call that rule EXISTS_VALID and silently skip it.
    # Read failures are NOT MISSING; they must fail closed in Preview/Apply.
    $port=@($one | Get-NetFirewallPortFilter -ErrorAction Stop)
    $address=@($one | Get-NetFirewallAddressFilter -ErrorAction Stop)
    $service=@($one | Get-NetFirewallServiceFilter -ErrorAction Stop)
    $interfaceType=@($one | Get-NetFirewallInterfaceTypeFilter -ErrorAction Stop)
    if($port.Count -ne 1 -or $address.Count -ne 1 -or
       $service.Count -ne 1 -or $interfaceType.Count -ne 1){
        return [pscustomobject]@{State='CONFLICT';Description='Filtros de puertos, direcciones, servicio o interfaz ausentes/ambiguos'}
    }
    $fullScope=(
        (Test-PCADFirewallFilterAny $port[0].Protocol) -and
        (Test-PCADFirewallFilterAny $port[0].LocalPort) -and
        (Test-PCADFirewallFilterAny $port[0].RemotePort) -and
        (Test-PCADFirewallFilterAny $address[0].LocalAddress) -and
        (Test-PCADFirewallFilterAny $address[0].RemoteAddress) -and
        (Test-PCADFirewallFilterAny $service[0].Service) -and
        (Test-PCADFirewallFilterAny $interfaceType[0].InterfaceType)
    )
    if(!$fullScope){
        return [pscustomobject]@{State='CONFLICT';Description='Regla restringida por protocolo, puertos, IP, servicio o interfaz; no modificar'}
    }
    return [pscustomobject]@{
        State='EXISTS_VALID'
        Description='Regla propia con salida Block, perfiles Any y filtros amplios de protocolo, puertos, direcciones, servicio e interfaz'
    }
}
function New-PCADRulePlan {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Catalog=@(),[switch]$CheckExisting)
    $included=New-Object System.Collections.ArrayList
    $excluded=New-Object System.Collections.ArrayList
    $seen=@{}
    foreach($c in @($Catalog)) {
        if($null -eq $c){continue}
        $original=[string]$c.Path
        if([string]$c.Classification -ne 'AUTOCAD_PRODUCTO' -or [string]$c.Policy -ne 'SOLO_INVENTARIO') {
            [void]$excluded.Add([pscustomobject]@{Name=[string]$c.Name;Reason='NO_EXCLUSIVO_O_NO_APROBADO';Path=(Protect-PCADPath $original)})
            continue
        }
        try {
            $path=Get-PCADCanonicalProgram -Path $original
            $year=[int]$c.Year
            $installRoot=Get-PCADProperty -Object $c -Name 'InstallationRoot'
            $null=Assert-PCADProgramInstallRoot -Program $path -Year $year -InstallRoot $installRoot
            $key=$path.ToUpperInvariant()
            if($seen.ContainsKey($key)){continue}
            $seen[$key]=$true
            $ruleName=Get-PCADRuleName -Program $path
            $item=[pscustomobject]@{
                RuleName=$ruleName;Group='PCAD4_MANAGED';Year=$year
                Program=$path;InstallationRoot=$installRoot;DisplayName=('ParcheCAD 4.0 - AutoCAD '+$year+' - '+[IO.Path]::GetFileName($path))
                Direction='Outbound';Action='Block';Profile='Any'
                Existing='NO_COMPROBADO';Assessment='CANDIDATO'
            }
            if($CheckExisting) {
                try {
                    $status=Get-PCADActualRuleStatus -RuleName $ruleName -Program $path
                    $item.Existing=$status.State
                    $item.Assessment=if($status.State -eq 'CONFLICT') {'NO_APLICAR'} else {'CANDIDATO'}
                } catch {
                    # No convertir un error de permisos o consulta en "MISSING".
                    $item.Existing='ERROR_INSPECCION'
                    $item.Assessment='NO_APLICAR'
                }
            }
            [void]$included.Add($item)
        } catch {
            [void]$excluded.Add([pscustomobject]@{Name=[string]$c.Name;Reason='RUTA_INVALIDA_O_SANEADA';Path=(Protect-PCADPath $original)})
        }
    }
    $entries=@($included.ToArray()|Sort-Object Year,Program)
    $conflicts=@($entries|Where-Object {$_.Assessment -eq 'NO_APLICAR'}).Count
    return [pscustomobject]@{
        Phase='F4_PREVIEW';ReadOnly=$true
        RuleGroup='PCAD4_MANAGED';State=if($conflicts){'CONFLICT'}else{'PLAN_NO_APLICADO'}
        Count=$entries.Count;Conflicts=$conflicts
        Entries=$entries;Excluded=@($excluded.ToArray())
        Disclaimer='Plan no implica conexiones bloqueadas; WebView2 compartido excluido.'
    }
}
