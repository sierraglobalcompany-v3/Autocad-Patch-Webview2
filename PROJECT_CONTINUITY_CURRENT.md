# PROJECT_CONTINUITY_CURRENT — ParcheCAD 4.0

**Fecha:** 2026-10-20/21  | **Repositorio único:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2

## Scope y metodología
Control/diagnóstico de conectividad AutoCAD 2023–2027 y estudio de WebView2 compartido. Reglas KISS / anti-ruido, sin runtime sin docs, checkpoints, PR Draft, QA real obligatorio antes de release, sin pedir al usuario pruebas de cada fase. No tocar otros proyectos ni crear servicios/drivers sin evidencia.

## Estado comprobado
- **F0 implementación:** código en rama `feat/f0-diagnostico-solo-lectura`, PR #3 Draft, sin merge.
- **F0 static QA:** PASS en Windows PowerShell 5.1 y PowerShell 7. Workflow `F0 static QA` ejecución #3, SHA `3d86242f88028c8e8d36ce469f18550d0ee5b64a`.
- **F0 smoke QA:** PASS en Windows Server 2022 de GitHub-hosted runner sin AutoCAD: seis secciones completadas, cero modificaciones, código de salida 0. Resultado: 0 instalaciones, 0 procesos, 0 servicios, 1 regla de firewall coincidente, 0 tareas, 0 conexiones seleccionadas.
- **F0 QA en PC con AutoCAD instalado:** PENDIENTE de la validación final integrada; no bloquea desarrollo de F1/F2/F3/F4. No afirmar que detección 2023–2027 esté certificada.
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

## Decisión de flujo de trabajo (solicitada por el usuario)
- No pedir al usuario ejecutar pruebas fragmentadas con F0/F1/F2.
- Reutilizar/auditar la lógica que ya funcionó de ParcheCAD 3.0 y mejoras de 3.2 como base; no copiarlas sin revisión.
- Completar experiencia de usuario, motor de descubrimiento, estado y recuperación, reglas selectivas con preview e idempotencia, pruebas con mocks/CI y pruebas de integración seguras en Windows accesible.
- El QA real en PC con AutoCAD queda como **prueba de aceptación de una versión candidata integrada**, no como requisito para empezar F1.
- La 4.0 no se declara lista para producción hasta QA final; si el aislamiento exclusivo WebView2 no resulta técnicamente demostrable, debe quedar explícito y no bloquear globalmente por defecto.

## NEXT — único y accionable
**F1/F2 implementación sin dependencias del usuario:** integrar catálogo de descubrimiento de AutoCAD 2023–2027, clasificación de ejecutables y servicios, motor histórico de reglas, UI con progreso y reversión inspirada en V3.0/3.2. Mantener CI verde, todo en PRs Draft y main sin merge hasta revisión. Preparar una candidata funcional para QA de usuario **una vez**, al cierre de la aplicación integrada.
