# ParcheCAD 4.3 — Auditoría externa, contrato de interfaz y continuidad

**Estado:** PR #22 en borrador, rama `feat/v4.3-wpf-dashboard`; NO release, NO merge en `main`, NO producción aprobada. Último ciclo completo de referencia: CI #166, 4/4 PASS. Un PASS en CI sin AutoCAD instalado **no certifica** bloqueo o restauración de aplicaciones reales.

## Leyes obligatorias

**KISS y anti-ruido:** conservar un solo motor de firewall/recuperación y una sola lógica de estados WPF; eliminar duplicación solamente con evidencia. No crear capas, servicios, drivers, bases de datos, tareas residentes, atajos ficticios ni «parches sobre parches». Corrige causa raíz y deja pruebas negativas. **No runtime sin documentación:** README, SPEC maestra, esta guía y protocolo F17 se mantienen coherentes. No certificar funcionalidad por apariencia, conteos, marcador de salida o exit code. Preflight → cambio focal → pruebas focales → QA global una vez → evidencia → NEXT. Proteger el PR Draft y todos los WIP; no publicar ni modificar el firewall del usuario sin consentimiento explícito.

## Arquitectura vigente

| Componente | Responsabilidad y límite |
|---|---|
| `Abrir_ParcheCAD.cmd` + `Dashboard.xaml/.ps1` | Interfaz principal WPF, dos pestañas, progreso, 10 estados y ventanas adaptables. |
| `Preview.ps1` / `WebViewAudit.ps1` | Dos consultas en procesos hijo separados; solo lectura, no bloqueo por PID. |
| `Monitor.ps1` | Observación temporal TCP/UDP; detener crea informe. Nunca bloquea. |
| `Reglas.ps1`, `Policy.ps1`, `Firewall.ps1` | Único motor elevado: Apply/RestoreFirewall/RestoreWebView2; revalidación, confirmación escrita, reglas identificadas y protección del runtime compartido. |
| `ProgramData\ParcheCAD\Operations` | Journals de aplicación propios. Persisten si se borra el directorio de ParcheCAD. |
| `ProgramData\ParcheCAD\Recovery` | Backup `.wfw` antes de borrar una regla y journal nuevo de restauración. |
| `Abrir_ParcheCAD_Clasico.cmd` | Respaldo WinForms temporal. Usar el MISMO motor y `RestoreFirewall`; no mantener una política de rollback alterna. |

### Contrato de acciones

- **ANALIZAR FIREWALL:** lee ejecutables AutoCAD 2023–2027, conflictos/filtros y rutas sin modificar reglas.
- **VERIFICAR Y APLICAR / BLOQUEO GENERAL AUTOCAD:** exige UAC, escribir `APLICAR`, journal y verificación elevada. Nunca bloquea `msedgewebview2.exe` compartido.
- **ANALIZAR WEBVIEW2:** solo captura observacional; si el informe completo confirma `SafeBlockingCandidates=0`, puede habilitar **BLOQUEO AUDITADO AUTOCAD**. Eso NO habilita bloqueo de WebView2: inicia un segundo preview AutoCAD y debe bloquear únicamente sus ejecutables verificados, cero conflictos, con revalidación al elevar.
- **INICIAR MONITOR / DETENER Y GUARDAR:** observación temporal, sin acciones de firewall. Al cerrar se solicita parada cooperativa y se comprueba el resultado del monitor.
- **RESTAURAR FIREWALL:** descubre firmas persistentes PCAD4 directamente en Windows Firewall aun sin archivo JSON; reglas AutoCAD ajenas requieren ID exacto. Revisa programa, grupo, hash y todos los filtros. 
- **RESTAURAR WEBVIEW2 AUTODESK:** no es restaurador global; requiere ruta `msedgewebview2.exe` MÁS identificador histórico vinculado expresamente a Autodesk (prefijos ambiguos exigen etiqueta Autodesk/AutoCAD). Una regla general queda EXCLUIDA aun si afecta el mismo EXE. Selección individual, confirmación y backup `.wfw` obligatorios. Nombre histórico NO demuestra aislamiento del runtime.
- **INFORMES:** abre carpeta de resultados de solo lectura después de consultas, `ProgramData\ParcheCAD\Operations` tras Apply o `ProgramData\ParcheCAD\Recovery` después de restaurar; código de salida 0 no equivale a regla eliminada.

## Auditoría adversarial de 10 pasadas (cierre de escritorio/CI, no certificación de producción)

| # | Pasada y evidencia revisada | Resultado y límite |
|---|---|---|
| 1 | Procedencia, HEAD, PR Draft, paquete distribuido, CRC y manifiesto SHA256 | PASS de integridad/consistencia CI. Sin merge ni release. |
| 2 | Leyes KISS, número de motores, dependencias, documentación redundante | Se mantiene motor único; se consolida esta guía activa, el historial anterior queda en Git. WinForms es deuda temporal protegida. |
| 3 | Arranque, XAML, accesibilidad básica, DPI sintético, 430/580/780/1050/1120 DIP | PASS de parser y render; DPI físico, teclado real, accesibilidad y UAC siguen pendientes. |
| 4 | Catálogo/rutas, junctions/symlinks, limitaciones, compartidos Autodesk | PASS de guardas y fixtures; rutas reales AutoCAD del usuario NO probadas. |
| 5 | Apply: UAC, confirmación escrita, hash de ID, filtros exactos, journal y rollback | PASS en suite y firewall sintético temporal; sin aplicar reglas al usuario. |
| 6 | Restauración sin carpeta: firma PCAD4, datos reales, exportación `.wfw`, TOCTOU | PASS de CI; se corrigió revalidación final de Group/Direction junto al EXE/ID antes de borrado. |
| 7 | WebView2: atribución PROBABLE, runtime compartido y restauración histórica limitada | PASS de prueba que conserva regla genérica aun compartiendo EXE; ninguna garantía de aislamiento por PID. |
| 8 | Monitor, cancelación, procesos hijo, StopRequested, informes parciales | PASS automatizado; se endureció validación semántica de `Result` y `StopReason`; cierre GUI físico no probado. |
| 9 | Estados WPF, botón auditado, progreso, informes incoherentes y destino del botón Informes | Defectos corregidos: validación de estado/conteos/filas del WebView2; vista previa coherente; métricas obsoletas eliminadas; Informes abre destino correcto. Nuevas pruebas negativas. |
| 10 | F0–F17, PS5.1/7, sintético TCP, paquete extraído con MOTW, fallback WinForms | PASS del conjunto CI; WinForms antes buscaba `informes/operaciones` y ahora usa `RestoreFirewall` sin exigir respaldo local. Prueba real con AutoCAD/AVG/GPO permanece BLOCKED. |

## Defectos corregidos en la auditoría

**AUD10-01 / P1:** WinForms clásico deshabilitaba la restauración sin carpeta `informes/operaciones` y pedía el manifiesto viejo. Unificado con `Reglas.ps1 -Mode RestoreFirewall`, el mismo motor que WPF. La restauración requiere UAC, copia independiente y confirmación, incluso si los archivos antiguos desaparecieron.

**AUD10-02 / P1:** el dashboard aceptaba como auditada una respuesta WebView2 con estado inesperado o conteos inconsistentes. El validador exige `AUDITORIA_WEBVIEW_COMPLETADA`, solo lectura, sin cambios, `SafeBlockingCandidates=0`, no aislamiento, filas y conteos coherentes y `AutomaticFirewallEligible=false`. Un resultado incorrecto no habilita bloqueo auditado.

**AUD10-03 / P1:** las vistas previas podían mostrarse como completas sin concordancia de `CatalogStatus`, `PlanState` y `Conflicts`; el monitor necesitaba comprobar `Result` y `StopReason`. Ahora se rechazan estados incoherentes.

**AUD10-04 / P1:** la restauración individual revalidaba ID/EXE/nombre pero no `Group` y `Direction` justo antes de borrar. Ahora rechaza esas modificaciones.

**AUD10-05 / P2:** el botón de informes abría la carpeta local aunque el journal estaba en ProgramData y el mensaje «terminó» podía confundirse con «restauró». Ahora usa el directorio correcto y no afirma eliminación sin comprobarla.

**AUD10-06 / P2 anti-ruido:** estados históricos A/B/C/D mezclados con hallazgos actuales en esta guía; sustituidos por un único contrato vigente. El historial original sigue en Git.

## Salida de seguridad y bloqueos reales

**NO APROBADO PARA PRODUCCIÓN:** falta una única QA interactiva en Windows con AutoCAD genuino 2023–2027, distintas DPI y escalas, arranque/monitor/salida, UAC y confirmación, reglas y conexión reales TCP/UDP IPv4/IPv6, AVG/GPO activos, aplicaciones WebView2 ajenas intactas, reinicio y restauración. Una regla presente NO certifica que el tráfico esté bloqueado; un monitor sin conexiones no prueba ausencia de tráfico. No hacer nuevas auditorías repetidas sin evidencia nueva.

**NEXT:** revisar CI de cierre, hashes del ZIP final y PR Draft; después el usuario ejecuta exclusivamente pruebas de lectura/UI y aporta resultados. Para el laboratorio de bloqueo/restauración real, solicitar autorización independiente. **SIGUIENTE: CHATGPT para cierre documental/QA; después TÚ para validación Windows.**


## Incidencia de Windows real: consola Apply aparentemente congelada (2026-10-27)

**Evidencia del usuario:** tras pulsar Aplicar, la consola elevada mostraba `ParcheCAD 4.0 | Motor de reglas por ruta` y `Descubriendo instalaciones reales y ejecutables sin modificar Windows...` sin nuevos avances. En el motor actual esa línea aparece **antes** de consultar registro, firmas, catálogo y filtros. Sin escribir `APLICAR` el proceso no puede alcanzar la creación de reglas, aunque pueden existir reglas previas. El texto de versión era legado de presentación; se actualiza a 4.3.

**Causa verificada en código:** el proceso sincronizado no mostraba ninguna actualización mientras catalogaba, y CI históricamente corría sin instalaciones AutoCAD. **Corrección KISS:** etapas visibles 1/3 registro/firma, 2/3 carpetas/EXE (contador de carpetas y EXE cada ~5 segundos) y 3/3 consulta de filtros, sin exponer rutas privadas completas; tiempo tope por árbol de instalación 180 segundos -> resultado `PARCIAL` y **Apply bloqueado**, nunca convertir timeout en éxito; cabecera 4.3. `Preview` WPF conserva su proceso independiente. Pruebas F1/F2 cubren catálogo con progreso y presupuesto de inspección agotado; CI global mantiene Apply/rollback sintéticos. **Límite:** un único `Get-ChildItem`/verificación de firma bloqueante no se interrumpe de manera asíncrona; no presentar el tope como watchdog absoluto de toda la aplicación. En Windows real verificar el catálogo, sin confirmar `APLICAR` antes de QA.


## Evidencia Windows real — P1 progreso y estado de aplicación (2026-10-27)

El usuario mostró (a) 31 candidatas AutoCAD 2027 y petición escrita `APLICAR`; (b) barra de progreso tardía; (c) el panel diciendo `TERMINÓ · SIN VERIFICAR` tras un código 0; (d) Analizar Firewall mostrando candidatas sin indicar cuáles estaban ya instaladas. **Causa confirmada:** el panel no consumía el journal Apply y Preview solo serializaba `Candidates`/`Conflicts`; el porcentaje del motor únicamente aparecía tras comenzar a crear reglas. **Corrección focal:** GUID por operación, estado transitorio de seis fases con animación inicial, una sola confirmación escrita, verificación final de todos los filtros antes del journal `APPLIED`, resultado vinculado al ID (creadas vs existentes) y consulta de solo lectura con `InstalledValid/MissingRules/UnverifiedRules`. No añadir segundo motor ni servicio. La barra es indeterminada durante descubrimiento; no inventar porcentajes. **Límite:** CI sin AutoCAD real no certifica el tráfico o UAC del usuario; no volver a pulsar Apply hasta leer el estado desde Analizar Firewall.
