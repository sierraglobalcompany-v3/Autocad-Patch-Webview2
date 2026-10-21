# SPEC MAESTRA — ParcheCAD 4.0
**Estado:** F0 pendiente · **Repositorio:** sierraglobalcompany-v3/Autocad-Patch-Webview2 · **Fecha:** 2026-10-20

## Objetivo y definiciones de éxito
Inventariar AutoCAD 2023–2027, sus ejecutables y servicios, procesos WebView2, reglas de firewall y conexiones. Evaluar aislamiento de conexiones de Autodesk, aceptando pérdida de funciones en línea, sin afectar WebView2 de WhatsApp/Outlook.

**R1: Bloqueo de conexiones salientes** = reglas efectivas + pruebas de conectividad, no solo conteo de reglas.
**R2: No usar WebView2** = AutoCAD no crea instancias WebView2; un firewall no cumple esta condición.
**R3: Aislamiento** = no modificar o bloquear globalmente msedgewebview2.exe compartido.
**R4: Cobertura honesta** = registrar componentes no atribuidos y mostrar PARCIAL/NO VERIFICADO si aplica.

## Hallazgos técnicos
- Reglas Windows por ruta de EXE permiten distinguir acad.exe de carpetas 2023–2027 pero no cubren tráfico de WebView2 compartido ni tráfico proxificado.
- Los procesos msedgewebview2.exe pueden ser de varios anfitriones; PID padre solo no basta. Correlacionar árbol, instante de creación, línea de comandos y carpeta de datos.
- WebView2Loader.dll es DLL y .WebView2/.../EBwebView es carpeta de datos: ninguno es objetivo de regla de aplicación.
- Licenciamiento y autenticación de Autodesk pueden requerir internet; si se bloquean, la aplicación puede fallar.
- Históricos 3.x: exploración recursiva demasiado amplia, bloqueo global WebView2 afectó apps ajenas, UI se congelaba y antivirus advirtió. No reutilizar sin revisión.

## F0: diagnóstico únicamente de lectura
- Descubrir 0–5 versiones: registro de desinstalación + rutas reales + firma/metadatos de acad.exe.
- Inventariar EXE de producto, ejecutables Autodesk compartidos y procesos reales. Clasificar EXCLUSIVO, AUTODESK_COMPARTIDO, WEBVIEW2_COMPARTIDO, DESCONOCIDO.
- Consultar WebView2 por PID, parent PID, fecha de arranque, línea de comandos y datos de usuario disponibles; documentar atribución CONFIRMADA/PROBABLE/INDETERMINADA.
- Consultar reglas de firewall y filtros de aplicación, almacenes cuando sean accesibles, tareas antiguas, servicios y conexiones TCP/UDP disponibles.
- Salidas: TXT para humanos + JSON para QA, con anonimización de nombres, tokens, IP y rutas personales.
- No requiere admin cuando la información esté disponible sin elevar; explicitar campos no accesibles. Sin escribir firewall, registro, tareas ni servicios.

## Arquitectura KISS propuesta
```
README.md
docs/SPEC_MAESTRA.md
Abrir_ParcheCAD.cmd
ParcheCAD.ps1
ParcheCAD.Core.ps1
tests/
.gitignore
```
Sin servicio residente, driver kernel, tareas automáticas, base de datos, dependencias externas obligatorias, descarga dinámica de scripts ni ofuscación. Ninguna elevación silenciosa.

## UX para fases posteriores
Pantalla inicial con estado AUTO-CAD / WebView2 compartido / reglas y tareas heredadas. Barra de progreso X/Y, etapa y tiempo; no bloquear el hilo gráfico; cierre con verificación posterior y estado COMPLETO/PARCIAL/ERROR/NO VERIFICADO. Reinicio ofrecido solamente si hay razón, nunca forzado. Recuperación y rollback de reglas PROPIAS idempotentes; reglas ajenas requieren confirmación.

## Fases y puertas
F0 diagnóstico -> F1 clasificación/conexiones -> F2 UI y recuperación -> F3 pruebas de aislamiento -> F4 controles reversibles -> F5 QA Windows. Un NEXT activo. No declarar PASS sin evidencia en Windows.

## Seguridad
Nunca deshabilitar AVG/Defender, añadir exclusiones, evadir alertas, eliminar licencias o modificar binarios del proveedor. Si AV detecta: detener, conservar la alerta y auditar. No subir logs identificables al repositorio público. Para cualquier control de firewall: vista previa, confirmación, backup, verificación y reversión.

## Fuentes primarias
- https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/rules
- https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/process-model
- https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/user-data-folder
- https://learn.microsoft.com/en-us/sysinternals/downloads/tcpview
- https://www.autodesk.com/support/technical/article/caas/sfdcarticles/sfdcarticles/Several-Microsoft-Edge-WebView2-instances-interfere-with-AutoCAD-applications.html

**NEXT: issue #1 — F0 diagnóstico 2023–2027, sin modificaciones de sistema.**
