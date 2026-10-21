# PROJECT_CONTINUITY_CURRENT — ParcheCAD 4.0

**Actualizado:** 2026-10-21. **Estado:** F0–F12 desarrolladas en PRs Draft; **SIN RC1 / RELEASE / DEPLOY / MERGE**.  
**Repositorio fuente única:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2  
**Rama vigente:** `feat/f12-integrated-qa-gates` · **PR #14 Draft**, apilado sobre #13→#12→#11→#10→#9→#8→#7→#6→#5→#4→#3. **`main` aún no tiene estas fases.**  
**CI F12 inicial verificado:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39546699351 — run **#100, 4/4 PASS**. Verificar CI sobre último HEAD tras commits de docs.

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

## Implementación probada hasta F12

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
| **F12** | **Evaluación de diez puertas RC1 desde diagnósticos antes/después** | **CI #100 4/4 PASS inicial; nunca RC1 automático** |

### F12 — trabajo recién realizado

- `src/ParcheCAD.RCGates.ps1`: compara dos diagnósticos sanitizados existentes y valida esquema, diez etapas, recuperación, matriz F11 y coherencia de conteos de reglas. No accede a firewall, no observa red nueva ni ejecuta AutoCAD.
- `tools/Invoke-ParcheCADRC12.ps1`: lee `-Before` y `-After`, produce `RC12_EVALUACION.json` y `RC12_RESUMEN.txt` (sin rutas/IP privadas). Código de salida 0 indica **evaluación completada**, NO aprobación de RC1.
- Diez puertas: DIAGNOSTICOS, AUTOCAD_INSTALADO, REGLAS_SALIENTES, TRAFICO_AUTODESK, WEBVIEW2_AUTOCAD, OTRAS_APLICACIONES, GUI_UAC, REINICIO_Y_ROLLBACK, AVG_ACTIVO, AUTOCAD_FUNCIONAL.
- Solo el formato de los dos diagnósticos puede obtener `PASS`; instalar acad.exe puede quedar `OBSERVADO`; reglas `CONFIGURACION_OBSERVADA`. **`Decision=BLOCKED`, `ProductionCertified=false`** en tanto no exista evidencia real de todas las puertas. No hay botón de autoaprobación.
- `tests/F12.RCGates.Tests.ps1` prueba escenarios vacíos, JSON contradictorios y recuperación pendiente PS5.1/7.
- `tests/F12.RealWindows.Integration.ps1` usa un diagnóstico Windows GitHub-hosted real (duplicado antes/después **solo para smoke**) y exige `Decision=BLOCKED`; no toca firewall.
- Evidencia y plan de sesión única: `docs/F12_GATE_RC1_QA_INTEGRADA.md`. ZIP DEV incluye evaluador, CLI y guía; `tools/Build-ParcheCAD.ps1` determinista, `.github/workflows/f0-static-qa.yml` con cuatro jobs Windows.
- README y SPEC armonizados; PR #14 Draft sobre ramas anteriores.

## Reconstrucción desde GitHub

Clonar exactamente la **rama F12**, leer `PROJECT_CONTINUITY_CURRENT.md` + `docs/SPEC_MAESTRA.md` + `docs/F12_GATE_RC1_QA_INTEGRADA.md`, ejecutar GitHub Actions y revisar 4/4 jobs. El artifact temporal `ParcheCAD_4.0_DEV_NOT_RELEASE` contiene ZIP allowlist y SHA256; **NO es instalador RC1 ni está listo para Apply en PC principal**. Ningún JSON local antiguo es necesario para reconstruir el software.

## Qué bloquea RC1

1. AutoCAD verdadero 2023–2027 no ha sido probado en una VM con producto auténtico y software autorizado.
2. No hay mediciones sostenidas de egress IPv4/IPv6 TCP/UDP ni cobertura confirmada de proxies/servicios Autodesk compartidos.
3. **WebView2 exclusivo de AutoCAD: NO RESUELTO.** Una regla WebView2 global es inaceptable porque afectaría otras aplicaciones.
4. UAC real aceptada/denegada, botones visuales, DPI, foco y AVG habilitado no han sido verificados en escritorio auténticamente interactivo.
5. Reinicio físico del sistema durante modificación y recuperación posterior no ensayados (reabrir PowerShell sí).
6. ZIP DEV probado en Windows GitHub-hosted, pero no existe release ni soporte de implementación certificado.

## NEXT único

**F13 / preparación de aceptación real:** cerrar cualquier defecto de la evaluación F12 y preparar un único entorno de QA Windows interactivo con AutoCAD autorizado, snapshot de restauración, AVG activo, registro de conexiones, prueba UAC y rollback/reinicio. Solo entonces evaluar la evidencia de las diez puertas; si WebView2 sigue sin solución exclusiva, mantener ese objetivo como BLOCKED y plantear una decisión de alcance explícita, **sin declarar éxito falso**. No pedir tests por módulos al usuario, no merge ni Release hasta decisión basada en evidencias.
