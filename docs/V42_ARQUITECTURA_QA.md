# ParcheCAD 4.2 - Separacion firewall y WebView2

## Decisiones del usuario
Firewall AutoCAD: no necesita el analizador de trafico; usar lista local de ejecutables ya descubiertos/conocidos y verificar existencia. El analizador se dedica SOLO a WebView2. El objetivo es evitar afectar WhatsApp, Outlook u otras aplicaciones que comparten el runtime Microsoft.

## Implementacion
- Botones Ver reglas AutoCAD / Verificar y aplicar independientes del informe de 10 etapas. La consola administrativa de src/ParcheCAD.Reglas.ps1 conserva deteccion de instalaciones, catalogo de EXE de producto, validacion de ruta y filtros, recovery, UAC y confirmacion escrita. Usa -SharedRoots @() para no inventariar software compartido para bloqueo AutoCAD.
- src/ParcheCAD.WebViewAudit.ps1 obtiene snapshot de procesos y red, correlaciona padre/UDF con AutoCAD y reporta atribucion probable. Candidato de bloqueo WebView2 = 0 (runtime compartido). No crea reglas, mata procesos ni modifica firewall.
- Monitor de 10 min sin cambios de seguridad; pestaña aparte.
- Interfaz WinForms limpia: tarjetas, agrupacion clara, botones diferenciados. No introducir drivers, servicio residente ni mecanismos de interceptacion de paquetes.

## Riesgos y criterios
- No existe en este repo una lista fija verificada de 96 rutas historicas; se usa catalogo construido de la instalacion real, no la lista inventada.
- Un PID, PPID, UserDataFolder o vista de TCP es evidencia observacional, no identidad persistente para aislar trafico en el Windows Firewall.
- Reglas de AutoCAD por EXE afectan tambien funcionalidades y licencias. Se exigen dos confirmaciones.
- Bloqueo global de msedgewebview2.exe prohibido. El auditor no concede aprobaciones de bloqueo por simple parentesco.
- CI: ps5.1/ps7, fixture y ZIP extraido, F6 WebView audit, F4/F13 egress efimero; no QA AutoCAD real ni prueba visual de desktop.
- Release RC1: bloqueada hasta prueba con AutoCAD del usuario, revision visual, conteo de EXE y aplicar/rollback autorizados.

## Siguiente
Validar UI Windows real, reglas candidatas por version, visualizacion auditoria y journal de operaciones sin tocar programas ajenos.


## Correccion focal: «Ver reglas» tardaba 1 minuto y congelaba WinForms

Causa confirmada en codigo: el handler `preview.Add_Click` ejecutaba `Get-PCADInstallations`, `Get-PCADExecutableCatalog` y `New-PCADRulePlan -CheckExisting` en el **hilo de la UI**. El inventario y NetSecurity son sincronos, por lo que Windows no repintaba la ventana y no habia barra activa hasta mostrar el resultado (31 candidatas y 0 conflictos en el equipo del usuario).

Se mueve el mismo calculo a `src/ParcheCAD.Preview.ps1`: salida JSON independiente y marcador 0/2, archivo de etapa 1/3 a 3/3, sin reglas ni operaciones administrativas. El timer del panel presenta etapa + segundos + `ProgressBarStyle.Marquee` (sin porcentajes inventados); `CANCELAR CONSULTA` detiene solamente el proceso de vista previa, confirma su finalizacion y no proclama bloqueo. `PCAD-Finish` valida schema, `ReadOnly`, `NoFirewallChanges` y conteos antes de actualizar tarjetas o mostrar resultados. Prueba GUI CI F9 verifica retorno rapido (<5 s en runner), hijos y limpieza; F6 ejecuta worker desde ZIP extraido, verifica integridad y estado.
