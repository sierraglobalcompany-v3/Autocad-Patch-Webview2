# SPEC MAESTRA — ParcheCAD 4.0
**Estado:** F0–F6 en desarrollo con QA Windows y ZIP DEV reproducible, no RC ni release · **Repositorio:** sierraglobalcompany-v3/Autocad-Patch-Webview2 · **Fecha:** 2026-10-20

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


## F5 — reglas de integracion y privacidad (2026-10-21)

- La detección conserva rutas reales **solo en memoria y durante operaciones autorizadas**. Los informes JSON/TXT y la vista previa pública sanea rutas de perfiles de Windows.
- La ruta del EXE se contrasta contra la raíz de instalación real: no suponer que toda instalación está bajo `C:\Program Files\Autodesk\AutoCAD 20XX`.
- La política reversible guarda esa raíz en el journal privado. Una regla propia puede revertirse aun si el EXE desaparece, pero un identificador ajeno nunca autoriza eliminación automática.
- La revisión de manifests solo muestra **registros históricos**, no existencia ni eficacia comprobada de reglas. `CREATING`, `ROLLBACK_ERROR` y archivos inválidos deben marcar revisión pendiente.
- La GUI solo habilita acciones cuando el diagnóstico ha finalizado sin errores y el plan está sin conflictos. UAC y confirmación adicional por cada modificación.
- QA alcanzada: PowerShell 5.1/7, fixtures F0–F5, autoinicialización WinForms y reglas reales temporales en Windows efímero. No reemplaza prueba de AutoCAD instalado, QA visual interactiva ni validación WebView2.
- Documento de referencia y puertas: `docs/F5_INTEGRACION_RECUPERACION_QA.md`.

## F6 — recuperación real y empaquetado técnico (2026-10-21)

- Detectar instalaciones desde DisplayIcon si InstallLocation está ausente/incorrecta, solo con rutas locales explícitas hacia acad.exe que existan físicamente; jamás ejecutar datos del registro.
- Probar con Windows real **descartable** la reversión de una regla temporal válida cuyo journal quedó en CREATING tras una interrupción simulada en mitad de la operación.
- ZIP DEV contiene exclusivamente allowlist de fuentes/documentos, con timestamp normalizado y SHA256 por archivo y por ZIP. Verificar determinismo con dos compilaciones y ejecutar CLI Preview y GUI SelfTest desde paquete extraído.
- Guardar ZIP como GitHub Actions artifact temporal, sin usar GitHub Releases ni publicarlo como RC o certificado.
- No confundir interrupción simulada con apagado abrupto/reinicio ensayado. Tampoco equivale a test de AutoCAD real o de aislamiento WebView2.

**NEXT: integración final RC1 — QA gráfica interactiva, UAC/reinicio real, AutoCAD instalado y evidencia honesta de cobertura/WebView2. PRs Draft; no merge ni release.**
