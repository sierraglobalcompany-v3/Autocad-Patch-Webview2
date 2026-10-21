# F17 — Protocolo unico de QA integrada (LAB Windows, NO RC1)

**Estado:** protocolo y facilitador read-only; no se ha ejecutado con AutoCAD genuino ni escritorio/UAC real. F12 conserva Decision=BLOCKED y ProductionCertified=false. Desarrollo en PR Draft apilado sobre F16.

## Objetivo y limites

Preparar **una unica sesion documentada y reproducible** en VM Windows con escritorio real, snapshot recuperable, AutoCAD genuino/autorizado y controles de seguridad habilitados. Una sesion debe entregar evidencia verificable de las diez puertas F12. **El facilitador F17 NO aplica reglas**, no mide por si solo el trafico real, no inicia AutoCAD y no certifica RC1. No utilizar el PC principal para experimentos fragmentados.

**Cuatro leyes:** (1) KISS: reutilizar F0 y F12, sin motor nuevo; (2) antirruido: una matriz y un protocolo, no diez informes paralelos; (3) antiparches: investigar causa raiz e impacto cruzado antes de corregir; (4) UX Pro Max: estados reales, detener si se pierde trazabilidad.

## Requisitos STOP previos

- VM/laboratorio propio **aislado del equipo principal**, Windows interactivo, snapshot restaurable y espacio de evidencia LOCAL fuera del repositorio.
- Instalacion y licenciamiento legitimos de las versiones AutoCAD objetivo; no modificar activacion, licencias ni componentes del proveedor.
- Sesion con permiso explicito del operador; no modificar firewall ajeno, AVG/Defender, servicios compartidos, GPO o WebView2 global.
- Aplicaciones de control instaladas cuando corresponda (Outlook y WhatsApp); documentacion de versiones, estado inicial y aceptacion del riesgo de perdida de funciones en linea.
- Herramientas autorizadas para trazas de conexiones TCP/UDP IPv4/IPv6 con PID, proceso y servicio; sus registros crudos **no** se suben a GitHub (pueden contener IP, usuarios, hosts y datos de sesion).
- Si no se dispone de esta infraestructura, ejecutar solo tests CI y cerrar F17 como PROTOCOLO_PREPARADO / QA_REAL_BLOCKED, **no RC1**.

## Flujo ejecutable (una sesion)

1. **Inventario del entorno.** Snapshot VM, fecha/hora, version Windows, hashes de binarios propios, versiones de AutoCAD/AVG, perfil de red y plan de reversion local. Documentacion sensible en laboratorio, solo clasificacion sanitizada en el repositorio.
2. **Baseline F17 (solo lectura).** Desde repositorio clonado en rama F17 ejecutar:
   powershell.exe -NoProfile -File .\tools\Invoke-ParcheCADF17.ps1 -Mode Before -SessionDirectory C:\PCAD_LAB_SESSION
   Debe generar un unico diagnostico.json bajo before/. Si el diagnostico es parcial, STOP; no inferir ausencia de software ni trafico.
3. **Baseline operativo y red.** Abrir AutoCAD autorizado, Outlook/WhatsApp. Capturar funcionalidad y trazas por proceso/servicio; observar WebView2 por proceso padre + UDF + timestamps, no atribuir propiedad solo por PID. Usar trazas con permisos explicitos, intervalos conocidos y control de privacidad. Cubrir TCP/UDP, IPv4/IPv6, resoluciones DNS/servicios/proxies segun esten presentes.
4. **Previsualizacion y autorizacion.** Abrir GUI de ParcheCAD, revisar lista exacta de EXE propios y conflictos; no aplicar si hay junction/symlink, errores de inspeccion, reglas ajenas o journals pendientes. Registrar captura UX con DPI/foco/progreso/UAC aceptada y denegada sin publicar datos privados.
5. **Aplicacion controlada** en VM mediante interfaz oficial, **solo despues** del punto anterior y con confirmacion; **nunca** mediante el script F17. No crear reglas globales para msedgewebview2.exe, no interferir con software ajeno ni alterar licencias. Verificar filtros efectivos Any/regla propia, estados CONFLICT y recuperabilidad.
6. **Prueba sostenida.** Bajo actividades reproducibles, registrar trafico real **antes/durante/despues**, incluyendo procesos Autodesk compartidos y WebView2. Medir que las conexiones de AutoCAD pretendidas no salen de la VM y que apps ajenas funcionan. Un firewall EXISTS_VALID es solamente configuracion, no prueba de aislamiento universal. Separar claramente **WebView2 ejecutado** de **WebView2 con salida de red**.
7. **Reinicio/recuperacion.** Ensayar en VM estado aplicado, reinicio real, operacion inconclusa solo si el snapshot permite recuperacion segura, deteccion de journal y rollback propio. Ante fallo de recuperacion: STOP y restaurar snapshot; nunca borrar regla ajena. AVG/Defender permanece activo durante toda la sesion.
8. **After F17 (solo lectura).** Tras la operacion y la reversion acordada ejecutar:
   powershell.exe -NoProfile -File .\tools\Invoke-ParcheCADF17.ps1 -Mode After -SessionDirectory C:\PCAD_LAB_SESSION
   Debe existir un diagnostico.json distinto del Before y posterior en GeneratedAt. Dos rutas con el mismo contenido/hash SHA256 o un reloj invertido provocan STOP; la misma maquina **no** se puede certificar por JSON y debe cotejarse manualmente con evidencia local.
9. **Evaluacion F12 + matriz F17.**
   powershell.exe -NoProfile -File .\tools\Invoke-ParcheCADF17.ps1 -Mode Evaluate -SessionDirectory C:\PCAD_LAB_SESSION
   El facilitador reutiliza F12 y genera evaluacion/RC12_EVALUACION.json, RC12_RESUMEN.txt y F17_MATRIZ_EVIDENCIA.json con diez puertas y ExternalEvidence=PENDING_REVIEW. No sobreescribe una evaluacion; crear nueva sesion si es necesario. La evaluacion valida capturas F12, SHA256 diferentes y orden temporal, sin asumir que son de la misma maquina.
10. **Revision independiente.** El operador relaciona cada puerta con evidencia local, hashes y resultados observables, anonimiza un **resumen** para revision de codigo, consigna PASS/BLOCKED solo con evidencia manual revisada. Hasta integrar explicitamente ese proceso de revision a una puerta futura, **F12/F17 NO pueden certificar RC1**.

## Puertas F12 y evidencias minimas

| Puerta | Evidencia necesaria | STOP si |
|---|---|---|
| DIAGNOSTICOS | Antes/despues distintos, 10 etapas, recuperacion sana | Estado parcial, informe duplicado |
| AUTOCAD_INSTALADO | Firma, version y funcionamiento real por ano | Archivo ficticio o sin autorizacion |
| REGLAS_SALIENTES | Regla PCAD4 efectiva, filtros completos y sin conflicto | GPO/regla ajena/restriccion |
| TRAFICO_AUTODESK | Trazas repetidas por proceso/servicio TCP+UDP IPv4+IPv6 | Trafico sin atribuir, cobertura insuficiente |
| WEBVIEW2_AUTOCAD | Procesos, anfitrion/UDF, ejecucion y trafico medidos | Confundir no trafico con no ejecucion |
| OTRAS_APLICACIONES | Outlook/WhatsApp antes y despues funcionales | Regresion de terceros |
| GUI_UAC | UAC si/no, foco, DPI, cancelar y errores | UI congelada o elevacion silenciosa |
| REINICIO_Y_ROLLBACK | Reboot real, journal, desaparicion de reglas propias | Restos propios, cambios a reglas ajenas |
| AVG_ACTIVO | Antivirus activo y eventos revisados | Alerta o desactivacion |
| AUTOCAD_FUNCIONAL | Abrir/editar/guardar segun funciones autorizadas | Fallo no aceptado o de licenciamiento |

## Separacion de evidencia y privacidad

**No subir a GitHub:** trazas ETL/PCAP, direcciones IP, hostnames, identificadores de licencias, numeros de serie, PID vinculados a usuarios, contrasenas, credenciales, rutas personales, journals con Program real, capturas de terceros. Conservar originales cifrados o en carpeta privada local con control de acceso; publicar unicamente matriz redactada de hallazgos sin datos sensibles. F17_MATRIZ_EVIDENCIA.json es un checklist, no una afirmacion de haber ensayado trafico. Flags ContentsDistinctVerified/ TimestampOrderVerified documentan solo el formato y orden; SameMachineVerified=false sin certificacion manual.

## Prueba de reconstruccion CI (sin AutoCAD)

- El workflow ejecuta los fixtures F17 tanto en Windows PowerShell 5.1 como en PowerShell 7.
- Un smoke aislado y read-only crea capturas nuevas Before y After y la evaluacion F12/F17 en Windows de GitHub. No hay AutoCAD instalado y no hay prueba de las puertas de red/GUI/UAC reales.
- F6 extrae el ZIP DEV allowlist, verifica SHA256 y ejecuta Invoke-ParcheCADF17.ps1 **desde el ZIP** contra dos informes sinteticos. El resultado obligatorio es BLOCKED con diez puertas. Los tests no se incluyen en el ZIP de distribucion DEV y permanecen reproducibles en GitHub.
- CI en verde demuestra que el software puede reconstruirse y ejecutarse en un Windows efimero; **no** demuestra funcionamiento con AutoCAD genuino.

## Resultados que permiten cerrar F17

- **F17 PREPARADO:** script, guia, tests PS 5.1/7, ZIP DEV reproducible y CI asociado al HEAD final verdes.
- **QA REAL BLOCKED:** hasta disponer de VM, AutoCAD real, evidencias TCP/UDP IPv4/IPv6 y todos los controles.
- **RC1 BLOCKED:** hasta completar y revisar las diez puertas y definir un mecanismo posterior de aprobacion explicita sin autoaprobacion.
- **NEXT:** ejecutar una sola QA integral autorizada cuando exista laboratorio; si descubre defecto, corregir causa raiz y QA cruzada antes de reconsiderar RC1.

**No merge, no deploy, no release, no cambio de licencias ni de antivirus.**


## Monitor temporal incorporado al panel (una prueba en el Windows del usuario)

La interfaz muestra **antes de iniciar** una ventana con cinco pasos y exige confirmar para empezar. El panel mantiene un resumen de la secuencia mientras observa. El monitor **no** inserta automáticamente un marcador cuando se aplican las reglas; anotar la hora exacta de aplicación (hh:mm:ss) para separar los eventos.

**Orden recomendado:** cerrar AutoCAD → verificar que la línea base no tiene reglas propias previamente aplicadas (revertir solo las propias desde ParcheCAD si procede) → iniciar monitor → abrir AutoCAD y probar 1–2 minutos SIN aplicar nuevas reglas → cerrar AutoCAD → aplicar desde ParcheCAD con confirmaciones → anotar la hora → reabrir AutoCAD y repetir las mismas acciones 1–2 minutos → detener y guardar. Si había reglas propias activas y no se revirtieron, NO presentar la primera medición como una línea base sin bloqueo.


1. Abrir ParcheCAD, dejar terminar el diagnostico inicial y pulsar **INICIAR MONITOR AUTOCAD / WEBVIEW2**. No necesita administrador para las consultas de lectura disponibles.
2. Abrir AutoCAD y reproducir las funciones relevantes. Para comparar estados, si se autoriza, aplicar/revertir desde los controles normales del programa durante la misma captura; el monitor **no aplica reglas**.
3. Pulsar **DETENER MONITOR Y GUARDAR LOG**. Se solicita el cierre cooperativo del proceso, no se mata AutoCAD/WebView2 ni se deshabilita el antivirus. Si no se detiene, finaliza por seguridad a los 600 segundos.
4. Usar **ABRIR INFORMES** y revisar la carpeta `informes/monitor_<id>/monitor.json` y `resumen.txt`. Es una unica sesion local. Compartir solo tras revisar su contenido.

**Datos capturados:** cambios entre muestras de procesos AutoCAD, Autodesk y WebView2, PID/padre, inicio (identidad), atribucion probable al host, conexiones TCP observadas por puerto/estado/clase de direccion y presencia de endpoints UDP. Sin IP remotas, URL, comandos ni rutas de usuario. Un endpoint UDP no prueba envio. Una conexion TCP observada no demuestra que otras fueron bloqueadas. Algunos eventos muy cortos se pueden perder entre muestras, y la reutilizacion de PID o WebView2 compartido limita la atribucion. No se capturan paquetes ni se cambia la auditoria de Windows. Los campos `BlockedTrafficVerified=false` y `WebViewIsolationVerified=false` siempre expresan los limites reales.

**QA:** `tests/Monitor.Tests.ps1` comprueba duracion acotada, cierre cooperativo, no sobrescritura, privacidad y banderas sin certificacion en PS5.1/PS7; el test de ZIP prueba el monitor desde el paquete extraido. El flujo visual interactivo final en PC de usuario sigue pendiente hasta que haya informe real. No cargar automaticamente los logs al repositorio.
