# SPEC MAESTRA — ParcheCAD 4.0
**Estado:** F0–F14 en desarrollo con QA Windows y ZIP DEV reproducible, no RC ni release · **Repositorio:** sierraglobalcompany-v3/Autocad-Patch-Webview2 · **Fecha:** 2026-10-20

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

## F7 — recuperación bloqueante (2026-10-21)

- Un registro de recuperación incompleto, corrupto, `.pending` o respaldo `.prev` huérfano implica `PARCIAL`; el diagnóstico no se considera completo.
- Las rutas GUI y CLI niegan nuevas reglas cuando hay operaciones por revisar. CLI comprueba el estado antes y después de la confirmación administrativa; el rollback explícito sigue disponible.
- GUI valida las diez etapas, recuperación y conflictos; se deshabilita de forma segura ante campos ausentes, sin excepción.
- Pruebas PowerShell 5.1/7, WinForms SelfTest, firewall temporal y ZIP SHA256. Ver `docs/F7_FAILCLOSED_GUI_QA.md`.
- Esto no sustituye QA de UAC real, visual, reinicio, AutoCAD instalado ni aislamiento de WebView2.

## F8 — coherencia de informe e interfaz (2026-10-21)

- Una evaluación de interfaz y elegibilidad **solo lectura** (`src/ParcheCAD.UIState.ps1`) reemplaza duplicaciones de controles del panel.
- El proceso hijo debe devolver código 0 y un JSON `Tool=ParcheCAD`, `SchemaVersion=1`, `ReadOnly=true`, resultado completo, diez etapas distintas y OK.
- Historial sin recuperación sana, vista previa ausente/en conflicto, secciones parciales o contradicción entre código y JSON deshabilitan Aplicar.
- WinForms anuncia COMPLETO únicamente con evidencia completa; un dato faltante no provoca una excepción ni un falso éxito.
- QA Windows PS5.1/7, ZIP reconstruido, AutoCAD temporal ficticio, WinForms SelfTest y suites de reportes corruptos/contradictorios. **CI #73 PASS 4/4:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39540161818
- Aun no existe QA visual interactiva, UAC real, AutoCAD 2023–2027 instalado ni aislamiento exclusivo probado de WebView2. Ver `docs/F8_UISTATE_QA.md`.

## F9 — eventos WinForms y finalización fiable de proceso hijo

- `PCAD-Busy` referencia botones por ámbito explícito `$script:`; no debe confundir el botón de Vista previa con una colección temporal del informe.
- El diagnóstico ejecutado por el panel dispone de protocolo de finalización dentro del directorio de informe único: `diagnostico.exitcode` se escribe exclusivamente cuando se solicita `-WriteExitMarker` y se concluye la exportación. Si está ausente/inválido o difiere del resultado nativo conocido, declarar estado parcial. No rebajar invariantes F8.
- Prueba F9 con formulario WinForms STA en GitHub-hosted Windows: despacha eventos reales del control **sin abrir la ventana**, valida Analizar→proceso hijo→JSON, Cancelar proceso propio y FormClosing con proceso administrativo ficticio. No UAC real.
- Un runner GitHub Actions puede no disponer de escritorio interactivo; no confundir tests de eventos con auditoría visual/UAC. Evidencia CI #84 (4/4 PASS): https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39542376065
- Documento de evidencia: `docs/F9_WINFORMS_EVENT_QA.md`. El código del panel no aplica reglas al inicio y WebView2 compartido permanece excluido.

## F10 — procesos propios y recuperación independiente (2026-10-21)

- `Cancelar` y `FormClosing` deben detener exclusivamente el proceso hijo de diagnóstico, esperar hasta 5 segundos y comprobar su salida. Si falla, preservar estado y reportar ERROR, nunca fingir CANCELADO ni cerrar a ciegas.
- Los controles administrativos no son objeto de cancelación/terminación general, y procesos ajenos (incluyendo WebView2) quedan fuera.
- Un segundo PowerShell, lanzado desde cero, puede importar módulos y recuperar la regla temporal PCAD4 que otro proceso dejó con journal CREATING. **No equivale a reinicio del sistema operativo**.
- QA CI #90 PS5.1/7, WinForms STA por eventos, firewall temporal, recuperación de nuevo proceso, integridad de ZIP. https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39543990081
- Evidencia y límites: `docs/F10_PROCESOS_RECUPERACION_QA.md`. No se ha verificado aislamiento exclusivo WebView2 ni tráfico total Autodesk.

## F11 — matriz de cobertura independiente de las reglas

- `Get-PCADCoverageReport` toma datos YA INVENTARIADOS (catálogo, servicios, procesos, conexiones, plan saliente y resumen WebView2), sin crear un segundo escáner ni descargar datos.
- `Sections.Coverage` agrega seis categorías explícitas: AUTOCAD_PRODUCTO, AUTODESK_COMPARTIDO, WEBVIEW2_COMPARTIDO, DESCONOCIDO, SERVICIOS_AUTODESK y PROCESOS_OBSERVADOS. Los nombres visibles son solo nombres base, con máximo 80 por grupo; no rutas o IP completas.
- Se registran candidatos, reglas configuradas propias presentes/ausentes/no verificables, TCP por PID como instantánea, y endpoints UDP como puertos locales. **Regla presente ≠ tráfico comprobado bloqueado.**
- No cambia las diez etapas ni los requisitos de `Get-PCADReportUiState` para habilitar Aplicar. El panel y los informes JSON/TXT muestran «COBERTURA NO CERTIFICADA».
- `AllAutodeskTrafficBlockedVerified=false`, `AutoCADWebViewLaunchPreventedVerified=false`, `WebViewIsolatedFromOtherAppsVerified=false`. Sin prueba física, estas garantías negativas NO se cambian.
- Microsoft documenta que los procesos WebView2 pueden compartir `CoreWebView2Environment` y UDF; el Firewall por ruta de programa no provee una selectividad automática por anfitrión para un mismo `msedgewebview2.exe`. No usar bloqueo global del runtime, ACL ni cambios en licencias como atajos.
- QA fixtures PS5.1/7 y diagnóstico integrado WinForms, además de firewall temporal y ZIP reproducible. Evidencia F11: `docs/F11_MATRIZ_COBERTURA_WEBVIEW2.md`.

## F12 — evaluador de aceptación RC1 sin autoaprobación

- `src/ParcheCAD.RCGates.ps1` evalúa dos reportes de diagnóstico `diagnostico.json` (antes y después), no modifica Windows, no crea una capa nueva de firewall ni altera el requisito de diez etapas.
- Diez puertas: DIAGNOSTICOS, AUTOCAD_INSTALADO, REGLAS_SALIENTES, TRAFICO_AUTODESK, WEBVIEW2_AUTOCAD, OTRAS_APLICACIONES, GUI_UAC, REINICIO_Y_ROLLBACK, AVG_ACTIVO, AUTOCAD_FUNCIONAL.
- Solo DIAGNOSTICOS puede acreditarse `PASS` por dos JSON coherentes, con recuperación sana y `Sections.Coverage` no certificada. La instalación puede quedar `OBSERVADO` y la regla `CONFIGURACION_OBSERVADA`; **estos estados NO son garantía de tráfico bloqueado**.
- `Decision=BLOCKED`, `ProductionCertified=false`, `AllAutodeskTrafficBlockedVerified=false`, `WebViewIsolatedVerified=false` hasta recopilar evidencia física de cada puerta. Está prohibido derivar cumplimiento RC1 de CI verde.
- `tools/Invoke-ParcheCADRC12.ps1` produce JSON y TXT con conteos y estado, sin rutas, IP ni líneas de comando privadas. No ejecuta Apply/Rollback, UAC, binarios AutoCAD ni cambios en servicios o antivirus.
- QA PS5.1/7 con fixtures y en Windows real desechable: diagnóstico solo lectura seguido del evaluador (dos instantáneas iguales como smoke, **no prueba de antes/después**). Guía: `docs/F12_GATE_RC1_QA_INTEGRADA.md`.
- Mantener las cuatro leyes KISS, anti-ruido, no parches, UX; corregir en origen con pruebas transversales. Sin WebView2 Microsoft global ni automatismos de licenciamiento.

## F13 — comprobar tráfico TCP real con ejecutable ficticio

- **Alcance:** `tests/F13.SyntheticEgress.Integration.ps1` en Windows GitHub-hosted compila un cliente TCP IPv4 ficticio y un EXE de control idéntico en ruta distinta; verifica conexión inicial de ambos, bloqueo efectivo de dos intentos únicamente para el primero y conexión restablecida tras rollback PCAD4.
- Reutiliza el motor F4, valida línea base, identidad de reglas y limpieza propia `finally`; no crea módulos ni servicios residentes ni modifica AutoCAD, WebView2 Microsoft, licencias o antivirus.
- Es evidencia efectiva de **una regla Outbound por ruta aplicada a un EXE de prueba**. No implica cobertura de AutoCAD instalado, Autodesk compartido, UDP, IPv6, LAN ni WebView2 exclusivo. `Get-PCADRC12Assessment` sigue BLOCKED.
- Evidencia: `docs/F13_PRUEBA_EGRESO_TCP_REAL.md` y pipeline GitHub Actions. No confundir configuración de reglas, prueba sintética y certificación de aplicación real.

## F14 — alcance de ejecutables Autodesk compartidos

- `Get-PCADExecutableCatalog` reutiliza un **único recorrido acotado** para raíces AutoCAD confirmadas y carpetas conocidas de programas Autodesk compartidos (AdODIS, Access, Autodesk Desktop App, Identity Services y Common Files/Autodesk Shared).
- Raíces por defecto basadas en `ProgramFiles`/Common Files; no recorrer todo C:, perfiles personales ni rutas UNC. Sin traversal de junctions/symlinks.
- Límite de 900 archivos y profundidad 7 por AutoCAD; 250 y profundidad 5 por raíz compartida. El código marca truncamiento en profundidad, cantidad y errores de acceso.
- `Status` del producto controla la capacidad de declarar completo el diagnóstico; `SharedStatus` advierte si el inventario compartido es parcial **sin bloquear un Apply a EXE de producto que esté bien verificado**.
- Todos los EXE descubiertos en raíces compartidas permanecen `AUTODESK_COMPARTIDO`, `Policy=SOLO_INVENTARIO`, excluidos de reglas automáticas; WebView2 `msedgewebview2.exe` continúa excluido.
- `Sections.CatalogScope` expone estados de ambas exploraciones y `SharedAutomaticBlocking=false`; WinForms informa el estado. La existencia en carpeta no demuestra firma, proveedor ni uso exclusivo.
- Fixtures `tests/F14.SharedCatalog.Tests.ps1` PS5.1/7 y test headless del diagnóstico/UI; evidencia `docs/F14_INVENTARIO_COMPARTIDO_QA.md`.

**NEXT: una única QA integrada de aceptación en Windows con escritorio auténticamente interactivo, AutoCAD instalado, AVG habilitado, trazas de red y reinicio; si no existe entorno/evidencia, RC1 sigue BLOCKED. PRs Draft, no merge ni release.**
