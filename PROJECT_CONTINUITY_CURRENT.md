# PROJECT_CONTINUITY_CURRENT — ParcheCAD 4.0

**Actualizado:** 2026-10-21. **Estado:** F0–F17 (F17 protocolo LAB read-only, sin prueba AutoCAD) desarrolladas en PRs Draft; **SIN RC1 / RELEASE / DEPLOY / MERGE**.  
**Repositorio fuente única:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2  
**Rama vigente:** `fix/f17-integrated-qa-protocol` · **PR #19 Draft**, apilado sobre #18→#17→#16→#15→#14→#13→#12→#11→#10→#9→#8→#7→#6→#5→#4→#3. **`main` aún no tiene estas fases.**  
**CI F17 anterior al refinamiento:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39557943813 (#136, 4/4 SUCCESS). Revisar siempre CI del HEAD final del PR #19 antes de certificar nuevos cambios. La certificación con AutoCAD real sigue pendiente. No confundir con certificación AutoCAD. Verificar CI sobre último HEAD tras commits de docs.

## Objetivo del usuario y límites no negociables

El usuario quiere impedir la conectividad saliente de **AutoCAD 2023–2027 y todos los componentes Autodesk que corresponda**, aun perdiendo funciones en línea. Quiere también que **AutoCAD no ejecute WebView2**, pero sin interrumpir WhatsApp, Outlook ni otras aplicaciones que comparten el runtime `msedgewebview2.exe`.

**Situación REAL:** ParcheCAD inventaría instalaciones, EXE y servicios y crea reglas salientes solo para `AUTOCAD_PRODUCTO` con confirmación y reversión. No se probó bloqueo total de Autodesk ni ejecución cero de WebView2. Las reglas por ruta no bloquean automáticamente servicios/proxies ni permiten distinguir anfitriones del runtime Microsoft compartido. **Evitar tráfico ≠ impedir ejecución de WebView2.** No hay RC1 aprobada.

### Cuatro leyes obligatorias
1. **KISS:** soluciones simples, eficientes y óptimas, sin servicios residentes, drivers, arquitectura superflua ni procesos innecesarios.
2. **Anti-ruido:** unir, optimizar, mejorar o eliminar duplicaciones con evidencia; no añadir motores paralelos.
3. **No parches:** corregir la causa en el origen y verificar todos los consumidores, evitando remedios aislados.
4. **UX/diseño:** panel claro, progreso y mensajes reales; no habilitar acciones peligrosas ni mostrar COMPLETO sin pruebas.

**Metodología:** código y documentos en GitHub para reconstrucción, Codex solo si estrictamente indispensable; QA transversal, no ir y volver con pruebas parciales en el PC del usuario. Preparar **una sola prueba final integrada** cuando exista entorno real y criterios suficientes.

**Protección:** nunca bloquear globalmente `msedgewebview2.exe`; no desactivar AVG/Defender, modificar binarios/licencias, tareas o reglas ajenas. Admin solo explícito, reglas PCAD4 con journal reversible; rutas/IP privadas excluidas de artefactos compartidos.

## Implementación F0–F17 (pruebas de CI, no certificación del producto)

| Fase | Hecho | Alcance de QA |
|---|---|---|
| F0–F2 | Inventario/GUI, servicios, tareas, reglas y reportes | PS5.1/7, consulta read-only |
| F3 | Observación WebView2 por PID/padre/UDF y conexiones | Atribución PROBABLE, sin aislamiento |
| F4 | Plan firewall por EXE propio y rollback | Regla temporal real Windows |
| F5 | Raíces personalizadas, datos saneados, recuperación | Fixtures |
| F6 | DisplayIcon, ZIP reproducible SHA256, CREATING | Windows efímero |
| F7 | Bloqueo fail-closed en journal corrupto/pending | Diagnóstico parcial real |
| F8 | Validación única de diez etapas, recuperación, plan y salida de hijo | WinForms SelfTest |
| F9 | Eventos Analizar/Cancelar/Cerrar y protocolo fin de diagnóstico | WinForms por eventos sin escritorio/UAC |
| F10 | Terminación PID propio y recuperación desde otro proceso | Firewall temporal en Windows, no reboot |
| F11 | Matriz de cobertura EXE/servicios/WebView2/TCP/UDP en JSON/TXT/UI | CI #99 4/4 PASS |
| F12 | Evaluación de diez puertas RC1 desde diagnósticos antes/después | CI #103 PASS; nunca RC1 automático |
| F13 | Prueba TCP IPv4 real de EXE ficticio: conexión permitida → bloqueada → restaurada; otro EXE intacto | CI #109 PASS |
| F14 | Inventario acotado de Autodesk compartido y advertencias de profundidad/cantidad, sin bloqueo automático | CI #117 PASS |
| F15 | Validación de rutas: sin junction/symlink en plan y Apply, avisos de catálogo parcial | CI #124 PASS |
| F16 | Fallo seguro ante filtros NetSecurity restringidos | CI #133, 4/4 PASS |
| F17 | QA integrada solo lectura; captura temporal+hash antes/después, matriz F12 | CI #136 base PASS; último HEAD por confirmar |

### F12 — evaluación RC1 disponible

- `src/ParcheCAD.RCGates.ps1`: compara dos diagnósticos sanitizados existentes y valida esquema, diez etapas, recuperación, matriz F11 y coherencia de conteos de reglas. No accede a firewall, no observa red nueva ni ejecuta AutoCAD.
- `tools/Invoke-ParcheCADRC12.ps1`: lee `-Before` y `-After`, produce `RC12_EVALUACION.json` y `RC12_RESUMEN.txt` (sin rutas/IP privadas). Código de salida 0 indica **evaluación completada**, NO aprobación de RC1.
- Diez puertas: DIAGNOSTICOS, AUTOCAD_INSTALADO, REGLAS_SALIENTES, TRAFICO_AUTODESK, WEBVIEW2_AUTOCAD, OTRAS_APLICACIONES, GUI_UAC, REINICIO_Y_ROLLBACK, AVG_ACTIVO, AUTOCAD_FUNCIONAL.
- Solo el formato de los dos diagnósticos puede obtener `PASS`; instalar acad.exe puede quedar `OBSERVADO`; reglas `CONFIGURACION_OBSERVADA`. **`Decision=BLOCKED`, `ProductionCertified=false`** en tanto no exista evidencia real de todas las puertas. No hay botón de autoaprobación.
- `tests/F12.RCGates.Tests.ps1` prueba escenarios vacíos, JSON contradictorios y recuperación pendiente PS5.1/7.
- `tests/F12.RealWindows.Integration.ps1` usa un diagnóstico Windows GitHub-hosted real (duplicado antes/después **solo para smoke**) y exige `Decision=BLOCKED`; no toca firewall.
- Evidencia y plan de sesión única: `docs/F12_GATE_RC1_QA_INTEGRADA.md`. ZIP DEV incluye evaluador, CLI y guía; `tools/Build-ParcheCAD.ps1` determinista, `.github/workflows/f0-static-qa.yml` con cuatro jobs Windows.
- README y SPEC armonizados; PR #14 Draft sobre ramas anteriores.

## F13 — último checkpoint de conectividad

- **Código:** `tests/F13.SyntheticEgress.Integration.ps1`, solo ejecutable en runner GitHub-hosted con administrador. Compila un cliente TCP IPv4 ficticio como `acad.exe` en un directorio único temporal y otro idéntico como `ProbeControl.exe` en ubicación diferente. **No es AutoCAD real**.
- **Resultados CI #104:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39548196571 — línea base (ambos EXE conectan), regla saliente PCAD4, dos conexiones bloqueadas al objetivo, control permitido, rollback y recuperación de ambas conexiones. Tests antiguos y ZIP DEV también PASS.
- **Evidencia:** `docs/F13_PRUEBA_EGRESO_TCP_REAL.md`. Se reutilizó el motor F4, sin arquitectura nueva; regla temporal propia eliminada al finalizar.
- **Limitaciones:** la prueba F13 **no** valida AutoCAD instalado, servicios compartidos, conexiones UDP/IPv6, túneles/proxies ni WebView2. La evaluación F12 sigue `Decision=BLOCKED`. No elevar una prueba sintética a cobertura total.
- **Entrega:** PR #15 Draft sobre #14 y anteriores; sin merge ni release. Informes privados fuera del repositorio.

## F14 — último checkpoint de inventario

- **Hallazgo:** la exploración anterior no recorría raíces conocidas de aplicaciones Autodesk compartidas fuera de las instalaciones AutoCAD. La profundidad máxima de carpetas no siempre generaba una advertencia, por lo que parecía más exhaustiva de lo que era.
- **Refactor KISS:** `src/ParcheCAD.Catalogo.ps1` contiene un solo walker acotado y sin atravesar enlaces/junctions, reutilizado para producto y compartidos. Añade descubrimiento únicamente en raíces conocidas AdODIS, Autodesk Access/Desktop App, Identity Services y Common Files/Autodesk Shared cuando existen.
- **Cobertura:** `Status` del producto y `SharedStatus` del inventario compartido son independientes; una raíz compartida incompleta se documenta pero no deshabilita por sí sola las reglas válidas para producto. `Sections.CatalogScope` y WinForms informan explícitamente `SharedAutomaticBlocking=false`.
- **Garantía:** EXE compartidos permanecen inventario, no candidatos automáticos del motor F4; `msedgewebview2.exe` continúa excluido de bloqueos globales. Ninguna afirmación de tráfico completamente aislado.
- **QA:** `tests/F14.SharedCatalog.Tests.ps1` en PS5.1/7; prueba de integración WinForms exige la sección/advertencia; pruebas F13 de tráfico TCP y reversión + ZIP reproducible siguen verdes. Evidencia `docs/F14_INVENTARIO_COMPARTIDO_QA.md`. CI #114: https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39549747614.
- **Pendiente RC1:** AutoCAD real instalado, servicios compartidos en ejecución, tráfico efectivo de Autodesk, WebView2 exclusivo NO RESUELTO, sesión GUI/UAC real, AVG y reinicio completo. No requerir al usuario pruebas por fase.

## F15 — último checkpoint de seguridad de rutas

- **Defecto real:** una ruta que empieza por una instalación AutoCAD puede atravesar una junction o enlace simbólico intermedio y alcanzar una aplicación ajena.
- **Corrección en el origen:** `Assert-PCADNoReparseComponents` en `src/ParcheCAD.Policy.ps1` inspecciona todos los segmentos existentes hasta la raíz de la unidad y rechaza enlaces. `Assert-PCADProgramInstallRoot` la ejecuta al planificar y preparar reglas.
- **Segunda barrera:** `src/ParcheCAD.Firewall.ps1` repite la validación justo antes de `New-NetFirewallRule`, reduciendo el intervalo entre comprobación y uso. No prometer inmunidad absoluta a condiciones de carrera.
- **Inventario honesto:** `Get-PCADCatalogTree` marca `PARCIAL` cuando omite carpetas o ejecutables enlazados.
- **Rollback preservado:** la eliminación de reglas propias exactas sigue siendo posible cuando AutoCAD fue desinstalado o una carpeta cambió después de aplicar; la comprobación de propiedad de regla y grupo sigue siendo obligatoria.
- **QA:** `tests/F15.ReparseGuard.Tests.ps1` crea junctions reales en TEMP; PS5.1/7, firewall temporal, TCP sintético y ZIP reproducible PASS. La primera ejecución evidenció fallo de limpieza de junction en PS5.1; se corrigió mediante borrado no recursivo sin tocar el destino. Evidencia: `docs/F15_REPARSE_GUARD_QA.md`; CI #119: https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39551110553.
- **No certifica RC1:** AutoCAD real, servicios compartidos, tráfico TCP/UDP IPv6, WebView2 exclusivo, UAC/DPI, AVG y reboot sin ensayar.

## F16 — último checkpoint de integridad NetSecurity

- **Defecto:** `Get-PCADActualRuleStatus` solo validaba EXE, grupo, salida, Block, Enabled y perfil; los filtros externos podían limitar la regla a un protocolo, IP, puerto, servicio o interfaz y aun recibir `EXISTS_VALID`.
- **Corrección KISS:** `src/ParcheCAD.Policy.ps1` inspecciona los filtros asociados de puertos, direcciones, servicio, tipo y alias de interfaz; todos requieren `Any` y unicidad. En caso de desviación declara `CONFLICT`; error de inspección es fail-closed, no `MISSING`.
- **Pruebas:** `tests/F3F4.Tests.ps1` introduce drifts de TCP, IP, Spooler, Wireless y Ethernet; `tests/F4.RealFirewall.Integration.ps1` modifica **solo una regla propia temporal** a IP `192.0.2.77`, exige CONFLICT y restaura `Any` en finally; tests F13 TCP y rollback siguen transversales. Documentación `docs/F16_INTEGRIDAD_FILTROS_FIREWALL.md`.
- **Alcance honesto:** regla local válida no implica tráfico Autodesk totalmente aislado si hay GPO, servicios/proxies, WebView2 Microsoft compartido o reglas ajenas. AutoCAD 2023–2027 real, UAC visual, AVG y reinicio no ensayados.
- **PR #18 Draft**, sin merge ni RC1. El workflow Windows F0–F16 y ZIP DEV mantienen fuente reproducible.

## Reconstrucción desde GitHub

Clonar exactamente la **rama F17**, leer `PROJECT_CONTINUITY_CURRENT.md` + `docs/SPEC_MAESTRA.md` + `docs/F12_GATE_RC1_QA_INTEGRADA.md`, ejecutar GitHub Actions y revisar 4/4 jobs. El artifact temporal `ParcheCAD_4.0_DEV_NOT_RELEASE` contiene ZIP allowlist y SHA256; **NO es instalador RC1 ni está listo para Apply en PC principal**. Ningún JSON local antiguo es necesario para reconstruir el software.

## Qué bloquea RC1

1. AutoCAD verdadero 2023–2027 no ha sido probado en una VM con producto auténtico y software autorizado.
2. No hay mediciones sostenidas de egress IPv4/IPv6 TCP/UDP ni cobertura confirmada de proxies/servicios Autodesk compartidos.
3. **WebView2 exclusivo de AutoCAD: NO RESUELTO.** Una regla WebView2 global es inaceptable porque afectaría otras aplicaciones.
4. UAC real aceptada/denegada, botones visuales, DPI, foco y AVG habilitado no han sido verificados en escritorio auténticamente interactivo.
5. Reinicio físico del sistema durante modificación y recuperación posterior no ensayados (reabrir PowerShell sí).
6. ZIP DEV probado en Windows GitHub-hosted, pero no existe release ni soporte de implementación certificado.

## NEXT único

**SIGUIENTE: ejecutar una única QA final con AutoCAD real en LAB aislado cuando esté disponible:** usar la evidencia F13 para distinguir pruebas sintéticas del producto y preparar un entorno Windows interactivo con AutoCAD autorizado, snapshot de restauración, AVG activo, registro de conexiones, prueba UAC y rollback/reinicio. Solo entonces evaluar la evidencia de las diez puertas; si WebView2 sigue sin solución exclusiva, mantener ese objetivo como BLOCKED y plantear una decisión de alcance explícita, **sin declarar éxito falso**. No pedir tests por módulos al usuario, no merge ni Release hasta decisión basada en evidencias.


## F17 — protocolo QA integrada (2026-10-21)
- Rama `fix/f17-integrated-qa-protocol` apilada sobre F16, sin merge, release ni pruebas con AutoCAD real.
- `tools/Invoke-ParcheCADF17.ps1`: solo lectura; `Before`, `After` y `Evaluate`, con carpetas distintas y bloqueo de sobrescritura; reutiliza F0 y F12; exige GeneratedAt posterior y SHA256 distinto (no certifica mismo equipo), no aplica firewall ni aprueba RC1.
- `docs/F17_PROTOCOLO_QA_INTEGRADA.md`: sesión única de laboratorio, evidencia TCP/UDP IPv4/IPv6, servicios, WebView2 compartido, GUI/UAC, AVG y reinicio/rollback.
- `tests/F17.Session.Tests.ps1`: fixtures de evaluación de 10 puertas y rechazo fail-closed. CI #136 del HEAD anterior verde; revalidar HEAD actual tras integridad temporal y antirreplay.
- **NEXT:** verificar CI y ejecutar sesión única solo cuando exista VM Windows con AutoCAD legítimo; RC1 sigue BLOCKED.
