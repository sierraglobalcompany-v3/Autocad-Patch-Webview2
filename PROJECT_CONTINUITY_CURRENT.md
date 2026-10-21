# PROJECT_CONTINUITY_CURRENT — ParcheCAD 4.0

**Actualización:** 2026-10-21 · **Estado:** F0–F10 implementadas en ramas apiladas; **SIN RC1 / RELEASE / DEPLOY**.  
**Repositorio fuente de verdad:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2  
**Rama actual:** `feat/f10-process-lifecycle-recovery` · **PR #12 Draft** sobre #11 → #10 → #9 → #8 → #7 → #6 → #5 → #4 → #3. **Main SIN merge**.  
**Último QA del código F10:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39543990081 — **CI #90, PASS 4/4**. Un commit nuevo de documentación/ZIP exige nuevo CI para constituir el último HEAD verde.

## Requisitos innegociables

**Objetivo del usuario:** AutoCAD 2023, 2024, 2025, 2026, 2027 y Autodesk sin conexiones a internet; además desea que AutoCAD **no ejecute WebView2**. Tolera pérdida de funciones online. Pero **no** acepta impedir WebView2 de WhatsApp, Outlook u otras aplicaciones.

**Estado de cobertura HONESTO:** el motor actual bloquea, previa confirmación, **EXE clasificados como AUTOCAD_PRODUCTO** por ruta saliente. No hay prueba de bloqueo de **todo Autodesk**: quedan servicios/EXE compartidos, tráfico por procesos auxiliares y WebView2. Impedir que AutoCAD cree WebView2 no se ha demostrado ni implementado. **NO declarar éxito total ni RC1**.

**Leyes del proyecto:**
1. **KISS:** simple, eficiente, optimizado, eficaz; sin driver, servicio residente, instaladores de terceros ni arquitectura compleja sin evidencia.
2. **Anti-ruido:** eliminar/unir/mejorar duplicaciones en el origen, con justificación.
3. **No parches:** corregir causa y componentes afectados, no soluciones aisladas superpuestas.
4. **Diseño/UX:** estado real, controles claros, progreso, cancelación, respaldo y reversión; nunca mostrar COMPLETO sin pruebas.
5. GitHub contiene fuente, QA, README/SPEC y checkpoint; Codex solo al final y cuando resulte indispensable, sin ping-pong.
6. Una sola prueba final integrada al usuario; no solicitarle pruebas incompletas por fase.

**Seguridad:** no bloquear globalmente `msedgewebview2.exe`; no desactivar AVG ni Defender; no modificar licencias, binarios Autodesk, reglas ajenas ni servicios sin comprobación de impacto. Operaciones administrativas explícitas con journal local y rollback. La desconexión puede inutilizar funciones/licenciamiento en línea.

## Estado por fases y evidencia

| Fase | Implementado | QA |
|---|---|---|
| F0–F2 | Inventario AutoCAD, procesos WebView2, servicios, firewall y tareas; WinForms inicial | PS5.1/PS7, inventario read-only |
| F3 | Observación de conexiones y atribución probable WebView2 | Fixtures; **no aislamiento probado** |
| F4 | Plan de reglas salientes por EXE exclusivo; Apply/rollback/journal | Windows temporal, regla ficticia real |
| F5 | Instalaciones personalizadas, rutas internas y reportes saneados, estados de recuperación | Fixtures y CI |
| F6 | Fallback DisplayIcon verificado, ZIP reproducible SHA256 y rollback tras CREATING | Windows efímero |
| F7 | Apply fail-closed ante journals corruptos, incompletos, .pending/.prev huérfanos | CI y diagnóstico parcial real |
| F8 | Fuente única para validar diez etapas, exitcode, plan/recuperación y habilitación de GUI | Fixtures y WinForms SelfTest |
| F9 | Eventos Analizar/Cancelar/FormClosing, colisión de controles reparada, marcador de salida del hijo | CI #89 PASS 4/4 |
| **F10** | Cancelación/cierre **verificados por PID propio** y rollback de regla ficticia CREATING desde **nuevo PowerShell** | **CI #90 PASS 4/4** |

### F10 — último avance

- `src/ParcheCAD.Panel.ps1` usa `PCAD-StopOwnedDiagnostic` para Cancelar/Cerrar: `Kill()` solo al hijo de lectura, `WaitForExit(5000)`, no reportar cancelado ni cerrar si no finaliza; los procesos administrativos y terceros no son detenidos.
- El test F9/F10 en STA usa eventos del **formulario real sin mostrar ventana** y verifica que Cancelar/Cerrar eliminen el PID propio mientras otro PowerShell ajeno permanece vivo.
- `tests/F10.Recover.Child.ps1` recibe un journal de regla de prueba `CREATING`, se inicia como **proceso nuevo**, vuelve a importar Core/Policy/Firewall, inspecciona identidad, revierte y verifica inexistencia de la regla.
- `tests/F4.RealFirewall.Integration.ps1` crea únicamente reglas sobre EXE sintético en TEMP bajo Windows **GitHub-hosted**, invoca dicho proceso nuevo, comprueba el journal y limpia con `finally`. **No representa reiniciar Windows**.
- Evidencia detallada: `docs/F10_PROCESOS_RECUPERACION_QA.md`.

### Mapa de código para reconstrucción

- `src/ParcheCAD.Core.ps1`: lectura de registro, instalaciones, procesos/servicios, firewall y tareas.
- `src/ParcheCAD.Catalogo.ps1`, `ParcheCAD.Network.ps1`, `ParcheCAD.Historico.ps1`: clasificación, atribución observacional WebView2 y journals antiguos/recuperación.
- `src/ParcheCAD.Policy.ps1`, `ParcheCAD.Firewall.ps1`: política por EXE, reglas PCAD4, rollback y registros privados.
- `src/ParcheCAD.Diagnostico.ps1`, `ParcheCAD.Evidence.ps1`, `ParcheCAD.UIState.ps1`: diez etapas, informe saneado y estado seguro.
- `src/ParcheCAD.Panel.ps1`, `ParcheCAD.Reglas.ps1`: interfaz Windows, CLI de Preview/Apply/Rollback con confirmación.
- `Abrir_ParcheCAD.cmd`: lanzador; `tools/Build-ParcheCAD.ps1`: ZIP DEV con whitelist + SHA256.
- `tests/` y `.github/workflows/f0-static-qa.yml`: pruebas PS5.1/7, WinForms, firewall efímero, ZIP.
- `README.md`, `docs/SPEC_MAESTRA.md` y `docs/F0_...F10_....md`: instrucciones, decisiones y detalle de QA. Los estados antiguos viven en los reportes de cada fase, no en este archivo.

**Reconstitución:** clonar **esta rama** en un PC o chat nuevo, leer este archivo y `docs/SPEC_MAESTRA.md`, ejecutar el workflow. GitHub Actions produce `ParcheCAD_4.0_DEV_NOT_RELEASE.zip` con hash SHA256 como artifact temporal; NO usar Apply en PC principal hasta completar RC1.

## Bloqueos estrictos de RC1

1. **Cobertura real Autodesk:** falta identificar y atribuir conexiones TCP/UDP IPv4/IPv6 originadas por servicios y componentes Autodesk compartidos. Una regla por `acad.exe` no cubre todo.
2. **WebView2 AutoCAD:** aún **no se ha probado** impedir su uso o aislarlo sin afectar otras apps. Bloqueo global Microsoft prohibido.
3. **QA escritorio:** GitHub-hosted no dio escritorio interactivo fiable para Form.Show(); eventos STA PASS **no certifican** DPI, clics reales, foco, accesibilidad, UAC aceptada/denegada o AVG.
4. **Reinicio Windows:** recuperación tras iniciar **otro PowerShell** PASS; corte de energía/reboot en mitad del journal **NO ENSAYADO**.
5. **AutoCAD instalado:** ninguna prueba con las versiones reales 2023–2027; fixture `acad.exe` no es Autodesk.
6. **Distribución:** no release ni merge, ZIP exclusivamente técnico/temporal.

## NEXT único

**F11 — matriz de cobertura:** implementar/instrumentar un reporte claro de qué EXE de producto y servicios Autodesk compartidos son candidatos o excluidos, qué tráfico se observa y por qué, sin falsos «totalmente bloqueado». Investigar las posibilidades de aislamiento de WebView2 exclusivamente para AutoCAD y documentar BLOCKED si no es verificable. Preparar luego QA visual/UAC/reinicio en VM Windows con escritorio **verdaderamente interactivo** antes de cualquier RC1. Mantener PRs #3–#12 Draft, `main` intacta y no pedir pruebas al usuario por módulos.
