# PROJECT_CONTINUITY_CURRENT — ParcheCAD 4.0

**Actualización:** 2026-10-21. **Estado:** código F0–F11 publicado en PRs Draft, **NO RC1, NO RELEASE, SIN MERGE**.  
**Repositorio único:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2  
**Rama actual:** `feat/f11-matriz-cobertura` · **PR #13 Draft** sobre #12 → #11 → #10 → #9 → #8 → #7 → #6 → #5 → #4 → #3; `main` no incorpora estos cambios.  
**CI F11 verificado:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39545583352 — **#95, PASS 4/4** en Windows PowerShell 5.1, PowerShell 7, reglas temporales y ZIP reproducible. Tras cualquier cambio al HEAD, esperar su propio CI antes de declarar el nuevo HEAD verde.

## Objetivo del usuario y reglas innegociables

El usuario quiere bloquear el tráfico a Internet de AutoCAD 2023–2027 y, eventualmente, todos los componentes Autodesk de su instalación, aun con pérdida de funciones en línea. También desea que AutoCAD **no inicie WebView2**, sin afectar WhatsApp, Outlook ni otras aplicaciones que comparten `msedgewebview2.exe`.

**Estado REAL:** la aplicación solo puede proponer reglas salientes por ruta sobre EXE clasificados como AutoCAD producto; otros servicios/procesos Autodesk y WebView2 compartido siguen fuera. **No existe evidencia de bloqueo total ni de impedir la ejecución de WebView2 en AutoCAD.** Bloquear conectividad no equivale a impedir que WebView2 se ejecute.

**Cuatro leyes:**
1. **KISS:** simple, eficiente, optimizado, eficaz. Sin drivers, daemons, arquitecturas complejas o trabajo duplicado.
2. **Anti-ruido:** fusionar, mejorar, optimizar o eliminar redundancia demostrando impacto.
3. **No parches:** aislar la causa y corregir fuente/componente afectado, luego ejecutar QA transversal.
4. **Diseño/UX:** interfaces claras y confiables; visualización de progreso, estados COMPLETO/PARCIAL reales, bloqueo de acciones inseguras y recuperación explicable.

**Flujo:** implementar directamente en GitHub, Codex únicamente cuando sea estrictamente indispensable, evitar ping-pong y pruebas de usuario por cada fase. Preparar una sola validación integrada final cuando exista RC1 con evidencia. Mantener README + SPEC + continuidad actualizados y fuente reconstruible desde GitHub.

**Protecciones:** no bloquear globalmente `msedgewebview2.exe`, ni modificar licencias, binarios, servicios, tareas ajenas ni AVG/Defender. Reglas únicamente tras plan, administrador y confirmación, con journal privado y rollback. No publicar IP, argumentos o rutas personales.

## Estado técnico implementado

| Fase | Entregado | Evidencia |
|---|---|---|
| F0–F2 | Inventario AutoCAD, procesos/WebView2, servicios, firewall, tareas; WinForms | PS5.1/7, lectura sin AutoCAD |
| F3 | PID/PPID/UDF y conexiones observadas para WebView2, atribución PROBABLE | Fixtures; no demuestra aislamiento |
| F4 | Política por EXE producto; Apply/rollback con journal | Firewall temporal Windows |
| F5 | Rutas personalizadas, reportes saneados, recuperación incompleta | Fixtures, CI |
| F6 | DisplayIcon, ZIP de desarrollo allowlist + SHA256 | Windows QA / ZIP reproducible |
| F7 | Apply fail-closed cuando existen journals parciales/corruptos | Windows diagnóstico parcial |
| F8 | Contrato único de diez etapas y estado válido para GUI/CLI | Fixtures WinForms |
| F9 | Eventos Analizar/Cancelar/FormClosing, marcador de fin del proceso hijo | CI headless WinForms; NO UAC real |
| F10 | Cancelación y cierre por proceso propio, reversión desde **otro** PowerShell | CI #94 PASS; no reinicio Windows |
| **F11** | **Matriz informativa de EXE, servicios compartidos, WebView2, reglas PCAD4 y TCP/UDP** en JSON/TXT/WinForms | **CI #95 PASS 4/4** |

### F11 — Nuevo checkpoint

- `src/ParcheCAD.Cobertura.ps1`: único cálculo **solo lectura** a partir del catálogo/servicios/procesos/conexiones/plan ya recopilados. Seis grupos: AUTOCAD_PRODUCTO, AUTODESK_COMPARTIDO, WEBVIEW2_COMPARTIDO, DESCONOCIDO, SERVICIOS_AUTODESK, PROCESOS_OBSERVADOS.
- `src/ParcheCAD.Diagnostico.ps1` incorpora **`Sections.Coverage`** en JSON y resumen TXT sin cambiar las diez etapas, permisos ni condiciones del botón Aplicar.
- `src/ParcheCAD.Panel.ps1`: exhibe recuento de EXE candidatas, reglas propias presentes, ausentes o no verificadas, servicios, TCP/UDP, WebView2; el test headless F9 exige matriz desde un diagnóstico real y «NO CERTIFICADA».
- `tests/F11.Cobertura.Tests.ps1`: fixtures vacíos y mixtos, clasificación y exclusiones, ausencia de filtración de rutas/IP, TCP vs UDP endpoint, no declaraciones engañosas de aislamiento. Ejecutado PS5.1 y PS7.
- Campos de garantía `AllAutodeskTrafficBlockedVerified`, `AutoCADWebViewLaunchPreventedVerified`, `WebViewIsolatedFromOtherAppsVerified` **siempre false** hasta evidencia externa real. Una regla presente **no prueba tráfico bloqueado**.
- `docs/F11_MATRIZ_COBERTURA_WEBVIEW2.md`: auditoría con documentación Microsoft sobre proceso WebView2/UDF compartido y Firewall por programa. `tools/Build-ParcheCAD.ps1` incluye código/doc F11 en ZIP DEV SHA256.
- QA #95 Windows 4/4 PASS. **Ningún AutoCAD real fue instalado o bloqueado.**

## Mapa de código y reconstrucción

- `src/ParcheCAD.Core.ps1` registro, instalaciones, procesos/servicios/firewall/tareas/conexiones.
- `src/ParcheCAD.Catalogo.ps1` clasificación; `ParcheCAD.Network.ps1` WebView2 probable; `ParcheCAD.Cobertura.ps1` F11.
- `src/ParcheCAD.Policy.ps1`, `ParcheCAD.Firewall.ps1`, `ParcheCAD.Historico.ps1` política/reglas/journals.
- `src/ParcheCAD.Diagnostico.ps1`, `ParcheCAD.Evidence.ps1`, `ParcheCAD.UIState.ps1` diez etapas, exportación sana/privada y estado.
- `src/ParcheCAD.Panel.ps1`, `ParcheCAD.Reglas.ps1`, `Abrir_ParcheCAD.cmd` UI y CLI.
- `tests/`, `.github/workflows/f0-static-qa.yml` QA. `tools/Build-ParcheCAD.ps1` ZIP.
- `README.md`, `docs/SPEC_MAESTRA.md`, `docs/F11_MATRIZ_COBERTURA_WEBVIEW2.md` documentación actual.

**Reconstrucción:** clonar **la rama F11 indicada**, revisar `README.md` + SPEC + continuidad, ejecutar GitHub Actions. Artifact `ParcheCAD_4.0_DEV_NOT_RELEASE` (ZIP + SHA256) se genera desde GitHub y es temporal, **no instalador certificado**, no usar Apply en PC principal.

## Bloqueos que impiden RC1

1. **AutoCAD instalado:** todavía ninguna prueba funcional con AutoCAD 2023, 2024, 2025, 2026 o 2027 verdadero.
2. **Tráfico real:** no hay pruebas TCP/UDP sostenidas IPv4/IPv6 sobre todos los procesos Autodesk ni servicios compartidos/proxies. Una captura vacía no demuestra ausencia.
3. **WebView2 exclusivo:** sin mecanismo acreditado para prohibir que AutoCAD lo inicie y sin forma demostrada de aislar el mismo runtime compartido por anfitrión con una regla tradicional de programa.
4. **UI interactiva:** GitHub-hosted valida eventos WinForms sin ventana visible; no captura clicks reales, escalado DPI, UAC aceptado/denegado, accesibilidad o AVG del usuario.
5. **Reinicio:** se verificó recuperación después de iniciar otro proceso PowerShell, **no** un reinicio físico/abrupto de Windows.
6. **Empaquetado:** ZIP técnico reproducible únicamente; PRs Draft sin merge o Release.

## NEXT único

**F12 — diseñar y preparar una única QA final integrada en Windows con escritorio real y AutoCAD instalado:** cobertura por ejecutable y servicio, tráfico IPv4/IPv6 TCP/UDP antes/después de reglas, UAC visual, escenarios de fallo y reinicio/rollback, verificar no afectar WhatsApp/Outlook. No anunciar que WebView2 está deshabilitado si solo existe atribución probable. Resolver bloqueos en origen; dejar PRs #3–#13 Draft y `main` intacta mientras falten pruebas. No pedir al usuario validaciones por módulos.
