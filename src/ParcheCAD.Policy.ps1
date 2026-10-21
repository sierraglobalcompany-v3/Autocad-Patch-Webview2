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
    if($samePath -and $sameGroup -and $sameAction -and $sameDirection -and $sameEnabled -and $sameProfile) {
        return [pscustomobject]@{State='EXISTS_VALID';Description='Regla ParcheCAD coincide con ruta, grupo, salida, bloqueo y perfiles'}
    }
    return [pscustomobject]@{State='CONFLICT';Description='Regla con nombre ocupado o configuracion distinta: no modificar'}
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
            if($year -lt 2023 -or $year -gt 2027 -or $path -notmatch ('(?i)\\AutoCAD '+$year+'\\')) {
                throw 'Ruta/version no coinciden'
            }
            $key=$path.ToUpperInvariant()
            if($seen.ContainsKey($key)){continue}
            $seen[$key]=$true
            $ruleName=Get-PCADRuleName -Program $path
            $item=[pscustomobject]@{
                RuleName=$ruleName;Group='PCAD4_MANAGED';Year=$year
                Program=$path;DisplayName=('ParcheCAD 4.0 | AutoCAD '+$year+' | '+[IO.Path]::GetFileName($path))
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
