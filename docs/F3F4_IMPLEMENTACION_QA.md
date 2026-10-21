# F3/F4 — Implementación, límites y QA

**Repositorio:** sierraglobalcompany-v3/Autocad-Patch-Webview2  
**Rama:** feat/f3-f4-atribucion-politicas (PR #5 Draft, apilado sobre PR #4)  
**Estado:** F3 observacional desarrollado; F4 planificador y motor reversible desarrollados; QA automatizada en curso; NO release.

## F3: lo que podemos demostrar

El diagnóstico consulta procesos \`acad.exe\`, \`msedgewebview2.exe\`, sus PID/PPID, pistas de carpeta de datos WebView2 y conexiones TCP/UDP. \`src/ParcheCAD.Network.ps1\` intenta asociar los procesos al AutoCAD de 2023–2027 correspondiente y marca la atribución **PROBABLE** cuando hay señales; cuando no, marca **INDETERMINADA** o **CONFLICTO**.

**No prueba** que todo el tráfico de WebView2 esté bloqueado, que el proceso no se ejecute, ni que la conexión de red esté ligada exclusivamente al AutoCAD anfitrión. El runtime de Microsoft sigue compartido y **NO** tiene bloqueo global por defecto.

## F4: diseño del motor

- Plan basado en un catálogo **de ejecutables confirmados bajo instalaciones de AutoCAD 2023–2027**, no todos los ejecutables Autodesk por defecto.
- Reglas únicamente \`Outbound\`, \`Block\`, \`Profile Any\`, \`PersistentStore\`, \`Group=PCAD4_MANAGED\`.
- ID determinista \`PCAD4_A_<SHA256-parcial>_OUT\` calculado por ruta completa normalizada. Dos ejecuciones no deben duplicar la misma regla.
- **No** se crean reglas para \`msedgewebview2.exe\`, servicios compartidos Autodesk, programas desconocidos, carpetas o DLL.
- Preflight: ruta ejecutable y versión, ausencia de junction en el archivo, reglas existentes y colisiones de identidad, límite de 900 entradas.
- No ejecutar el plan sin permiso explícito de administrador, confirmación y copia de las operaciones.
- Journal local por operación: estados \`PREPARED\`, \`CREATING\`, \`CREATED\`, \`ALREADY_PRESENT\`, \`ROLLED_BACK\`, \`ROLLBACK_ERROR\`. Archivo JSON \`PCAD4_<id>.json\` guardado bajo \`informes/operaciones\`.
- Tras cada creación, verifica que la regla local corresponde exactamente a la ruta, dirección, acción, grupo y perfil esperados.
- Si hay fallo durante la aplicación, intenta revertir **solo** lo nuevo. La recuperación manual queda explícita si alguna regla propia no pudo revertirse.
- La recuperación deliberada requiere manifest y confirmación; reglas anteriores o ajenas nunca se borran por similitud del nombre.

## Operación por consola (no usar en producción todavía)

**Solo vista previa / solo lectura:**

\`\`\`powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\src\ParcheCAD.Reglas.ps1 -Mode Preview
\`\`\`

**Funciones creadas pero reservadas para QA de integración en entorno controlado:**

\`\`\`text
src/ParcheCAD.Reglas.ps1 -Mode Apply -ConfirmChange
src/ParcheCAD.Reglas.ps1 -Mode Rollback -Manifest <ruta al JSON local> -ConfirmChange
\`\`\`

Estos modos requieren elevación administrativa y una segunda confirmación interactiva; **no se recomienda ejecutarlos todavía en el PC principal**. En una VM aislada se deberá comprobar reversión y ausencia de afectación ajena antes de activar sus botones en el panel.

**Precisión:** un bloqueo de salida de Windows por \`-Program\` suele afectar conexiones salientes del ejecutable también hacia la red local, no únicamente internet. Tampoco garantiza bloquear el tráfico que salga de un ejecutable compartido en nombre de AutoCAD.

## Pruebas automáticas

- \`tests/F3F4.Tests.ps1\`: árboles WebView2; diferenciación de WhatsApp; ID estable por ruta; vista previa; exclusión WebView2; aplicación por mocks de PowerShell; ejecución repetida sin duplicados; colisión de nombre ajeno; simulación de fallo intermedio y rollback; reversiones idempotentes.
- \`.github/workflows/f0-static-qa.yml\`: Windows PowerShell 5.1 y PowerShell 7; smoke de diagnóstico de diez etapas sin AutoCAD; \`Preview\` real sin modificar firewall.
- **Nunca** ejecutar \`-Mode Apply\` contra el firewall real del runner compartido. En CI solo están permitidos mocks y operaciones de lectura.

## Problemas detectados y corregidos en CI

La primera prueba F4 falló porque el mock declaraba \`ErrorAction\` dos veces; se corrigió con funciones avanzadas y parámetros comunes nativos. Las pruebas PS5.1/PS7 posteriores pasaron antes de ampliar el smoke.

## Pendientes para RC1

1. Completar QA del modo real de aplicar/revertir sobre VM Windows aislada con snapshots de firewall antes/después y simulación de interrupción.
2. Test de GUI WinForms visual/responsivo, cancelar una consulta larga, errores y cierre, sin antivirus desactivado.
3. Añadir controles gráficos de aplicar/revertir solamente cuando QA del motor de firewall esté aprobado.
4. Evaluar cobertura de servicios compartidos Autodesk como opción avanzada, no automática, con impactos claramente descritos.
5. Resolver o declarar no disponible el aislamiento exclusivo de WebView2 de AutoCAD. No usar reglas globales salvo una elección explícita e informada fuera de la política segura de este MVP.
6. Empaquetado con checksums y documentación de recuperación offline. Mantener los PR Draft sin merge hasta revisión.

**NEXT:** QA real de F4 en Windows aislado + implementación de controles de aplicación/reversión en el panel únicamente tras su PASS. No pedir al usuario pruebas por cada fase; RC1 será la candidata integrada para aceptación.
