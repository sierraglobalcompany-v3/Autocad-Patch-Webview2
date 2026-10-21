# F12 — Puertas RC1 y prueba integrada reproducible

**Estado:** herramientas de evaluación F12 en rama `feat/f12-integrated-qa-gates` (PR Draft). **No RC1, no lanzamiento, no merge ni cambios a Windows del usuario.**

## Objetivo

No seguir acumulando fases sin una prueba final. F12 formaliza los criterios que **deben** estar acreditados en una única sesión integrada antes de presentar RC1. Un CI verde en runners sin AutoCAD certifica el **código**, no la **cobertura del bloqueo real**.

## Arquitectura KISS

- `src/ParcheCAD.RCGates.ps1`: módulo puro de evaluación **solo lectura** de dos informes `diagnostico.json` (antes y después). No invoca firewall, licencias, servicios, UAC, red ni AutoCAD.
- `tools/Invoke-ParcheCADRC12.ps1`: CLI que compara informes, devuelve una matriz de diez puertas y opcionalmente guarda `RC12_EVALUACION.json` + `RC12_RESUMEN.txt` **sin rutas, IP ni argumentos privados**.
- `tests/F12.RCGates.Tests.ps1`: comprueba escenarios vacíos, instalaciones detectadas, reglas configuradas, informe parcial, evidencia WebView2 contradictoria, conteos inválidos y recuperación pendiente.
- `tests/F12.RealWindows.Integration.ps1`: en Windows GitHub-hosted ejecuta diagnóstico real de solo lectura y lo pasa al evaluador como ambas instantáneas para comprobar que **NO** se conceda aprobación falsa a una máquina sin AutoCAD. Dos informes iguales en esa prueba no acreditan un antes/después.
- El ZIP técnico DEV incorpora el módulo, el CLI y esta guía. No se añade driver, servicio, escáner nuevo ni motor paralelo de reglas.

## Diez puertas RC1

| Puerta | Qué aporta la herramienta F12 | Qué queda por probar |
|---|---|---|
| DIAGNOSTICOS | Dos JSON válidos con 10 etapas OK y recuperaciones sanas | Comparabilidad entre antes/después en el mismo entorno |
| AUTOCAD_INSTALADO | Archivo `acad.exe` y año encontrados | Firma, autenticidad, ejecución funcional y versiones exigidas |
| REGLAS_SALIENTES | Regla propia PCAD4 configurada por ruta de EXE y sin conflicto | Cobertura de tráfico real y reglas adicionales de terceros |
| TRAFICO_AUTODESK | Solo evidencia de inventario | Medición de egress TCP/UDP IPv4/IPv6, por proceso/servicio y ventanas temporales sostenidas |
| WEBVIEW2_AUTOCAD | Atribución probable del anfitrión | Demostrar que AutoCAD no ejecuta WebView2 o que no transmite nada sin afectar runtime compartido |
| OTRAS_APLICACIONES | No se bloquea WebView2 Microsoft de forma global | WhatsApp, Outlook y otras apps funcionando antes y después |
| GUI_UAC | Eventos WinForms y estados probados sin sesión de escritorio | Acciones reales con UAC aceptada/denegada, DPI, foco, cancelaciones y avisos |
| REINICIO_Y_ROLLBACK | Restauración desde segundo PowerShell | Reinicio completo durante fallo, integridad del journal y reversión final |
| AVG_ACTIVO | No se modifica el antivirus | QA con AVG habilitado y sin interferencias |
| AUTOCAD_FUNCIONAL | Inventario de instalaciones y ejecutables | Funciones operativas tras aislar Internet y consecuencias de licenciamiento |

**Estados:** `PASS` únicamente para un diagnóstico coherente; `OBSERVADO` para un archivo detectado; `CONFIGURACION_OBSERVADA` para reglas de programa verificadas. Los demás quedan `BLOCKED`. `Decision` permanece `BLOCKED` y `ProductionCertified=false` hasta introducir **evidencia verificable de las otras puertas en una fase posterior**, no por una casilla de autoaprobación.

## Uso futuro en VM Windows de QA

El evaluador lee dos diagnósticos ya generados. No ejecuta `Apply` y no altera Windows:

```powershell
powershell.exe -NoProfile -File .\tools\Invoke-ParcheCADRC12.ps1 `
  -Before "C:\QA\antes\diagnostico.json" `
  -After "C:\QA\despues\diagnostico.json" `
  -OutputDirectory "C:\QA\resultado"
```

**No ejecutar bloqueos en el PC principal hasta que exista una RC1 suficientemente probada.** Preparar un Windows de escritorio aislado con restauración por snapshot, AutoCAD genuino autorizado y conexiones de prueba; realizar una única sesión guiada de aceptación, con rollback y pruebas de otras aplicaciones. Las credenciales, IP y journals privados no se suben a GitHub.

## Bloqueos reales que ninguna prueba en GitHub resuelve

- No hay licencia/instalación de AutoCAD 2023–2027 en el runner.
- El entorno GitHub-hosted no proporciona sesión de escritorio WinForms interactiva/UAC fiable, reinicio real controlado con persistencia ni AVG del usuario.
- Una regla por `acad.exe` no controla necesariamente servicios Autodesk compartidos, conexiones de proxies ni `msedgewebview2.exe` compartido.
- Bloquear Internet no equivale a impedir la creación de WebView2; sin mecanismo exclusivo demostrado, sigue **NO RESUELTO**.

## Próximo trabajo concreto

1. Validar en GitHub que F12 entrega siempre la decisión correcta y no introduce regresiones en F0–F11.
2. Corregir los fallos detectados y actualizar la continuidad.
3. Planificar, **sin pedir pruebas repetitivas al usuario**, la ejecución única en una VM Windows auténticamente interactiva; si el entorno no está disponible, registrar `BLOCKED` y no lanzar RC1.

**Criterio de cierre:** nunca pasar a RC1 por tener cuatro jobs verdes; el lanzamiento debe basarse en cobertura real, reversión y UX verificadas.
