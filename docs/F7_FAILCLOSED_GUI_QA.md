# F7 — Puertas de recuperación y seguridad en la interfaz

**Proyecto:** ParcheCAD 4.0 · **PR:** #9 Draft, apilado sobre #8 · **Estado:** código y CI aprobados; **SIN RC1 y SIN release**.

## Problema real identificado

Hasta F6, `Get-PCADRecoveryOverview` podía informar respaldos incompletos pero el diagnóstico seguir marcando su etapa como `OK`. La interfaz y la consola ofrecían crear más reglas aunque un journal anterior estuviera en estado `CREATING` o no se pudiese leer. También podían existir archivos `.pending` o copias `.prev` huérfanas después de una escritura interrumpida. Estas condiciones **no autorizan nuevas modificaciones del firewall**.

## Cambios integrados (sin duplicar motores)

- `src/ParcheCAD.Historico.ps1`: clasifica como `PARCIAL` journals `CREATING`, `ROLLBACK_ERROR`, corruptos, archivos `PCAD4_*.json.pending` y `.prev` cuyo JSON principal falta. `Assert-PCADRecoveryReady` rechaza el estado para operaciones nuevas. Archivos `.prev` normales, con JSON principal presente, no generan falsos positivos.
- `src/ParcheCAD.Diagnostico.ps1`: la etapa `Historico` pasa a `PARCIAL` cuando la recuperación no es verificable; el reporte general deja de presentar `DIAGNOSTICO_COMPLETADO_SIN_CAMBIOS`.
- `src/ParcheCAD.Reglas.ps1`: `Apply` consulta la recuperación antes de pedir confirmación y otra vez inmediatamente antes de aplicar. `Preview` sigue siendo de solo lectura; `Rollback` sigue disponible para resolver el problema.
- `src/ParcheCAD.Panel.ps1`: `Aplicar` requiere informe completo, **10/10 etapas OK**, plan sin conflictos y recuperación sana. Si faltan secciones del informe, se deshabilita sin lanzar excepciones bajo `Set-StrictMode`.
- `tests/F7.Tests.ps1`: estados limpio, `CREATING`, corrupto, `.pending`, `.prev` huérfano y normalización posterior. Test F5 actualizado para exigir `PARCIAL` en un journal interrumpido.
- La autoevaluación WinForms cubre ausencia de campos, reporte parcial, recuperación pendiente, estado sano y consulta en ejecución.

## Evidencia verificada

**GitHub Actions CI #56: 4/4 PASS** — https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39538100660

| Trabajo | Evidencia |
|---|---|
| Windows PowerShell 5.1 | Suites F0–F5/F7; panel WinForms SelfTest; diagnóstico y vista previa |
| PowerShell 7 | Suites F0–F5/F7 |
| Firewall real temporal | Creación, repetición sin duplicados y recuperación de regla temporal en GitHub-hosted Windows |
| ZIP DEV | Dos builds deterministas, hashes y CLI/WinForms SelfTest ejecutados desde extracción |

**No hubo conexión a la PC del usuario; no se aplicaron bloqueos a Autodesk, WebView2, AVG ni licencias.**

## Limitaciones pendientes para RC1

- Esta QA **no es automatización de clics con escritorio interactivo**, no confirma UAC aceptada/denegada ni DPI/UX visual. El SelfTest valida construcción del formulario y lógica de habilitación, no renderizado completo.
- No existe ensayo con instalaciones reales de AutoCAD 2023–2027 ni medición de tráfico TCP/UDP o componentes Autodesk compartidos.
- La recuperación de interrupciones se ensayó con journal `CREATING` y firewall real, pero no con apagado brusco o reinicio Windows mientras se escribía el manifest.
- El WebView2 compartido continúa excluido. Impedir que AutoCAD lo ejecute y aislar únicamente su tráfico siguen sin demostrarse. No presentar bloqueo «total» de Autodesk.
- Si existe un `.pending` o `.prev` huérfano, el programa exige revisión; **no lo elimina ni repara automáticamente** porque hacerlo sin verificar el firewall podría perder información de recuperación.
- Los journals contienen rutas privadas, son locales y no deben publicarse en GitHub.

## NEXT

**F8 — QA interactiva y RC gate:** pruebas del panel con clics y UAC en escritorio Windows aislado, cierre/reinicio y errores de consulta, revisión de cobertura real de AutoCAD y WebView2. Mantener PR #3–#9 Draft; no merge, deploy ni release antes de superar puertas reales. Reservar pruebas de usuario para candidata integrada.
