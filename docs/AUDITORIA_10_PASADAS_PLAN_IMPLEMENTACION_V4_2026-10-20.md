# ParcheCAD 4.0 — Auditoría de diez pasadas y plan de implementación

**Estado:** DOCUMENTACIÓN / NO IMPLEMENTADO · **Fecha:** 2026-10-20/21 · **Rama:** docs/v4-auditoria-10-pasadas  
**Repositorio único:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2  
**NEXT único:** F0, inventario de solo lectura, con pruebas de Windows y sin cambiar el firewall.

## 0. Objetivo, límites y definiciones

Objetivo solicitado: administrar bloqueos de conectividad saliente de componentes Autodesk y AutoCAD 2023–2027, incluida la investigación de cómo aislar la conectividad de WebView2 iniciado por AutoCAD. El usuario acepta que ciertas funciones online de AutoCAD puedan dejar de funcionar, pero **no** quiere afectar WhatsApp, Outlook ni otras aplicaciones WebView2.

Tres resultados diferentes que NO se deben confundir:

1. **Reglas creadas:** se registraron entradas de política; no implica efectividad.
2. **Conexiones Autodesk bloqueadas:** tráfico observado originado por programas/servicios identificados coincide con reglas activas; pueden existir rutas no descubiertas.
3. **AutoCAD no utiliza WebView2:** no crea ninguna instancia local del runtime. Una regla de firewall no garantiza esto, aunque bloquee conexiones.

El producto nunca afirmará «bloqueo total verificado» si subsiste algún origen no atribuido, se detecta una regla de directiva que no controlamos o falta observación de una ruta de tráfico. No se editarán ejecutables o mecanismos de licencia. Una suscripción legítima puede requerir validaciones periódicas; documentar las consecuencias.

## 1. Evidencia histórica REAL disponible y cómo interpretarla

**Documentos recuperados:** block.bat, find.bat, block_corregido_reenvio.bat, setup-webview2-block.ps1, setup-webview2-block-corregido.ps1 y paquetes de ParcheCAD V2, V3, V3.1 y V3.2. Se inspeccionaron códigos fuente, no solo sus nombres.

**Captura de V3.0 antes de recuperación:** 96 reglas activas clasificadas como AutoCAD; 2 de WebView2; 1 tarea sospechosa/heredada. **Captura después:** el programa informó 96 reglas retiradas; persistían dos reglas de WebView2 y una tarea de nombre «Autodesk Block WebView2». Esto no certifica que se eliminaron todas las rutas ni que se bloquearan todas las conexiones antes de la operación. La lista original completa de rutas NO está disponible: el informe histórico podría existir localmente en C:\parchecad\informes y debe recuperarse si el usuario lo suministra; no inventar las 96 rutas ni reconstruirlas del contador.

**Archivos concretos visibles en la captura:**
- C:\Program Files\Autodesk\AdODIS\V1\Setup\AdskInstallerUpdateCheck.exe
- C:\Program Files\Autodesk\AutoCAD 2023\styshwiz.exe
- C:\Program Files\Autodesk\AdODIS\V1\Setup\AdskUninstallHelper.exe
- C:\Program Files\Autodesk\AutoCAD 2023\AcPerfMonAgent.exe
- C:\Program Files (x86)\Microsoft\EdgeWebView\Application\155.0.4283.62\msedgewebview2.exe (ruta de la captura, versión no perpetua)

Reglas WebView2 visibles: WebView2GlobalBlock.5EE264B543B814BD.Inbound y WebView2GlobalBlock.5EE264B543B814BD.Outbound. No asumir que permanecen actualmente. La tarea original de WebView2 podía ejecutarse al iniciar Windows y repetirse una vez por hora, según setup-webview2-block.ps1; identificar/deshabilitar únicamente tras revisión y respaldo.

**Familias de identificadores a reconocer en modo SOLO LECTURA y migración cautelosa:**
- Etiqueta «Autodesk Block: <nombre.exe>» — BAT inicial, susceptible a colisiones.
- SGC_AUTODESK_BLOCK_V1_ — BAT con hash estable de ruta y dirección, reversible.
- PCAD_A_V3_ y PCAD_W_V3_ — paquetes anteriores ParcheCAD.
- SGC_WEBVIEW2_CONTROL_V1_ y SGC_WEBVIEW2_V2_ — controladores anteriores.
- «WebView2 Global Block - ChatGPT Fix» y «WebView2GlobalBlock.<hash>.Inbound/Outbound».
- «AutodeskBlocker_In» y «AutodeskBlocker_Out» del repositorio de referencia — NO son propias de ParcheCAD.

Una coincidencia de nombre **nunca** bastará para eliminar una regla: corroborar programa exacto, acción, dirección, ámbito y origen; exigir aprobación si es ajena.

## 2. Diez pasadas de auditoría independientes

| # | Pregunta y evidencia | Resultado | Decisión / puerta de calidad |
|---|---|---|---|
| 01 | ¿Qué funcionó previamente? Capturas 96/2/1 y scripts locales | PASS documental, efectividad de tráfico NO VERIFICADA | Importador de reglas históricas; solicitar evidencia TXT/JSON original |
| 02 | ¿Dónde están los EXE? BAT originales y discover.ps1 externo recorren carpetas Autodesk | Aprovechable con ajustes, incompleto si se usan solo Program Files | Inventario de registro + EXE real + firma; no confiar solo en carpeta |
| 03 | ¿Podemos separar 2023–2027? Todas utilizan acad.exe bajo rutas diferentes | Ruta por versión separable si existe; extras requieren clasificación | 5 perfiles identificados por ruta y metadatos, 0–5 versiones detectadas |
| 04 | ¿Qué comparte Autodesk? ODIS, Identity, Licensing, Genuine, Access | Riesgo de afectar otros productos | Grupo COMPARTIDO y selección explícita, nunca fusionar con exclusivo |
| 05 | ¿Qué hace realmente WebView2? Runtime msedgewebview2.exe fuera de Autodesk y grupos de procesos | FIREWALL POR RUTA NO AISLA POR HOST | Diagnóstico de UDF/PPID/árbol, no activar bloque global por defecto |
| 06 | ¿Son correctas las reglas? V1 y 3.x usan identidad más estable; externo duplica | Duplicados y nombres amplios en proyecto externo | Una regla saliente por ruta; Name único determinista + manifest |
| 07 | ¿Hace falta bloquear entrada? Scripts previos crean entrada y salida | Generalmente redundante para objetivo saliente | Solo Outbound por defecto; Inbound opt-in justificado |
| 08 | ¿Se recuperan cambios? V3 quitó 96, pero quedaron WebView2/tarea | Recuperación parcial observada | Backup, ownership comprobado, idempotencia, tareas heredadas con decisión separada |
| 09 | ¿Se demuestra efectividad? Contar reglas no prueba bloqueo; Windows ofrece eventos WFP 5157 | No hay certificación de tráfico aún | ActiveStore + observación IPv4/IPv6 y TCP/UDP; evidencia con límites |
| 10 | ¿Es usable/seguro? UI V3 se congeló; V2 error Execute; AVG alertó | Bloqueos críticos de QA | Worker no UI, progreso, AV activo, prueba Windows real y no cambios a ciegas |

**Auditoría estática** no reemplaza a ejecución en Windows. Estado global de la implementación 4.0: **BLOCKED hasta F0 y pruebas**.

## 3. Revisión archivo por archivo de sawyermade/autodesk-blocker

Repositorio externo: https://github.com/sawyermade/autodesk-blocker (rama master observada). Referencia, no dependencia.

| Archivo | Hallazgo al revisar el código | Decisión |
|---|---|---|
| discover.ps1 | Examina Program Files, ProgramData, Common Files y AppData de varios usuarios; busca carpetas Autodesk/ADSK, incluso anidadas; puede repetir exploraciones; silencios de acceso | Reutilizar **idea**, no código literal; deduplicar árboles, presupuesto de tiempo y errores explícitos |
| discover.bat | Se eleva para leer perfiles ajenos y usa ExecutionPolicy Bypass | F0 sin admin cuando sea viable; elevar solo para lectura restringida con consentimiento; evitar Bypass |
| block.bat | Escaneo recursivo *.exe; crea dos reglas por ejecutable; usa nombres únicos por DIRECCIÓN pero compartidos entre todos los ejecutables (AutodeskBlocker_In/Out); sin idempotencia | **No copiar motor**; un identificador por ruta/dirección, no duplicar |
| block-list.bat | Lee block-list.txt que puede incluir carpetas anidadas; reejecuta block.bat para cada una sin deduplicación global | Manifest de rutas deduplicadas y clasificadas |
| status.bat | Consulta reglas por DisplayName; no comprueba origen, estado ActiveStore ni efectividad de conexión | Reemplazar por modelo estructurado de inventario de reglas |
| unblock.bat | Elimina reglas de nombres compartidos masivamente sin verificar filtro de aplicación | **No copiar**; reversión por Name+Group+Program verificados |
| find_features.py | Lee/combina archivos de licencia | **Excluir** del alcance; no es componente necesario para firewall |
| CLAUDE.md | Declara expresamente que no hay pruebas/CI funcional | Mantener conocimiento técnico útil, exigir pruebas nuevas |

Aspectos rescatables: directorios de descubrimiento como señales, inventario de EXE ocultos, separar discover/status/unblock, compatibilidad con rutas con espacios, ausencia de dependencias de terceros.

Aspectos descartados: bloquear indiscriminadamente cualquier EXE de ProgramData/AppData, buscar carpetas por coincidencia de nombre como prueba suficiente, reglas entrantes innecesarias, nombres repetidos, ejecución repetida sin inventario, eliminación por DisplayName global y ejecución de scripts externos sin revisión.

## 4. Catálogo de detección / política de clasificación

| Clase | Ejemplos verificables | Regla por defecto |
|---|---|---|
| A_PRODUCTO | C:\Program Files\Autodesk\AutoCAD 2023\acad.exe, 2024, 2025, 2026, 2027; otros EXE bajo raíz de producto confirmada | CANDIDATO solo Outbound después de preview |
| B_SHARED_AUTODESK | Ejecutables reales de AdODIS, Identity Manager, AdSSO, Licensing, Access, Genuine, Desktop App, y Shared | SUPERVISAR; bloquear solo con confirmación de impacto compartido |
| C_WEBVIEW2 | msedgewebview2.exe bajo Microsoft\EdgeWebView\Application\<build> | NUNCA bloquear GLOBAL por defecto |
| D_DATA_LIB | WebView2Loader.dll, .WebView2\1\EBwebView, ficheros de datos | NO ES OBJETIVO DE FIREWALL por EXE |
| E_UNKNOWN | Rutas no firmadas, EXE en perfiles, Proxy/servicios indirectos | REVISIÓN MANUAL y NO VERIFICADO |

**Descubrimiento con evidencia en orden:**
1. Registro de desinstalación HKLM/HKCU x64/x86 y entradas de aplicación; comprobar DisplayName, InstallLocation e instalador.
2. Hallar acad.exe dentro de cada ubicación real (no asumir C:); validar ProductName/FileDescription/FileVersion y firma cuando esté disponible.
3. Enumerar subárbol EXE una sola vez por carpeta canónica de producto, incluidos ocultos si se autoriza; detectar symlinks/junctions y **no cruzar** a directorios ajenos.
4. Leer estado de servicios con Get-CimInstance Win32_Service, ruta ImagePath y cuenta ejecutora sin cambiar servicio.
5. Procesos Win32_Process, ruta/PID/PPID/CreationDate/CommandLine; asignar host WebView2 por múltiples señales (UDF, padre, grupo, lanzamiento), con certeza CONFIRMADA/PROBABLE/INDETERMINADA. Tener presente que dos host apps podrían compartir una UDF.
6. Inventario firewall: ActiveStore y PersistentStore, asociaciones de Program/Service, reglas Allow/Block, Enabled, perfiles, dirección, origen GPO/local cuando accesible.
7. Tareas programadas heredadas: nombre/acción/argumentos/triggers/estado; soportar acciones sin Execute o Arguments; detectarlas sin deshabilitarlas en F0.
8. Conexiones de procesos: Get-NetTCPConnection y Get-NetUDPEndpoint para observación momentánea; no asumir que un endpoint UDP demuestra flujo remoto ni que una instantánea observa todo el tráfico.

**Notar:** la ruta exacta de componentes compartidos depende de instalación/versión. Los nombres hallados en foros se tratarán como pistas; no rellenar automáticamente rutas inexistentes.

## 5. Motor de firewall: contrato F4 (aún NO implementado)

**Política base:** bloquear tráfico saliente de ejecutables seleccionados con New-NetFirewallRule (-Direction Outbound -Action Block -Program <ruta real> -Profile Any). Las reglas de servicio (-Service) se investigan solo cuando el servicio y el ejecutable reales estén comprobados; nunca usar svchost.exe como bloque global por defecto.

**Generación de inventario antes de modificar:**
- Ruta canónica normalizada, sin segmentos .., con Test-Path, FileVersion, firma y SHA256 opcional para evidencia.
- ID determinista basado en SHA256(ruta normalizada + ámbito + Outbound) que no cambia entre ejecuciones; esquema PCAD4_A_<hash>_O y PCAD4_S_<hash>_O; nombre reservado para propiedad de ParcheCAD.
- Manifest JSON con operationId, fecha, usuario redaccionado, versión detección, ruta, firma, tipo, riesgo, regla existente, Name, Group, Action, Direction, Profile, estado previo/posterior.
- Dry-run y vista previa con contadores: nuevos, ya existentes válidos, ajenos/conflicto, compartidos, sin verificar, omitidos.

**Ejecución atómica a nivel lógico (firewall no es transacción única):**
1. Preflight: UAC solo en modificación, BFE/firewall activos, backup state y permisos.
2. Crear/activar reglas propias una a una; tras cada acción, verificar identidad y filtros. Si hay colisión de Name, ABORTAR y no tocar la regla.
3. Informar progreso cada X reglas sin congelar UI; checkpoint cancelable.
4. Si hay error, registrar parcial y ofrecer compensación SOLO de reglas nuevas de operación; no hacer borrado masivo.
5. Reevaluar ActiveStore, perfiles, IPv4/IPv6 y procesos/conexiones en ventana de prueba.
6. Guardar manifest firmado mediante SHA256 del informe (integridad no autenticación) y estado final.
7. Re-ejecución idempotente, sin duplicados. Desactivación/recuperación solo de reglas identificadas como propias, con filtro exacto y confirmación; reglas antiguas se migran por proceso separado, nunca silenciosamente.

**Limitación técnica central:** el firewall tradicional asocia la condición Program a la ruta del ejecutable, no a su proceso padre. Por ello bloquear solo acad.exe no garantiza bloquear msedgewebview2.exe compartido ni procesos que envíen tráfico en nombre de AutoCAD. La política nunca traducirá esa cobertura parcial a «todo Autodesk sin internet».

## 6. WebView2: pruebas y puertas de viabilidad F3

**F3-A Observación:** ejecutar AutoCAD 2023 y 2027 (si están instalados) y registrar procesos msedgewebview2.exe, UDF, PPID, árbol temporal, destinatarios y quién envía tráfico. Aplicar pruebas de control a WhatsApp y Outlook. Procesos hijos y PID pueden cambiar o reusarse: la atribución es evidencia probabilística si no existen señales suficientes.

**F3-B Aislamiento sin driver:** determinar si la instalación concreta acepta un runtime WebView2 separado y si la separación es compatible con la versión de AutoCAD. No modificar WebView2 compartido, ni copiar DLL o tocar instalación de Autodesk sin respaldo/VM. Una política solo por nombre acad.exe puede abarcar varias versiones: comprobarlo.

**F3-C WFP avanzado:** solo si A y B fallan y existe un caso de negocio que justifique el coste. Prototipo separado con controlador firmado si la política depende de parentesco dinámico y no puede resolverse con filtros declarativos. Requiere compatibilidad Win10/Win11, firma, actualización y fallback a modo lectura. No introducir driver por defecto en 4.0 MVP.

**Estados UX separados:**
- «Ejecutables AutoCAD bloqueados / no verificado».
- «Instancias WebView2 de AutoCAD detectadas / atribución probable».
- «WebView2 compartido permitido».
- «Aislamiento de WebView2 de AutoCAD: NO DISPONIBLE» hasta que la prueba sea satisfactoria.
- «AutoCAD no ejecuta WebView2» solo si se prueba expresamente durante las funciones observadas; no generalizar.

## 7. UX — flujo preciso

Pantalla inicial: barra de estado + versiones instaladas + procesos observados + reglas propias/ajenas + tareas heredadas + estado de WebView2. Sin bloquear el hilo de la ventana.

Pestañas: (1) Resumen; (2) AutoCAD 2023–2027; (3) Componentes compartidos; (4) WebView2 y conexiones; (5) Reglas/Historial; (6) Recuperación/Informe.

Acciones habilitadas según etapa: Analizar (F0), previsualizar, aplicar reglas por versión (F4), verificar, revertir, exportar informe. Toda operación muestra etapa, procesados/total, segundos, errores acumulados y cancelar si es seguro. Botones bloqueados durante operación, pero UI no congelada. Mensajes completos/parciales/NO_VERIFICADO según comprobaciones. Sin pedir reinicio por rutina; verificar cierre y reapertura de aplicaciones y ofrecer reinicio opcional si una prueba señala la necesidad.

No usar colores rojos para «0 reglas» cuando 0 es simplemente una ausencia: «Sin reglas detectadas» no significa «Acceso garantizado».

## 8. Fases detalladas con entregables y criterios PASS/BLOCKED

### F0 — Inventario universal SOLO LECTURA | PRIORIDAD 0
Tareas:
- Implementar Discovery.ps1 para registro/instalaciones 2023–2027; resolver ruta y metadatos.
- Implementar FirewallRead.ps1 con inventario ActiveStore/PersistentStore y filtros relacionados.
- Implementar ProcessRead.ps1 con PID/PPID/commandline/UDF y services.
- Exportar JSON estructurado (schemaVersion=1), TXT resumido y diagnóstico de completitud; sanitización por defecto.
- Pester unit tests con fixtures de 0 versiones, 1, 5, rutas personalizadas, errores de acceso, PPID desactualizado y tareas sin Execute.
**PASS:** sin modificaciones al registro, firewall, servicios, tareas ni auditoría; campos inciertos identificados; informe consistente, QA Windows 10/11 documentado. **BLOCKED:** si requiere elevar para todas las operaciones sin justificación, pierde rutas o inventa propietario de procesos.

### F1 — Catálogo y clasificación
Tareas: esquema de política versionada para A_PRODUCTO/B_SHARED/C_WEBVIEW2/D_DATA/E_UNKNOWN; reglas de confianza, validación de firma/fabricante, canonicalización de rutas, symlinks/junctions, perfiles 2023–2027, catálogo de bloqueos históricos recuperados.
**PASS:** cada EXE tiene clase + motivo + evidencia + riesgo; rutas duplicadas eliminadas; rutas históricas tratadas como candidatos.

### F2 — Históricos, recuperación y modelo UX
Tareas: importador read-only de PCAD_A_V3_, PCAD_W_V3_, SGC_..., WebView2GlobalBlock..., Autodesk Block:..., AutodeskBlocker_In/Out; comprobación de acciones de tareas; snapshots; interfaz no bloqueante y barra.
**PASS:** histórico mostrado con dueño verificado/ajeno/sospechoso y propuesta de migración; no se elimina regla o tarea por nombre únicamente; informes anterior/posterior.

### F3 — Laboratorio tráfico/WebView2
Tareas: capturar baseline con y sin AutoCAD, WebView2 de Microsoft, otros host apps; validar conectividad TCP/UDP e IPv4/IPv6; usar WFP audit 5157 si está configurado; cualquier cambio de política de auditoría requiere autorización y reversión de estado original.
**PASS:** matriz de procesos y destinos observados + límites; confirmación de que WhatsApp/Outlook no fueron afectados; decisión escrita WEBVIEW2_ISOLATION_FEASIBLE=YES/NO/UNKNOWN. **BLOCKED:** falta evidencia de atribución, driver sin justificación o reglas globales aplicadas accidentalmente.

### F4 — Motor de políticas y reversión
Tareas: RulePlan/RuleApply/RuleVerify/RuleRollback; identificadores únicos, Dry-run, consentimiento por tipo y grupo, manifest, idempotencia, rollback sobre errores, gestión de ActiveStore/GPO.
**PASS:** dos ejecuciones no duplican reglas; repetición y reversión dejan equipo consistente; tareas/servicios ajenos no se alteran; preview coincide con acciones y estado final.

### F5 — Pruebas reales e integración
Matriz: Windows 10/11, PowerShell 5.1, 0/1/múltiples AutoCAD, rutas por defecto/personalizadas, usuario normal/admin, firewall activo/inactivo/GPO, IPv4/IPv6, tareas heredadas, AVG activo, actualizar WebView2, reiniciar Windows, WhatsApp y Outlook con tráfico permitido, AutoCAD abriendo/guardando, error durante aplicación, interrupción/pérdida de permisos, cancelación y reinstalación.
**PASS:** sin cambios fuera de alcance, log completo, UI responsiva, rollback probado, resultados honestos. Toda configuración del firewall debe probarse también tras reboot y update del EXE.

### F6 — Release y distribución
Tareas: README de instalación, pantalla UAC explícita, archivos sin ofuscación ni ejecución remota, checksums, changelog, firma de scripts/EXE si procede, detecciones AV evaluadas sin exclusiones, ZIP verificable.
**PASS:** artefacto reproducible, sin falsos «100%», instrucciones de recuperación offline y QA firmado. No release si alerta antivirus sin investigar o WebView2 compartido resulta bloqueado por sorpresa.

## 9. Estructura del repositorio sugerida

    README.md
    docs/
      SPEC_MAESTRA.md
      AUDITORIA_10_PASADAS_PLAN_IMPLEMENTACION_V4_2026-10-20.md
      DECISIONES_TECNICAS.md
      MATRIZ_COMPONENTES.md
      MATRIZ_QA.md
    src/
      Launch.cmd
      ParcheCAD.ps1
      Core/
        Discovery.ps1
        Classification.ps1
        FirewallRead.ps1
        ProcessRead.ps1
        FirewallPlan.ps1
        FirewallApply.ps1
        FirewallRollback.ps1
        Evidence.ps1
    tests/
      Fixtures/
      Unit/
      Integration/
    .github/workflows/
      static-qa.yml

Mantener 1 único motor de negocio; separar la UI de la lógica. No incluir binarios de Autodesk, claves de licencia ni WebView2 Runtime redistribuido. CI automático estático + pruebas unitarias, pero ejecutar integración de firewall **solo** en Windows aislado, nunca sobre máquinas de runners compartidas.

## 10. Matriz de criterios de aceptación y semáforo

| Riesgo | Umbral para PASS | STOP/BLOCKED |
|---|---|---|
| Falso positivo de clasificación | Exact path + identidad comprobada; no depende solo de nombre | Rutas ambigüas |
| Duplicados | 0 tras segunda ejecución | Más de una regla propia mismo path/Out |
| Reversión | 100% de reglas PROPIAS restauradas/removidas conforme manifest | Regla ajena afectada |
| WebView2 terceros | 0 reglas globales nuevas y conectividad WhatsApp/Outlook comprobada | Cualquier interferencia de otras apps |
| Verificación | Resultado distingue configurado / efectivo observado / no probado | Declarar «total» solo por conteo |
| Integridad y AV | Antivirus ON, scripts auditables | Requerir exclusiones o apagar AVG |
| UX | UI no congela, progreso real y final después de lectura | Ventana «No responde» sin feedback |
| Privacidad | Reportes públicos sanitizados, originales locales | Registro bruto personal en repo público |
| Soporte de versiones | 2023–2027 catalogados; instalado probado, no instalado = NO PROBADO | Afirmar 5/5 sin 5 pruebas |
| Mantenimiento | Revalidación tras update EXE/EdgeWebView y reboot | Reglas obsoletas presentadas como vigentes |

## 11. Riesgos y decisiones adicionales

- **Licencias/autenticación:** no prometer que AutoCAD seguirá funcionando siempre offline. No incluir parches de licencia, manipulación de tokens, cambios de servidores de activación ni supresión de controles de verificación.
- **ProgramData y AppData:** su presencia en un catálogo de descubrimiento no los convierte en objetivos de bloqueo; comúnmente contienen datos, scripts o cachés.
- **Antivirus:** el código anterior fue señalado por AVG; no suponer falsos positivos. No deshabilitar protección.
- **Persistencia no deseada:** tarea histórica SYSTEM repetida por hora puede recrear reglas; F0 la detecta, F2 ofrece pausa segura con backup tras confirmación.
- **Nombres de reglas externos:** el proyecto sawyermade usa dos nombres idénticos para todos los EXE. No borrarlos en bloque; recuperar filtro por filtro.
- **Actividad de red indirecta:** proxy/servicio compartido o navegación WebView2 pueden hacer que una ruta Autodesk bloqueada no cubra todo el tráfico.
- **Observabilidad:** capturas periódicas TCP no prueban ausencia de tráfico. Combinar instantáneas, pruebas controladas y auditoría WFP opcional, sin atribuir toda actividad de un servicio compartido a AutoCAD.
- **Manejo de errores:** una inspección que falle no equivale a cero resultados; usar ERROR/PARCIAL y conservar traza.
- **Separación internet/LAN:** una regla Outbound Block -Program -Profile Any no distingue internet de red local; el UI debe aclarar que bloquea conexiones salientes incluidas LAN. No prometer «solo internet» sin diseñar alcances de direcciones.
- **Políticas corporativas:** ActiveStore puede contener GPO que el usuario no tiene permiso de cambiar. Nunca sugerir alterarlas por la fuerza.

## 12. Contrato de evidencias y checkpoints

Por fase: docs + código + pruebas + evidencia (JSON resumido saneado + TXT humano) + SHA256 + decisión PASS/PARTIAL/BLOCKED + NEXT. Estado en un solo archivo PROJECT_CONTINUITY_CURRENT.md, actualizado al aprobar la fase. README y SPEC maestra deben actualizarse antes de cada cambio de runtime; no trabajar contra borradores divergentes.

Los PRs son Draft hasta QA real en Windows. Nada de fusionar automáticamente o declarar release solo por CI verde. La documentación de fuentes externas y decisiones debe estar versionada.

**NEXT:** diseñar e implementar F0 sobre una rama aislada. Recopilar opcionalmente un informe histórico guardado en C:\parchecad\informes para completar la lista comprobada de las 96 reglas. No recrear esos 96 bloqueos antes de terminar F0.

## 13. Fuentes revisadas

**Código externo revisado, no copiado:**
- https://github.com/sawyermade/autodesk-blocker/blob/master/README.md
- https://github.com/sawyermade/autodesk-blocker/blob/master/discover.ps1
- https://github.com/sawyermade/autodesk-blocker/blob/master/block.bat
- https://github.com/sawyermade/autodesk-blocker/blob/master/block-list.bat
- https://github.com/sawyermade/autodesk-blocker/blob/master/status.bat
- https://github.com/sawyermade/autodesk-blocker/blob/master/unblock.bat
- https://github.com/sawyermade/autodesk-blocker/blob/master/CLAUDE.md

**Microsoft:**
- https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule
- https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallapplicationfilter
- https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallrule
- https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/process-model
- https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/filter-origin-documentation
- https://learn.microsoft.com/en-us/windows/win32/fwp/basic-operation

**Autodesk:**
- https://www.autodesk.com/support/technical/article/caas/sfdcarticles/sfdcarticles/Microsoft-Edge-can-t-read-and-write-to-its-data-directory-when-launching-AutoCAD-2023.html

**Origen propio:** capturas y scripts aportados en esta conversación. No publicar registros privados ni binarios previos sin autorización y auditoría de seguridad.

---
**Veredicto de 10 pasadas:** la arquitectura de diagnóstico y control selectivo es viable; la promesa de bloquear exclusivamente WebView2 de AutoCAD con el firewall tradicional **NO está demostrada**. La siguiente actividad es F0, no recrear indiscriminadamente reglas antiguas.
