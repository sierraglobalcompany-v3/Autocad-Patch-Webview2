# F15 — Validación de rutas reales antes de bloquear un ejecutable

**Estado:** QA técnica aprobada en Windows GitHub-hosted. **PR #17 Draft, sin merge ni RC1.**  
**Evidencia:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39551110553 — CI #119, **4/4 PASS** (PS5.1, PS7, firewall temporal, ZIP reproducible).

## Defecto de origen

La política anterior verificaba que el nombre de la ruta de un ejecutable empezara por la raíz de AutoCAD. En Windows, una carpeta dentro de esa raíz puede ser una **junction** o enlace simbólico que apunte a otro programa. Una ruta como `C:\AutoCAD 2027\ExtPlugin\UnrelatedTool.exe` puede resolver en realidad fuera de AutoCAD. El catálogo F14 omitía la carpeta enlazada, pero la puerta de política podía aceptar un catálogo forjado o modificado que utilizara esa ruta.

**Impacto:** una regla saliente creada para un ejecutable ajeno, contrario al objetivo de preservar WhatsApp/Outlook y otras aplicaciones.

## Corrección KISS sin parches aislados

- `src/ParcheCAD.Policy.ps1` incorpora `Assert-PCADNoReparseComponents`: recorre los componentes de la ruta desde EXE hasta la raíz del volumen, comprueba que existen y rechaza la presencia de `FileAttributes.ReparsePoint` en cualquiera de ellos.
- `Assert-PCADProgramInstallRoot` lo ejecuta durante la planificación y las validaciones de aplicación cuando el ejecutable debe existir. Se conservan los controles de raíz local, año 2023–2027, `acad.exe` principal y pertenencia textual a la raíz.
- `src/ParcheCAD.Firewall.ps1` repite `Assert-PCADManagedEntry` **justo antes de `New-NetFirewallRule`**, reduciendo cambios de ruta entre el plan y la escritura. Esto limita el riesgo, pero no permite prometer inmunidad a ataques de carrera con enlaces cambiados a nivel de sistema.
- **Rollback no bloqueado innecesariamente:** `-AllowMissingFile` permite eliminar la regla PCAD4 exacta cuando la instalación fue desinstalada o su ruta ya no coincide físicamente. Todavía se exige nombre determinista, grupo y propiedades del firewall; no se autoriza crear reglas con ese permiso.
- `src/ParcheCAD.Catalogo.ps1` marca exploración `PARCIAL` y registra advertencias cuando omite un enlace/junction, en vez de mostrar una exploración falsamente completa.

## Pruebas y límites

`tests/F15.ReparseGuard.Tests.ps1` crea carpetas temporales en Windows y una junction que apunta a un ejecutable ajeno. Verifica que el plan la excluya, que el motor rechace su aplicación, que la reversión exacta pueda continuar, que el catálogo no siga el enlace, y que muestre estado parcial y advertencia. También prueba una raíz entera de instalación redirigida.

La primera ejecución descubrió que `Remove-Item` podía fallar al retirar junctions desde Windows PowerShell 5.1. Se corrigió el **test**, usando eliminación no recursiva de la entrada enlazada para no tocar el destino; después se repitió toda la QA hasta **4/4 PASS**.

**No demostrado:** ausencia total de ataques TOCTOU, firmas/propiedad de todos los ejecutables Autodesk, AutoCAD instalado 2023–2027, tráfico efectivo de servicios compartidos, WebView2 exclusivo, UI/UAC visual, AVG y reinicio completo. El evaluador F12 sigue `BLOCKED`.

## Siguiente trabajo

Conservar todas las fases en GitHub y avanzar hacia la prueba final integrada en Windows con AutoCAD genuino, sin solicitar pruebas fragmentadas al usuario. No fusionar ni distribuir RC1 mientras no se certifiquen los puntos esenciales.
