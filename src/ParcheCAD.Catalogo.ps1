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

function Get-PCADExecutableCatalog {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Installations=@(),
        [AllowEmptyCollection()][object[]]$Services=@(),
        [int]$MaxFilesPerProduct=900,
        [int]$MaxDepth=7
    )
    $rows=New-Object System.Collections.ArrayList
    $notes=New-Object System.Collections.ArrayList
    $seen=@{}
    foreach($install in @($Installations)){
        if($null -eq $install -or !(($install.FileFound) -eq $true)) {continue}
        $year=[int]$install.Year
        if($year -lt 2023 -or $year -gt 2027) {continue}
        $exe=[string]$install.Path
        if(!$exe -or $exe -match '\[USUARIO\]|\[RUTA_RED_OCULTA\]') {
            [void]$notes.Add("AutoCAD $year: ruta no recuperable desde informe saneado")
            continue
        }
        try {
            $root=[IO.Path]::GetDirectoryName($exe)
            if(!([IO.Path]::IsPathRooted($exe)) -or !(Test-Path -LiteralPath $exe -PathType Leaf)) {
                [void]$notes.Add("AutoCAD $year: archivo no disponible");continue
            }
            $count=0; $stack=New-Object System.Collections.Stack
            $stack.Push([pscustomobject]@{Path=$root;Depth=0})
            while($stack.Count -gt 0 -and $count -lt $MaxFilesPerProduct) {
                $node=$stack.Pop()
                # Evitar junctions/symlinks al atravesar arbol.
                $dir=Get-Item -LiteralPath $node.Path -Force -ErrorAction Stop
                if(($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
                foreach($child in @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction Stop)){
                    if(($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
                    if($child.PSIsContainer) {
                        if([int]$node.Depth -lt $MaxDepth) {
                            $stack.Push([pscustomobject]@{Path=$child.FullName;Depth=([int]$node.Depth+1)})
                        }
                        continue
                    }
                    if($child.Extension -ine '.exe'){continue}
                    $key=$child.FullName.ToUpperInvariant()
                    if($seen.ContainsKey($key)){continue}
                    $seen[$key]=$true
                    $classification=Get-PCADFileClass -FilePath $child.FullName -InstallationRoot $root -Year $year
                    [void]$rows.Add([pscustomobject]@{
                        Year=$year;Name=$child.Name;Path=(Protect-PCADPath $child.FullName)
                        Classification=$classification.Classification
                        Confidence=$classification.Confidence;Impact=$classification.Impact
                        Rationale=$classification.Rationale
                        Policy='SOLO_INVENTARIO';VerifiedConnection='NO'
                    })
                    $count++
                    if($count -ge $MaxFilesPerProduct){break}
                }
            }
            if($count -ge $MaxFilesPerProduct){
                [void]$notes.Add("AutoCAD $year: limite $MaxFilesPerProduct EXE; catalogo INCOMPLETO")
            }
        } catch {
            [void]$notes.Add(("AutoCAD $year: error de acceso {0}; catalogo INCOMPLETO" -f $_.Exception.GetType().Name))
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
            Classification=$classification.Classification
            Confidence=$classification.Confidence;Impact=$classification.Impact
            Rationale=$classification.Rationale
            Policy='SOLO_INVENTARIO';VerifiedConnection='NO'
        })
    }
    return [pscustomobject]@{
        Status=$(if(@($notes).Count -gt 0){'PARCIAL'}else{'OK'})
        Entries=@($rows.ToArray() | Sort-Object Year,Path)
        Warnings=@($notes.ToArray())
        Important='Catalogo de descubrimiento; no es lista aprobada para bloquear.'
    }
}
