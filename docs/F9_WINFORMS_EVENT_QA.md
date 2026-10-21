# F9 — Pruebas de eventos WinForms y protocolo de finalización

**Estado:** F9 con QA automatizada **PASS**. PR #11 Draft; sin merge, RC1 ni Release.  
**Evidencia:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39542376065 (CI #84, 4/4 PASS).

## Qué se ejecutó y verificó

- Windows PowerShell 5.1 en GitHub-hosted Windows, bajo STA, construyó el mismo formulario WinForms que usa el usuario y despachó sus **eventos de botón** sin abrir una ventana interactiva (el runner no garantiza acceso a un escritorio gráfico real).
- **Analizar:** se despachó el evento de botón, se abrió un PowerShell hijo que ejecutó las 10 etapas reales de diagnóstico de solo lectura, se cargó el JSON exportado y se comparó el resultado mostrado con la validación F8. Resultado **COMPLETO** en runner limpio.
- **Cancelar:** se despachó el evento contra un proceso hijo ficticio `Start-Sleep` sin privilegios administrativos. Se comprobó su terminación y la restitución de los controles.
- **Salir/cierre:** se invocó el evento FormClosing con un proceso administrativo **simulado** (sin UAC). Se comprobó que el cierre quedaba bloqueado durante ese proceso y liberado tras su finalización.
- Su test tuvo limpieza `finally` de todos los procesos hijos y carpetas de informes de prueba; no modificó Firewall, antivirus, licencias ni WebView2.
- Sigue vigente PASS en PS7, suites F0–F8, prueba de reglas temporales reales y ZIP DEV reproducible.

## Defectos reales encontrados y corregidos

1. **Colisión de variable `preview`:** el informe creaba una variable local con el mismo nombre que el botón WinForms. Debido a la resolución dinámica de ámbitos de PowerShell, `PCAD-Busy` podía recibir una lista sin propiedad `Enabled`. Los controles se referencian explícitamente como `$script:...` y la lista se renombró `$planRows`.
2. **Resultado del hijo no siempre accesible:** en el runner Windows, `Start-Process -PassThru` devolvía un proceso terminado pero sin `ExitCode` legible. No se relajó la puerta F8: el diagnóstico escribe un archivo `diagnostico.exitcode` (`0` o `2`) solo tras exportar el informe, **únicamente si el panel lo solicita**, en el directorio único de esa ejecución. Un marcador ausente, inválido o contradictorio implica `PARCIAL`.
3. **QA dependiente del escritorio:** intentar mostrar el formulario en el runner no interactivo causó timeout. Se pasó a despachar los mismos eventos WinForms sin ventana visible, manteniendo la limitación documentada. Se restauró la llamada `PCAD-Finish` al depurar el test y se volvió a ejecutar CI.

## Qué sigue SIN certificar

- **No es una prueba visual ni una interacción mediante mouse/teclado en escritorio real**; no se revisaron DPI, foco, legibilidad, escalado o accesibilidad.
- **No se aprobó/denegó UAC real**; el proceso elevado fue simulado y no ejecutó un modo `Apply` ni `Rollback` de producción.
- No se probó un reinicio Windows real interrumpiendo escritura de journal o reglas.
- No se instaló ni ejecutó AutoCAD 2023–2027, ni se midió tráfico Autodesk de todos los componentes/servicios compartidos.
- `msedgewebview2.exe` compartido continúa excluido. No está implementada una garantía de que AutoCAD no ejecute WebView2 ni de que sus conexiones estén bloqueadas exclusivamente.

## NEXT único

**F10 / puertas RC1:** validar UAC e interacción visual en VM de escritorio Windows aislada; confirmar en instalaciones AutoCAD reales inventario/cobertura de red, bloquear solo componentes atribuibles sin romper WhatsApp/Outlook; probar reinicio/reversión; cuando exista evidencia, emitir RC1 integral con una sola prueba de aceptación del usuario. Mantener PRs #3–#11 Draft, `main` intacta.
