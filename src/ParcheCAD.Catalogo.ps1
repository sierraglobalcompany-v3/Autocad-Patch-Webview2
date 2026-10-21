# ParcheCAD 4.0 F1: catalogo de ejecutables por instalacion confirmada.
# Solo lectura. Compatible Windows PowerShell 5.1 y PowerShell 7.
Set-StrictMode -Version 2.0

function Get-PCADFileClass {
    [CmdletBinding()]
    param([string]$FilePath,[string]$InstallationRoot,[int]$Year=0,[string]$Kind='PRODUCT')
    $leaf=[IO.Path]::GetFileName($FilePath)
    $class='DESCONOCIDO';$confidence='BAJA';$reason='Componente sin clasificar';$risk='REVISAR'
    if($leaf -ieq 'msedgewebview2.exe') {
        $class='WEBVIEW2_COMPARTIDO';$confidence='ALTA';$reason='Runtime de Microsoft utilizado por varias aplicaciones';$risk='ALTO'
    } elseif ($Kind -eq 'SHARED') {
        $class='AUTODESK_COMPARTIDO';$confidence='MEDIA';$reason='Servicio/componente de Autodesk no exclusivo de una version';$risk='ALTO'
    } elseif($InstallationRoot -and $Year -ge 2023 -and $Year -le 2027) {
        $root=([IO.Path]::GetFullPath($InstallationRoot)).TrimEnd('\','/')
        $file=([IO.Path]::GetFullPath($FilePath))
        if($file.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){
            $class='AUTOCAD_PRODUCTO';$confidence='MEDIA'
            $reason=("EXE ubicado dentro de la instalacion AutoCAD {0}; dependencia aun no evaluada" -f $Year)
            $risk='FUNCIONES'
            if($leaf -ieq 'acad.exe' -and $file -ieq (Join-Path $root 'acad.exe')) {
                $confidence='ALTA';$reason=("Ejecutable principal de AutoCAD {0}" -f $Year)
            }
            if($leaf -ieq 'AcWebBrowser.exe') {
                $reason='Navegador legado Autodesk detectado: no confundir con WebView2'
                $risk='ALTO'
            }
        }
    }
    return [pscustomobject]@{
        Classification=$class;Confidence=$confidence
        Rationale=$reason;Impact=$risk
        AutoCADYear=$(if($class -eq 'AUTOCAD_PRODUCTO'){$Year}else{0})
        FirewallEligible=($class -eq 'AUTOCAD_PRODUCTO')
    }
}


# One bounded and symlink-safe walker for AutoCAD product and Autodesk shared roots.
function Get-PCADCatalogTree {
    [CmdletBinding()]
    param([string]$Root,[int]$MaxFiles=900,[int]$MaxDepth=7)
    $out=New-Object System.Collections.ArrayList
    $warnings=New-Object System.Collections.ArrayList
    $partial=$false
    if([string]::IsNullOrWhiteSpace($Root) -or !([IO.Path]::IsPathRooted($Root)) -or $Root -match '^\\\\'){
        return [pscustomobject]@{Entries=@();Warnings=@('Raiz no local');Partial=$true}
    }
    $stack=New-Object System.Collections.Stack
    $stack.Push([pscustomobject]@{Path=$Root;Depth=0})
    while($stack.Count -gt 0){
        $node=$stack.Pop()
        try{
            $dir=Get-Item -LiteralPath $node.Path -Force -ErrorAction Stop
            if(($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                $partial=$true
                [void]$warnings.Add('Raiz o carpeta enlazada omitida; inventario no exhaustivo')
                continue
            }
            foreach($child in @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction Stop)){
                if(($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                    $partial=$true
                    [void]$warnings.Add('Enlace/junction omitido; inventario no exhaustivo')
                    continue
                }
                if($child.PSIsContainer){
                    if([int]$node.Depth -ge $MaxDepth){$partial=$true}
                    else{$stack.Push([pscustomobject]@{Path=$child.FullName;Depth=([int]$node.Depth+1)})}
                    continue
                }
                if($child.Extension -ine '.exe'){continue}
                [void]$out.Add($child)
                if($out.Count -ge $MaxFiles){$partial=$true;break}
            }
            if($out.Count -ge $MaxFiles){break}
        }catch{
            [void]$warnings.Add(('Carpeta inaccesible: '+$_.Exception.GetType().Name))
            $partial=$true
        }
    }
    if($partial){[void]$warnings.Add('Inventario limitado por profundidad, cantidad o acceso')}
    return [pscustomobject]@{Entries=@($out.ToArray());Warnings=@($warnings.ToArray());Partial=$partial}
}
function Get-PCADDefaultSharedRoots {
    $roots=New-Object System.Collections.ArrayList
    $programFiles=@($env:ProgramW6432,$env:ProgramFiles,[Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) |
        Where-Object {$_} | Select-Object -Unique
    foreach($pf in $programFiles){
        foreach($relative in @('Autodesk\AdODIS','Autodesk\Autodesk Access','Autodesk\Autodesk Desktop App',
                              'Autodesk\Identity Services','Common Files\Autodesk Shared')){
            $root=Join-Path $pf $relative
            if(Test-Path -LiteralPath $root -PathType Container){[void]$roots.Add($root)}
        }
    }
    return @($roots.ToArray() | Select-Object -Unique)
}

function Get-PCADExecutableCatalog {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Installations=@(),
        [AllowEmptyCollection()][object[]]$Services=@(),
        [int]$MaxFilesPerProduct=900,
        [int]$MaxDepth=7,
        [AllowNull()][string[]]$SharedRoots=$null,
        [int]$MaxFilesPerSharedRoot=250,
        [int]$MaxSharedDepth=5,
        [switch]$InternalPaths
    )
    $rows=New-Object System.Collections.ArrayList
    $notes=New-Object System.Collections.ArrayList
    $seen=@{}
    $sharedPartial=$false
    foreach($install in @($Installations)){
        if($null -eq $install -or !(($install.FileFound) -eq $true)) {continue}
        $year=[int]$install.Year
        if($year -lt 2023 -or $year -gt 2027) {continue}
        $exe=[string]$install.Path
        if(!$exe -or $exe -match '\[USUARIO\]|\[RUTA_RED_OCULTA\]') {
            [void]$notes.Add("AutoCAD ${year}: ruta no recuperable desde informe saneado")
            continue
        }
        try {
            $root=[IO.Path]::GetDirectoryName($exe)
            if(!([IO.Path]::IsPathRooted($exe)) -or !(Test-Path -LiteralPath $exe -PathType Leaf)) {
                [void]$notes.Add("AutoCAD ${year}: archivo no disponible");continue
            }
            $tree=Get-PCADCatalogTree -Root $root -MaxFiles $MaxFilesPerProduct -MaxDepth $MaxDepth
            foreach($warning in @($tree.Warnings)){
                [void]$notes.Add(("AutoCAD {0}: {1}" -f $year,$warning))
            }
            foreach($child in @($tree.Entries)){
                $key=$child.FullName.ToUpperInvariant()
                if($seen.ContainsKey($key)){continue}
                $seen[$key]=$true
                $classification=Get-PCADFileClass -FilePath $child.FullName -InstallationRoot $root -Year $year
                [void]$rows.Add([pscustomobject]@{
                    Year=$year;Name=$child.Name
                    Path=$(if($InternalPaths){$child.FullName}else{Protect-PCADPath $child.FullName})
                    InstallationRoot=$(if($InternalPaths){$root}else{Protect-PCADPath $root})
                    Classification=$classification.Classification
                    Confidence=$classification.Confidence;Impact=$classification.Impact
                    Rationale=$classification.Rationale
                    Policy='SOLO_INVENTARIO';VerifiedConnection='NO'
                })
            }

        } catch {
            [void]$notes.Add(("AutoCAD ${year}: error de acceso {0}; catalogo INCOMPLETO" -f $_.Exception.GetType().Name))
        }
    }
    # Inventory ONLY: shared Autodesk install roots are never automatically
    # eligible for the product-specific firewall policy.
    $roots=if($null -eq $SharedRoots){@(Get-PCADDefaultSharedRoots)}else{@($SharedRoots)}
    foreach($sharedRoot in @($roots | Where-Object {$_} | Select-Object -Unique)){
        try{
            if(!(Test-Path -LiteralPath $sharedRoot -PathType Container)){continue}
            $tree=Get-PCADCatalogTree -Root $sharedRoot -MaxFiles $MaxFilesPerSharedRoot -MaxDepth $MaxSharedDepth
            if($tree.Partial){$sharedPartial=$true}
            foreach($warning in @($tree.Warnings)){
                [void]$notes.Add(('Autodesk compartido: '+$warning))
            }
            foreach($child in @($tree.Entries)){
                $key=$child.FullName.ToUpperInvariant()
                if($seen.ContainsKey($key)){continue}
                $seen[$key]=$true
                $classification=Get-PCADFileClass -FilePath $child.FullName -Kind 'SHARED'
                [void]$rows.Add([pscustomobject]@{
                    Year=0;Name=$child.Name
                    Path=$(if($InternalPaths){$child.FullName}else{Protect-PCADPath $child.FullName})
                    InstallationRoot=''
                    Classification=$classification.Classification
                    Confidence=$classification.Confidence;Impact=$classification.Impact
                    Rationale=$classification.Rationale
                    Policy='SOLO_INVENTARIO';VerifiedConnection='NO'
                })
            }
        }catch{
            $sharedPartial=$true
            [void]$notes.Add(('Autodesk compartido: error de acceso '+$_.Exception.GetType().Name))
        }
    }
    # Servicios compartidos tienen evidencias propias, no incluirlos en el mismo grupo de AutoCAD.
    foreach($svc in @($Services)) {
        if($null -eq $svc){continue}
        $path=[string]$svc.ExecutablePath
        if(!$path){continue}
        $key=$path.ToUpperInvariant()
        if($seen.ContainsKey($key)){continue}
        $seen[$key]=$true
        $classification=Get-PCADFileClass -FilePath $path -Kind 'SHARED'
        [void]$rows.Add([pscustomobject]@{
            Year=0;Name=[string]$svc.Name;Path=(Protect-PCADPath $path)
            InstallationRoot=''
            Classification=$classification.Classification
            Confidence=$classification.Confidence;Impact=$classification.Impact
            Rationale=$classification.Rationale
            Policy='SOLO_INVENTARIO';VerifiedConnection='NO'
        })
    }
    return [pscustomobject]@{
        Status=$(if(@($notes | Where-Object {$_ -notmatch '^Autodesk compartido:'}).Count -gt 0){'PARCIAL'}else{'OK'})
        SharedStatus=$(if($sharedPartial){'PARCIAL'}else{'INVENTARIO_LIMITADO'})
        Entries=@($rows.ToArray() | Sort-Object Year,Path)
        Warnings=@($notes.ToArray())
        Important='Inventario de EXE. Las raices compartidas son solo lectura y no se incluyen en el plan Automatico; catalogo no certifica cobertura total.'
    }
}
