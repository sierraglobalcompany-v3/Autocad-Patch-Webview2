# F11 — Matriz de cobertura AutoCAD, Autodesk y WebView2

**Estado:** implementada en rama `feat/f11-matriz-cobertura`, QA automatizada y diagnósticos Windows verificados. **SIN RC1 ni Release**.

## Problema identificado

F0–F10 podían encontrar ejecutables AutoCAD, servicios Autodesk y WebView2, preparar reglas salientes reversibles, pero **no tenían una matriz única** que separara explícitamente la capacidad de crear una regla de la **cobertura de tráfico comprobada**. Un programa instalado, una regla existente o la ausencia de conexiones en una instantánea no prueban aislamiento de red.

## Arquitectura KISS / no ruido

`src/ParcheCAD.Cobertura.ps1` contiene únicamente una función pura `Get-PCADCoverageReport`. Consume las mismas estructuras que ya producen Catalogo, Servicios, Procesos, Conexiones, Política y NetworkOverview; no vuelve a escanear el disco ni modifica el firewall.

Se agrega `Sections.Coverage` al JSON/TXT existentes, junto con el resumen WinForms. **Se conservan las diez etapas y el contrato F8**; no se añade una consulta costosa ni se alteran condiciones Apply/Rollback. El informe expone **nombres basenames** (máximo 80 por grupo) y cantidades, nunca rutas privadas, argumentos, IP o datos de sesión.

## Qué significa cada categoría

| Categoría | Política de la matriz | Qué se sabe | Qué no se puede afirmar |
|---|---|---|---|
| AUTOCAD_PRODUCTO | CANDIDATO_EXE | EXE encontrado bajo raíz AutoCAD conocida; puede prepararse regla saliente | No prueba que ya esté bloqueado ni que todas sus llamadas salgan por ese EXE |
| AUTODESK_COMPARTIDO | EXCLUIDO_AUTOMATICO | Componente compartido catalogado, p. ej. AdODIS | No se desactiva porque puede afectar otros Autodesk |
| WEBVIEW2_COMPARTIDO | EXCLUIDO_AUTOMATICO | Runtime Microsoft detectado | No se atribuye con certeza exclusiva ni se bloquea globalmente |
| DESCONOCIDO | NO_CLASIFICADO | Archivo no atribuible con seguridad | Sin reglas automáticas |
| SERVICIOS_AUTODESK | INVENTARIO_NO_BLOQUEADO | Servicios y nombres detectados | No implica que no transmitan tráfico o que se hayan bloqueado |
| PROCESOS_OBSERVADOS | INSTANTANEA | Procesos relevantes y PIDs en ese instante | PIDs reutilizables, conexiones fuera de captura |

Se separan **reglas candidatas, presentes, ausentes y no verificables**. Incluso `EXISTS_VALID` acredita solamente la configuración de una regla propia, no el resultado de tráfico. TCP es una captura puntual. `UDP_ENDPOINT` es un puerto local, no el destino remoto.

### Garantías negativas explícitas

En todos los escenarios los campos `AllAutodeskTrafficBlockedVerified`, `AutoCADWebViewLaunchPreventedVerified` y `WebViewIsolatedFromOtherAppsVerified` deben permanecer `false` mientras no exista una demostración real reproducible.

## Evidencia técnica primaria

- Microsoft, [WebView2 process model](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/process-model): browser/renderer/helper se agrupan por entorno y user-data-folder; varias instancias pueden compartir procesos.
- Microsoft, [Manage user data folders](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/user-data-folder): la carpeta de datos depende del anfitrión, pero puede compartirse con otras instancias y aplicaciones.
- Microsoft, [Configure firewall rules](https://learn.microsoft.com/en-us/windows/security/threat-protection/windows-firewall/best-practices-configuring): una regla por ruta de programa actúa sobre ese ejecutable, no sobre cualquier proceso hijo o servicio compartido de Autodesk.

**Conclusión de diseño:** usar PID, padre, UDF y nombre de ejecutable puede ayudar a una atribución **probable**, pero **no** crea por sí solo una regla del Firewall de Windows capaz de diferenciar dos anfitriones dentro del mismo ejecutable `msedgewebview2.exe`. Impedir la creación de WebView2 dentro de AutoCAD tampoco se consigue con un bloqueo de red. No se recomienda cambiar runtime Microsoft, su UDF, permisos globales ni licencias/instaladores Autodesk como supuesto atajo.

## Pruebas ejecutadas y puertas QA

**CI #95 PASS 4/4:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39545583352 — PowerShell 5.1 y 7, WinForms con diagnóstico real no interactivo y sección Coverage comprobada, regla ficticia de firewall/reversión y ZIP SHA256 extraído.

Casos comprobados:

1. Fixture sin Autodesk: seis categorías con cero, sin afirmar cobertura.
2. Fixture con EXE principales, auxiliares, servicios compartidos y WebView2: recuentos y exclusiones correctos.
3. Reglas propias presentes y ausentes: **configuración**, nunca «tráfico bloqueado verificado».
4. TCP por PID y UDP endpoint: separar observación de conclusión; no divulgar direcciones o rutas personales.
5. Diagnóstico real solo lectura en runner Windows, diez checks intactos y `Sections.Coverage` presente y visible en WinForms.
6. ZIP allowlist con módulo F11 y documento, hash reproducible.

## Bloqueos RC1

**NO SE HA PROBADO AutoCAD real instalado.** Falta correlación TCP/UDP IPv4/IPv6 sostenida, servicios compartidos y proxies; QA gráfica interactiva con UAC; reinicio Windows durante escritura; funcionamiento bajo AVG. **WebView2 exclusivo de AutoCAD: BLOCKED/NO RESUELTO**, no inventar capacidad de control por aplicación.

**NEXT único F12:** elaborar y ejecutar cuando exista entorno una QA integrada de AutoCAD real + Windows con GUI interactiva/UAC/reinicio; evaluar tráfico de servicios compartidos sin arriesgar WebView2 ajeno. Preparar evidencias y criterios de aceptación antes de RC1, sin pruebas fragmentadas al usuario. Mantener PRs Draft y `main` sin merge.
