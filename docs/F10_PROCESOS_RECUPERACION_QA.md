# F10 — Ciclo de vida de procesos y recuperación tras reiniciar ParcheCAD

**Estado:** cambios y pruebas automáticas en GitHub PASS; PR #12 Draft, apilado sobre #11; **NO RC1 / Release / merge**.  
**Evidencia principal:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39543990081 — CI #90, **4/4 PASS** (Windows PS5.1, PS7, firewall temporal real, ZIP reproducible).

## Problemas encontrados

- Antes, `Cancelar` y `FormClosing` intentaban `Kill()` y `Dispose()` de un proceso de diagnóstico pero **no esperaban su salida**. Podían decir «cancelado» o cerrar sin haber verificado su terminación.
- La reversión de un journal `CREATING` se había probado con un firewall real, pero siempre dentro del mismo proceso de PowerShell. Esto no demostraba que el archivo permitiera reconstruir la operación tras reiniciar la aplicación.

## Cambios integrados y comprobados

- `src/ParcheCAD.Panel.ps1`: función `PCAD-StopOwnedDiagnostic` llamada tanto por Cancelar como por cierre del formulario. Actúa **solo sobre `$script:Proc`**, el proceso de diagnóstico de solo lectura creado por el panel; nunca toca `AdminProc`, servicios ni otros PowerShell. Si está activo: `Kill()`, `WaitForExit(5000)`, `Dispose()`. Si falla, conserva la referencia, avisa de fallo y bloquea una afirmación falsa de cancelación o cierre.
- El evento Cancelar limpia el resultado anterior y los controles solamente después de confirmar fin del proceso; FormClosing cancela el cierre si no puede detener al hijo.
- El QA F9 ampliado en un Windows temporal inicia **dos** PowerShell independientes y prueba que Cancelar y FormClosing finalicen únicamente el PID propio, conservando vivo el otro. Todo el código de GUI se ejecuta en STA sin apertura de escritorio gráfico visible.
- `tests/F10.Recover.Child.ps1`: ejecutable de test restringido a `GITHUB_ACTIONS=true` y `RUNNER_ENVIRONMENT=github-hosted`, exige nombre PCAD4 exacto y un ejecutable ficticio `acad.exe` bajo TEMP. Al cargar un journal `CREATING` en **otro proceso nuevo**, verifica identidad de regla, llama al rollback y certifica que desapareció del firewall y se actualizó el journal.
- `tests/F4.RealFirewall.Integration.ps1`: sustituye la recuperación simulada intraproceso por la ejecución de `F10.Recover.Child.ps1` en un segundo PowerShell 5.1. El test crea únicamente una regla local efímera y conserva limpieza `finally` de ese nombre de regla. No afecta archivos de Autodesk.

## Alcance exacto de la evidencia

**PASS:** eventos Cancelar/FormClosing, espera efectiva al PID propio, proceso ajeno intacto, lectura de manifiesto persistente desde otro PowerShell, reversión de regla ficticia real, informe de journal y ausencia de regla residual. Suites anteriores, PS5.1/7 y ZIP técnico con SHA256 también PASS.

**NO CERTIFICADO:**

- Reinicio del sistema operativo en mitad de una escritura, pérdida abrupta de energía, controles de servicios/cortafuegos de AVG.
- UAC real (aceptado/denegado), screenshots, escalado/DPI o interacción por mouse/teclado de un escritorio Windows.
- AutoCAD 2023–2027 verdaderamente instalado, medición de IPv4/IPv6 TCP/UDP en funcionamiento, servicios Autodesk compartidos, conexiones a través de terceros.
- Que AutoCAD deje de crear `msedgewebview2.exe` o que se bloqueen exclusivamente los WebView2 de AutoCAD. Prohibido bloquear globalmente el runtime compartido porque dañaría aplicaciones ajenas.

## Principios y próxima decisión

KISS y ley anti-ruido: una sola función de finalización para Cancelar/Cerrar; mismo motor de rollback desde proceso nuevo, sin reimplementar reglas. No parches de binarios ni licencias; no tocar antivirus.

**NEXT único — F11:** producir **matriz de cobertura** de los componentes AutoCAD/Autodesk que siguen fuera de las reglas por EXE, determinar qué tráfico/servicios pueden atribuirse con seguridad y priorizar un QA de escritorio Windows real para visual/UAC y reinicio, sin solicitar pruebas aisladas al usuario. Si el aislamiento WebView2 sigue sin demostrarse, mantenerlo como BLOCKED y no anunciar RC1 con cumplimiento falso.
