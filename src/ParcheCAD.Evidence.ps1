# F5 - saneamiento de datos antes de escribir informes. Solo lectura.
Set-StrictMode -Version 2.0

function ConvertTo-PCADSafeRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Record,[string[]]$PathFields=@())
    $props=[ordered]@{}
    foreach($p in $Record.PSObject.Properties){
        if($PathFields -contains [string]$p.Name){
            $props[$p.Name]=Protect-PCADPath -Path ([string]$p.Value)
        } else {
            $props[$p.Name]=$p.Value
        }
    }
    return [pscustomobject]$props
}
function ConvertTo-PCADSafePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Plan)
    $safe=ConvertTo-PCADSafeRecord -Record $Plan
    $safe.Entries=@($Plan.Entries|ForEach-Object{
        ConvertTo-PCADSafeRecord -Record $_ -PathFields @('Program','InstallationRoot')
    })
    $safe.Excluded=@($Plan.Excluded|ForEach-Object{
        ConvertTo-PCADSafeRecord -Record $_ -PathFields @('Path')
    })
    return $safe
}
