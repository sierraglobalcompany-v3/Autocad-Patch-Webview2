# PROJECT_CONTINUITY_CURRENT — ParcheCAD 4.0

**Fecha:** 2026-10-20/21  | **Repositorio único:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2

## Scope y metodología
Control/diagnóstico de conectividad AutoCAD 2023–2027 y estudio de WebView2 compartido. Reglas KISS / anti-ruido, sin runtime sin docs, checkpoints, PR Draft, QA real obligatorio. No tocar otros proyectos ni crear servicios/drivers sin evidencia.

## Estado comprobado
- **F0 implementación:** código en rama `feat/f0-diagnostico-solo-lectura`, PR #3 Draft, sin merge.
- **F0 static QA:** PASS en Windows PowerShell 5.1 y PowerShell 7. Workflow `F0 static QA` ejecución #3, SHA `3d86242f88028c8e8d36ce469f18550d0ee5b64a`.
- **F0 smoke QA:** PASS en Windows Server 2022 de GitHub-hosted runner sin AutoCAD: seis secciones completadas, cero modificaciones, código de salida 0. Resultado: 0 instalaciones, 0 procesos, 0 servicios, 1 regla de firewall coincidente, 0 tareas, 0 conexiones seleccionadas.
- **F0 QA en PC con AutoCAD instalado:** **BLOCKED / PENDIENTE**. No afirmar que la detección 2023–2027 está certificada antes de esa prueba.
- **F1 clasificación/bloqueos:** NO COMENZADO. No bloquear WebView2 globalmente ni afirmar aislamiento.

## Código y evidencias
- `src/ParcheCAD.Core.ps1`: descubrimiento de instalaciones, procesos WebView2, servicios, filtros firewall, tareas y conexiones. Consultas de solo lectura.
- `src/ParcheCAD.Diagnostico.ps1`: orquestación, barra de progreso en consola, errores no confundidos con cero resultados, exportación local TXT/JSON.
- `Abrir_ParcheCAD.cmd`: lanzador sin elevar automáticamente.
- `tests/F0.Tests.ps1`: parser y pruebas puras sin dependencias de terceros.
- `.github/workflows/f0-static-qa.yml`: PS5.1, PS7 y smoke Windows sin AutoCAD.
- `docs/F0_GUIA_USO_Y_QA.md`: instrucciones y pruebas manuales.

## Riesgos y límites
- Firewalls basados en la ruta de `acad.exe` **NO** aíslan automáticamente conexiones de `msedgewebview2.exe` compartido.
- Atribución de WebView2 por PID padre/UDF = PROBABLE, no conclusión absoluta.
- Resultado de una consulta de firewall no equivale a bloqueo efectivo. F0 no modifica licencias, servicios, tareas, reglas ni registro.
- El diagnóstico es una instantánea que puede omitir conexiones efímeras. Comprobar resultados reales al abrir AutoCAD y durante distintas funciones.
- Informes locales bajo `informes/` están gitignorados. Antes de adjuntarlos o publicarlos, revisar privacidad.
- No desactivar AVG/Defender ni agregar exclusiones para ejecutar.

## PREVIOUS
Rama de solo documentación PR #2 Draft: 10 pasadas y plan F0–F6, sin merge. Scripts legacy V2/3.x únicamente referencia auditada, no publicados como release nuevo. Capturas V3.0: 96 reglas AutoCAD retiradas, 2 WebView2 remanentes, una tarea heredada; esto no es inventario exhaustivo de los 96 EXE.

## NEXT — único y accionable
**F0-WIN-QA:** validar PR #3 en un PC Windows con AutoCAD 2023 y/o 2027 realmente instalado, sin desactivar antivirus, capturando las seis secciones. Corregir cualquier ERROR, falsos positivos o rutas omitidas, y dejar un informe sanitizado con PASS/PARTIAL/BLOCKED. No fusionar ni comenzar F1 si F0-WIN-QA no está certificado para el entorno objetivo.
