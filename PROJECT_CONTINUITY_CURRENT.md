# PROJECT_CONTINUITY_CURRENT — ParcheCAD 4.0

**Fecha:** 2026-10-21 · **Estado:** desarrollo F0–F8; **SIN RC1, SIN RELEASE NI DEPLOY**.  
**Repositorio único:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2  
**Rama de trabajo actual:** `feat/f8-ui-report-safety` · **PR #10 Draft** (apilado sobre #9 → #8 → #7 → #6 → #5 → #4 → #3).  
**Main:** no fusionada con estas funcionalidades. Nunca anunciar que el código de los PR está en `main`.

## 1. Solicitud y límites que deben sobrevivir a otros chats

La aplicación debe gestionar bloqueos de conectividad saliente para AutoCAD 2023–2027 y componentes Autodesk relacionados. El usuario acepta pérdida de funciones online, pero exige que el uso compartido de Microsoft WebView2 por WhatsApp, Outlook u otras apps no quede bloqueado indiscriminadamente. También desea que AutoCAD no use WebView2, un objetivo **distinto** de bloquear conexiones de red; aún no está demostrado ni implementado.

No afirmar que «todo Autodesk está desconectado» ni que «AutoCAD no usa WebView2»: el bloqueo por ruta de EXE principal/producto no cubre servicios Autodesk compartidos, proxies ni un runtime `msedgewebview2.exe` compartido. No modificar autenticación/licencias/binarios del proveedor ni desactivar AVG/Defender. El modo sin conexión puede afectar validaciones legítimas.

### Principios de trabajo
1. **KISS:** simple, eficiente, optimizado, eficaz; no introducir servicios, drivers ni dependencias sin evidencia.
2. **Anti-ruido:** mejorar, optimizar, unir o eliminar código redundante; demostrar motivo, no acumular soluciones en paralelo.
3. **No parches:** localizar la causa y corregir el módulo de origen junto con los componentes afectados.
4. **UX clara:** progreso no bloqueante, estado exacto, controles confirmados y recuperación entendible; no mostrar PASS falso.
5. **Checkpoints y documentación:** README + SPEC + continuidad alineados; QA y CI antes de considerar fase completa.
6. **No ping-pong al usuario:** no pedir pruebas de módulos parciales en su PC; preparar una RC1 integral cuando realmente lo permita la evidencia.

## 2. Qué está implementado

| Etapa | Código / funcionalidad | Validación |
|---|---|---|
| F0 | Diagnóstico registro/instalaciones, procesos, servicios, firewall, tareas, conexiones e informes locales | CI Windows 5.1/7 y smoke sin AutoCAD |
| F1 | Descubrimiento de EXE AutoCAD 2023–2027, clasificación de componentes compartidos | Fixtures + smoke |
| F2 | Históricos PCAD/SGC/WebView2, panel WinForms y progreso por proceso separado | Parser + WinForms SelfTest; sin QA interactiva completa |
| F3 | Árbol WebView2 y conexiones observables (atribución PROBABLE/INDETERMINADA) | Fixtures; no atribución absoluta ni aislamiento |
| F4 | Planificador Outbound por EXE de producto, identificador estable, Apply/rollback explícitos y journal | Mocks e integración con firewall real **únicamente en Windows efímero** |
| F5 | Rutas personalizadas privadas, reportes saneados, evaluación de journal aplicado/incompleto/corrupto | CI y fixtures |
| F6 | Fallback por DisplayIcon verificando acad.exe; recuperación de journal CREATING con regla temporal real; ZIP DEV determinista con SHA256 | **CI #49 4/4 PASS** |
| F7 | Fail-closed cuando existen operaciones y archivos de recuperación pendientes; GUI/CLI no aplican nuevas reglas | CI #63 PASS |
| F8 | Estado único para informes/UI, diez etapas verificadas, salida de proceso coherente y errores de lectura sin falso éxito | **CI #73 4/4 PASS** |

**CI #63:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39538578854 — PowerShell 5.1, PowerShell 7, integración real sobre regla temporal y construcción/extracción/verificación de ZIP. Se corrigió un fallo de manejo de campos ausentes en WinForms antes de PASS; F6 resolvió el parser DisplayIcon.

## 3. Arquitectura vigente y reconstrucción desde GitHub

- `src/ParcheCAD.Core.ps1`: instalaciones, servicios, procesos, firewall, tareas y conexiones (solo lectura).
- `src/ParcheCAD.Catalogo.ps1`: descubrimiento por versión, controles de recorrido y clasificación.
- `src/ParcheCAD.Historico.ps1`: familia de reglas antiguas y estados de recuperación (no elimina reglas ajenas).
- `src/ParcheCAD.Network.ps1`: observación de WebView2 por host probable.
- `src/ParcheCAD.Policy.ps1`: plan/ID de reglas, verificación de identidad, EXE admitido.
- `src/ParcheCAD.Firewall.ps1`: aplicación y rollback explícitos, journal privado. Sin servicio residente.
- `src/ParcheCAD.Evidence.ps1`: copias saneadas para informes públicos.
- `src/ParcheCAD.Diagnostico.ps1`: orquestación de diez etapas, JSON/TXT.
- `src/ParcheCAD.Reglas.ps1`: CLI Preview / Apply / Rollback, confirmación escrita.
- `src/ParcheCAD.Panel.ps1`: panel WinForms, proceso hijo y autorización UAC.
- `Abrir_ParcheCAD.cmd`: lanzador Windows del panel.
- `tools/Build-ParcheCAD.ps1`: ZIP DEV con allowlist, hashes por archivo y checksum del ZIP.
- `tests/F0.Tests.ps1`, `F1F2.Tests.ps1`, `F3F4.Tests.ps1`, `F5.Tests.ps1`, `F4.RealFirewall.Integration.ps1`, `F6.Package.Tests.ps1`: suites locales/CI.
- `.github/workflows/f0-static-qa.yml`: cuatro jobs Windows, incluye artifact DEV retenido temporalmente.

**Reconstrucción:** clonar la rama actual, leer README/SPEC/F6 y ejecutar el workflow de GitHub Actions; el artifact `ParcheCAD_4.0_DEV_NOT_RELEASE` se produce de la fuente del repositorio, no de copias locales antiguas. ZIP actual: `ParcheCAD_4.0_DEV_NO_RELEASE.zip`. El pipeline valida reproducibilidad de dos builds, manifiesto SHA256, extracción, CLI Preview y arranque de WinForms SelfTest. **No instalar/usar Apply en PC principal por ahora.**

Historial de auditoría: `docs/F0_GUIA_USO_Y_QA.md`, `F1F2_IMPLEMENTACION_QA.md`, `F3F4_IMPLEMENTACION_QA.md`, `F4_INTERFAZ_QA_REAL.md`, `F5_INTEGRACION_RECUPERACION_QA.md`, `F6_PAQUETE_PRE_RC.md`. Documentos `docs/SPEC_MAESTRA.md` y `README.md` actualizados.

## 4. Evidencia y límites de QA

**PASS demostrado:** sintaxis/tests PS5.1 y 7; diagnosticador Windows sin AutoCAD; inicio no interactivo de WinForms (no prueba de clics en escritorio); regla de EXE ficticio creada, identificada, repetida sin duplicarse y retirada en Windows temporal; recuperación de una regla real con journal marcado CREATING después de interrupción **simulada**; ZIP repetible y verificado por hash.

**PENDIENTE / no generalizar:**
- No se probó en un Windows con AutoCAD real 2023, 2024, 2025, 2026 o 2027 instalado.
- No hay QA gráfica completa de botones/UAC aceptada y denegada, cancelación, cierre durante proceso administrativo, pantallas con DPI variable ni AVG del usuario.
- No hay interrupción física real/reinicio entre escritura y rollback (solo simulación controlada), ni verificación del comportamiento persistente en el equipo objetivo.
- No existe prueba de bloqueo de **todo** el tráfico Autodesk, IPv4/IPv6 TCP/UDP ni de servicios compartidos de Autodesk. Las reglas por EXE pueden bloquear también tráfico LAN.
- **WebView2 exclusivo de AutoCAD: NO RESUELTO.** El runtime Microsoft compartido está intencionalmente excluido para no afectar otras aplicaciones.
- Los reportes están sanitizados, pero los manifests de operaciones contienen rutas completas y permanecen locales bajo `informes/`, excluidos de Git.

## 5. Política GitHub y entrega

PRs apilados #3–#10 **Draft**, sin merge, deploy ni Release. CI verde **no** implica aplicación final aprobada. Todos los cambios de lógica viven en GitHub; no depender de carpetas temporales del asistente ni del PC del usuario. No incluir logs privados en PR. Los ZIP de Actions son artefactos temporales de desarrollo.

## F7 — Checkpoint más reciente (PR #9 Draft)

- **Problema:** recuperación histórica reportaba incompletos, pero el diagnóstico aún podía quedar COMPLETO y permitir más bloqueos.
- **Causa corregida en origen:** `Get-PCADRecoveryOverview` marca PARCIAL por `CREATING`, `ROLLBACK_ERROR`, JSON ilegible, archivo `.pending` o `.prev` huérfano. No elimina datos ni reglas ajenas.
- **Diagnóstico:** etapa Histórico propagada como PARCIAL; reporte no anuncia éxito completo.
- **CLI Apply:** `Assert-PCADRecoveryReady` antes y después de pedir confirmación. **Rollback no queda bloqueado**, ya que es el mecanismo de solución.
- **GUI:** exige 10/10 comprobaciones OK, histórico verificable y plan sin conflictos; informe sin campos deshabilita el botón sin colapsar WinForms.
- **Pruebas:** suites F0–F5 + F7, WinForms SelfTest, **diagnóstico Windows real con journal `.pending` que exige salida PARCIAL**, integración de regla temporal y empaquetado reproducible. **CI #63 (4/4 PASS):** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39538100660.
- Evidencia: `docs/F7_FAILCLOSED_GUI_QA.md`. Actualizar la cifra CI si algún cambio posterior activa un nuevo run.
- **PENDIENTE:** QA visual interactiva con UAC, reinstalación/reinicio, AutoCAD real 2023–2027, cobertura Autodesk compartido, aislamiento WebView2 exclusivo. Sin certificación de bloqueo total.

## F8 — Último checkpoint (PR #10 Draft)

- **Origen del defecto:** el panel usaba el código de salida para decir COMPLETO aun si el informe era parcial/insuficiente. Existían tres validaciones independientes de Aplicar, Vista previa y resultado.
- **Corrección integrada:** `src/ParcheCAD.UIState.ps1` define la validación única y pura; `ParcheCAD.Panel.ps1` la consume para texto de estado y botones. No servicios, drivers ni procesos residentes nuevos.
- **Invariantes:** ExitCode=0; Tool=ParcheCAD, esquema 1, ReadOnly=true; resultado completo; diez etapas identificadas y cada una OK; recuperación sana; vista previa PLAN_NO_APLICADO con candidatos y sin conflictos.
- **Fallo seguro:** JSON incompleto, secciones ausentes, duplicación de etapa, código no cero, proceso activo o journal pendiente: no se habilita Aplicar ni se muestra diagnóstico completo, incluso si el propio JSON declara otras etapas OK.
- **QA automática:** `tests/F8.UIState.Tests.ps1` en PS5.1/7; WinForms SelfTest; ZIP reproducible con módulo UIState incluido y ejecutable desde extracción; regla temporal Windows y rollback sin AutoCAD real. **CI #73 PASS 4/4:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39540161818
- **Nota sobre QA:** fallo de parser inicial al integrar expresiones de formato multilineales, resuelto simplificando la presentación en el origen y repitiendo CI; la interfaz aún no ha superado QA de clics reales.
- **Documentos:** `docs/F8_UISTATE_QA.md`, README y SPEC actualizados. Artifact GitHub DEV no es release.
- **BLOQUEOS:** QA escritorio interactivo/UAC, interrupción física/reinicio, AutoCAD instalado 2023–2027, medición de tráfico Autodesk compartido y objetivo WebView2 sin ejecución **NO RESUELTO**.

## NEXT único

**F9 — QA gráfica interactiva/decisión RC1:** validar clics, cambios de foco/DPI, UAC denegada/aceptada, cancelación y resultado administrativo sobre Windows descartable; aislar cualquier fallo en el módulo de origen y probar la recuperación tras reinicio cuando sea factible. Registrar con precisión la cobertura de Autodesk y WebView2. Mantener PRs #3–#10 Draft, sin merge ni release; no exigir pruebas fragmentadas al usuario.
