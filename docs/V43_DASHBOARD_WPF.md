# ParcheCAD — Auditoría V4.3, 10 pasadas y plan único KISS
**Fecha:** 2026-10-26 · **Alcance:** PR #22, HEAD c78c54e1613ac3142c083d3ed2860ff367688da4 (antes de este documento)  
**Decisión:** V4.3 NO aprobada visualmente ni como RC1. Plan de corrección integral, sin parches superpuestos ni frameworks nuevos.

## Leyes de trabajo (obligatorias)
1. **KISS:** una interfaz WPF + PowerShell 5.1 STA + motores CLI ya existentes. No introducir Electron, React, servicios, drivers, nuevo runtime, MVVM/C# por defecto ni frameworks para un panel local.
2. **Anti-ruido:** cada elemento se conserva, integra, optimiza o elimina con evidencia. No producir otra colección de documentos Fxx, wrappers, copias de UI o pruebas circulares. Este documento reemplaza la antigua guía V43, no abre otro historial.
3. **No parches:** resolver la causa raíz (medición y diseño adaptable) en XAML y el controlador WPF existente, no correcciones por posición o DPI, ni reestilizar WinForms.
4. **Diseño humano:** priorizar tareas, lenguaje simple, estados veraces, controles legibles, teclado, contraste y tamaños variados. La interfaz debe ajustarse a la pantalla y no exigir que el usuario se adapte a ella.
5. **Seguridad:** NO bloquear msedgewebview2.exe global; no modificar Windows durante auditoría; Apply/Rollback solo con UAC, validación independiente, palabra escrita y journal. Un PID probable no prueba aislamiento.

## Evidencia y límites
- Árbol GitHub en PR #22 y ZIP DEV de CI #151 SHA-256 ee3dc0ec77749610113fa2e004129ce931e6f3d6da54bd8cf76c211bc78f0090; 45 archivos + manifiesto; sha256sum -c PASS.
- CI #151: cuatro suites PASS (Windows PowerShell 5.1 y 7, empaquetado extraído, firewall sintético con recuperación); prueba XAML SelfTest y render WPF offscreen a 96 DPI.
- Captura del render CI: bonita a un ancho fijo, pero NO sustituye captura de escritorio real, ni prueba el comportamiento al escalar o reducir ventana. El usuario informa texto montado y cortado; el código muestra causas estructurales plausibles, sin atribuir un elemento exacto sin reproducción de pantalla.
- Referencia externa: https://github.com/nextlevelbuilder/ui-ux-pro-max-skill — en especial data/stacks/wpf.csv (reglas 13–18, 42–47) y data/ux-guidelines.csv (feedback de carga, acceso, estados, legibilidad). Adoptar principios, NO copiar mecánicamente recomendaciones específicas de aplicaciones WPF compiladas: XamlReader + PowerShell no exige x:Class ni MVVM.
- No hay ejecución GUI/UAC de AutoCAD real ni comprobación del bloqueo efectivo en la máquina del usuario. RC1 sigue bloqueada.

## Diez pasadas independientes y verificables

### 1. Identidad, entrega e integridad — PASS acotado
Árbol de la rama auditada y ZIP consistentes; 45 entradas manifestadas, hashes PASS. Dos launchers: Abrir_ParcheCAD.cmd (WPF) y Abrir_ParcheCAD_Clasico.cmd (WinForms). NO modificar main ni eliminar respaldo durante auditoría.
**Decisión:** conservar launcher principal; respaldo clásico temporal con salida documentada.

### 2. Motor de bloqueo y alcance de ejecutables — PASS de guardas; QA real PENDIENTE
src/ParcheCAD.Reglas.ps1 líneas 32–60: catálogo de instalaciones reales y validación previa; rechaza catálogo incompleto, cero candidatos, conflictos; UAC y REQUIERE escribir APLICAR. src/ParcheCAD.Policy.ps1 evita ejecutables compartidos; src/ParcheCAD.Firewall.ps1 vuelve a validar rutas y filtros, registra cada transición.
La vista previa de 31 candidatos/0 conflictos reportada por el usuario NO implica que se crearon reglas ni que todas las conexiones se bloquearon.
**Decisión:** conservar este motor; no reemplazar por lista fija supuesta ni mezclarlo con auditoría WebView2.

### 3. Reversión y respaldo — GUARDAS PRESENTES; feedback gráfico incompleto (P1)
Reglas propias PCAD4_MANAGED, manifiesto PCAD4_<guid>.json y rollback que no retira reglas alteradas/no propias (Firewall.ps1 46–80, 97–153).
Dashboard.ps1 líneas 309–316 solo muestra el código de salida del proceso elevado; no interpreta el journal final ni ofrece resultado comprobado de aplicadas/revertidas. Una operación administrativa puede producir estado parcial; no convertir «terminó» en «aplicó».
**Decisión:** conservar motor; mostrar «Operación terminada — revisa el journal» y manifestar estados exactos sin afirmar éxito ficticio.

### 4. Procesos, monitor y cancelación — HALLAZGO P1
Los workers de solo lectura (preview y auditoría) viven fuera del hilo WPF: buena decisión. Cancelar mata solo su proceso, no AutoCAD ni la consola elevada.
Dashboard.ps1 327–350: al cerrar con monitor activo se cancela Closing y se envía solicitud de parada, pero al terminar el monitor la ventana no se cierra automáticamente; el usuario debe repetir Salir. Fallos de cierre/stop y lanzamientos simultáneos requieren prueba de carrera.
**Decisión:** unificar el ciclo de vida de la sesión: cerrar solicitado -> parar monitor una vez -> esperar reporte -> cierre único, con fallo visible. Sin servicios de background ni temporizadores adicionales.

### 5. Modelo de estados y confianza del usuario — HALLAZGO P1
Dashboard.ps1 55–58 actualiza texto de badge pero NO StatusDot/color: «CONFIRMACIÓN REQUERIDA», error o consulta pueden mantener punto verde. 124–140: Progress=100 aunque resultado PREVIEW_PARCIAL; estado parcial reconocido en texto, pero color/progreso pueden inducir error. 310–316: final administrativo equivale a «terminado» sin certificar efectos.
**Decisión:** una sola función de representación de estado (IDLE, CONSULTING, PREVIEW_OK, PARTIAL, ERROR, MONITORING, APPLY_AWAIT_CONFIRM, ADMIN_FINISHED_UNVERIFIED), que controle texto, color y botones; NO nueva capa de negocio.

### 6. Tamaños reales, DPI y textos cortados — HALLAZGO P0, causa raíz
Dashboard.xaml líneas 3–5: Window Width=1170 Height=875 MinWidth=1040 MinHeight=750, imposible de acomodar entero en ciertos tamaños lógicos con escalado Windows 125–200 %. Ejemplo: 1366 px a 150 % son ~911 unidades independientes de dispositivo de ancho, menores que MinWidth=1040. Línea 55 desactiva scroll horizontal; otros elementos no tienen reflujo.
Líneas 66–105: cuatro cards fijas en UniformGrid Columns=4; 112–155: dos paneles de trabajo en columnas fijas; líneas 127–150: dos acciones en una fila; líneas 191–199: pie con tres anchos fijos. Textos de cabecera/pie sin wrapping ni Trimming.
**Decisión:** reconstruir SOLO el layout XAML actual con Grid/Auto/*, sin posiciones absolutas; límites adecuados a WorkArea; cards 4/2/1 por ancho real; paneles dos/uno; botones fluidos, contenido multilínea sin recortes; pie siempre accesible con scroll vertical. Nunca «arreglar» posiciones por porcentajes de DPI.

### 7. Accesibilidad, contraste y legibilidad — HALLAZGO P1
Cálculo sRGB: #169256 con blanco ≈3.98:1 (CTA verde; texto de 13 DIP), pie #8592A5 sobre #F5F7FB ≈2.94:1 (texto de 11 DIP). Ambos incumplen referencia 4.5:1 para texto normal. Tema con HEX fijos sin adaptación al alto contraste; botones usan ControlTemplate personalizado sin FocusVisualStyle explícito ni etiquetas de AutomationProperties para estados. Escalado/lectores no comprobados.
**Decisión:** 5–7 tokens semánticos en Window.Resources, verde más oscuro con >=4.5:1, pie >=4.5:1, foco visible, nombres accesibles, mensajes que no dependan solo del color, evaluar Windows High Contrast, tab/Enter/Escape. No descargar fuentes ni iconotecas.

### 8. Sistema visual y lenguaje humano — HALLAZGO P1
El diseño offscreen WPF se acerca más al mockup que WinForms, pero tiene múltiples mensajes técnicos («bloqueables automáticamente», «atribución por PID», «candidatas») en primer plano, titulares largos y regiones con poca jerarquía. Botón «Verificar y aplicar» parece acción inmediata cuando la consola elevada vuelve a verificar y exige confirmación.
**Decisión:** conservar 2 tareas primarias «Revisar reglas AutoCAD» y «Analizar WebView2»; separar «Aplicar reglas» claramente como acción de riesgo, con microtexto «requiere confirmación»; mostrar detalles técnicos en informe expandible; resumen legible (resultado, próximo paso, seguridad). Iconos WPF vectoriales simples solo si añaden significado, nunca decoración excesiva.

### 9. Arquitectura y anti-ruido — HALLAZGO P1
La rama incluye dos UI completas: src/ParcheCAD.Panel.ps1 (aprox. 56 KB) y Dashboard.ps1 (aprox. 18 KB) + XAML (aprox. 14 KB), con dos entrypoints, estados y pruebas de interacción duplicados. Repo conserva muchos informes técnicos F0–F17 y README acumulativo, pero no se deben borrar evidencias sin comprobar referencias.
**Decisión:** durante la validación mantener el fallback; después de una prueba real WPF sin regresiones, borrar en UN SOLO cambio atómico UI clásica, launcher clásico y sus tests exclusivos, limpiando referencias de Build/CI/README; nunca quitar motores o pruebas de firewall/recovery por su nombre Fxx. Mantener README + SPEC maestra + UNA guía QA vigente, y referencias a historial en Git.

### 10. Pruebas, empaquetado y puerta de salida — HALLAZGO P0/P1
CI #151 4/4 PASS acredita XAML load, código empaquetado, integración previa de WinForms y firewall efímero; NO prueba controles WPF con click real, UAC, DPI, maximización, textos extensos, keyboard-only, recortes ni veracidad del journal. Render WPF usa ejemplo sintético y tamaño fijo, no equivalencia exacta con ventana real.
**Decisión:** un gate pequeño de regresión VISUAL + funcional: Windows en 100/125/150/200 %, resolución baja y normal, texto largo, sin overlay, tests de control/estado, cancelación, cierre y salida. Mantener una prueba empaquetada con hash y los tests de seguridad existentes. RC1 BLOCKED mientras falten AutoCAD real/UAC/rollback autorizados.

## Plan de implementación: 3 lotes, sin fases infinitas

### Lote A — P0: corregir diseño en la raíz (obligatorio primero)
**Archivos:** src/ParcheCAD.Dashboard.xaml, quizá ajustes mínimos en Dashboard.ps1.
1. Sustituir min-size rígido por dimensionado basado en espacio útil y layout adaptable; una zona vertical scroll segura, ningún corte horizontal.
2. Reflujo: tarjetas 4/2/1, bloques 2/1 y acciones de 2 a 1 columna según espacio disponible. Usar tamaños naturales y TextWrapping, no offsets manuales. No crear un motor de responsive ni framework externo.
3. Estilo coherente: tokens, contraste, botones sin desbordes, foco, textos breves, prioridad visual por tarea. Los indicadores deben ser comprensibles sin interpretaciones técnicas.
**Gate A:** comparativos con mockup original y capturas Windows 100/125/150/200 %; 0 cortes, solapamientos o botones inaccesibles. Conserva mismo comportamiento funcional.

### Lote B — P1: un solo controlador de estados y cierre
**Archivo:** src/ParcheCAD.Dashboard.ps1 (NO tocar motores salvo defecto confirmado).
1. Función pequeña y única que derive colores, textos, progreso y habilitación de acciones desde estado real, sin flags redundantes.
2. Monitor: un cierre cooperativo idempotente y confirmación del informe; cancelar exclusivamente hijo de lectura.
3. Operación elevada: comunicar terminación vs confirmación de éxito, permitir abrir journal sin exponer rutas en logs compartibles.
4. Mejorar textos humanos, validaciones de marcador/JSON, errores visibles y acción de recuperación segura.
**Gate B:** pruebas de estados: parcial/error/cancelar/repetir/exit, monitor activo y elevado, sin procesos huérfanos ni afirmaciones falsas.

### Lote C — P1/P2: QA y retiro de ruido sustentado
**Archivos:** prueba WPF focal, workflow QA, Build, README, esta guía V43.
1. Un solo script de QA que renderice y compruebe geometría/content bounds de elementos críticos y evidencia visual; complementar con prueba interactiva real en el PC. No crear 10 suites casi idénticas.
2. Mantener suites actuales CLI, recovery, F4/F13 y ZIP/SHA; ejecutar QA integral UNA vez tras validar candidatos.
3. Cuando WPF supere aceptación real, eliminar WinForms de respaldo y sus pruebas exclusivas en una sola limpieza controlada; NO borrar mecanismos de seguridad ni evidencias necesarias.
4. Actualizar README/SPEC con la versión vigente; consolidar documentación sin duplicar históricos.
**Gate C:** CI 4/4 GREEN en HEAD final + QA visual real + no regresiones firewall/monitor, diff sin archivos innecesarios.

## Riesgos y bloqueos de entrega
- **No release ni merge:** la interfaz real en Windows del usuario y matriz DPI aún no pasan.
- **Firewall:** 31 candidatas/0 conflictos son resultado de vista previa anterior, NO una autorización para bloquear ni evidencia de tráfico denegado.
- **WebView2:** bloqueable de modo selectivo por PID = NO; mantener runtime Microsoft compartido fuera del plan.
- **Permisos:** Apply/Rollback solo con UAC y confirmaciones existentes. Verificación de funcionamiento real, recuperación, suscripción/licencia y tráfico sigue pendiente.
- **No más capas:** si una mejora requiere un framework, antes demostrar por qué no cabe en WPF/XAML + las funciones actuales.

## Lote B — Ejecución y auditoría focal (2026-10-26)

**Causa raíz en WPF:** `PCAD-Status` actualizaba solo texto (no color del estado); `PCAD-CompleteChild` llevaba la barra al 100 % incluso para informes parciales; el cierre con monitor activo cancelaba el cierre pero exigía otro clic al finalizar.

**Corrección (solo Dashboard.ps1):** presentación de 10 estados reconocidos en una única función `PCAD-Status`, que sincroniza badge, indicador circular, pestaña de resultados y colores; porcentaje 100 solo tras una vista previa o auditoría comprobada, cero cuando parcial/error/cancelado. Al pulsar salir con monitor activo se anota intención, se solicita parada cooperativa (reintento si el worker aún crea su carpeta) y al terminar y recoger el log se cierra automáticamente sin matar AutoCAD. Durante el cierre se deshabilitan nuevas acciones. Si hay operación elevada activa no se cierra y se informa que todavía no terminó. Un proceso administrativo con código 0 **no** certifica bloqueo; exige verificar journal y reglas, código distinto de cero indica error.

**Gate automatizado:** `-StateSelfTest` recorre diez estados visuales sin abrir escritorio, verifica color/texto/result-tag/progreso y bloqueos de controles en cierre. Conservar el QA existente de PowerShell, monitor/paquete/firewall; pruebas de cierre real interactivo siguen pendientes en equipo del usuario. Ningún cambio en módulos de reglas, políticas, WebView2 o monitor.

## Prioridad operativa inmediata
**SIGUIENTE: CHATGPT (no Codex):** ejecutar Lote C con validación focal e inventario de ruido tras el Lote B; no retirar la UI clásica sin aceptación interactiva en Windows del usuario.


## Lote C — consolidación de ruido en el artefacto (2026-10-26)

**Hallazgo real:** el ZIP de desarrollo incluía 19 archivos de reportes y documentación de versiones históricas, además de la guía de continuidad antigua. Esto no hace funcionar el software ni ayuda al usuario. El código fuente y la trazabilidad NO se eliminan del repositorio.

**Decisión KISS:** el ZIP de instalación técnica contiene un README actual, SPEC maestra, guía QA vigente V43 y protocolo F17; motores y scripts de recuperación completos, launcher WPF y respaldo WinForms. Las 19 fuentes documentales antiguas siguen en Git para auditoría, pero ya no se distribuyen en el paquete. No se añade un sistema de migración de documentos ni otra app.

**QA sin duplicaciones:** test F6 comprueba los documentos activos, ausencia de históricos en ZIP, launcher WPF empaquetado con Mark-of-the-Web, estado y seguridad de workers, fallback WinForms y SHA determinista. El renderer WPF añade escenarios de texto largo/cambio de escala tipográfica, aclarando que no sustituye DPI físico. Mantener QA de firewall existente sin repetir suites.

**Retiro definitivo de WinForms:** BLOQUEADO hasta aceptación interactiva WPF en equipo Windows con AutoCAD y reversión autorizada. En un único commit futuro se retirarán launcher clásico, Panel.ps1, UIState.ps1, pruebas exclusivas y referencias de Build/CI/README; no borrar el motor ni pruebas de seguridad.


### Lote D — Reorganización compacta solicitada por el usuario

**Causa:** el dashboard A/B/C necesitaba scroll para llegar a las acciones o a los informes, porque dos paneles funcionales, el estado y todos los registros se presentaban simultáneamente. **Decisión KISS:** sin reescribir motores ni introducir pantallas adicionales, concentrar Firewall y WebView2 en dos pestañas de un solo TabControl WPF; mantener métricas siempre arriba, actividad debajo y detalles en un Expander contraído. Ya no mostrar los dos grupos de acciones al mismo tiempo.

**Comportamiento:** los procesos de consulta, auditoría y monitor mantienen sus marcadores e informes; al iniciar una operación el frontend selecciona la pestaña correcta. Los detalles no se abren automáticamente para no forzar desplazamiento. Pantalla nominal 1050×665 DIP sin scroll; en resolución/DPI pequeños se conserva desplazamiento vertical únicamente como medida de accesibilidad. Se reemplaza el render de 7 vistas históricas por **una prueba focal** de seis escenarios (normal, grande, media, pequeña, angosta, estrés de texto), con verificación de botones de ambas pestañas, detalles inicialmente plegados y ausencia de scroll nominal. El fallback WinForms se conserva hasta QA real. Sin cambios en firewall, rollback, conexión o atribución WebView2.


### Cambio de lenguaje y acceso directo solicitado

Se renombra **Ver reglas → Analizar firewall** y **Auditar → Analizar WebView2**. En la pestaña WebView2 se añade un acceso al **Bloqueo general AutoCAD** (mismo controlador y gates existentes, sin inspección WebView2 requerida) y una acción informativa de **estado/restauración WebView2**, puesto que ningún bloqueo de runtime compartido ha sido instalado por ParcheCAD. No se crea un falso bloqueador por PID ni se altera Microsoft WebView2. El acceso explica explícitamente que no modifica el runtime ni restaura reglas externas. Esto conserva una sola función de aplicación, una sola reversión real y una sola fuente de verdad para permisos.


## Restauración autosuficiente — una acción por categoría (2026-10-27)

**Exigencia del usuario:** no presentar varios botones «por si acaso». **Solo `RESTAURAR FIREWALL` y `RESTAURAR WEBVIEW2`.** Cada uno primero revisa las reglas actuales del almacén local de Windows Firewall y, dentro de la misma operación, permite recuperar tras consentimiento; no es necesario encontrar una carpeta ParcheCAD o JSON antiguo.

- Firewall: identifica estructura `PCAD4_A_<24hex>_OUT`, `PCAD4_MANAGED`, ruta EXE original, año AutoCAD y filtros completos. Reglas ajenas de AutoCAD pueden recuperarse solo mediante selección por nombre exacto; nunca eliminarlas en lote.
- WebView2: exige tanto filtro `msedgewebview2.exe` como ID/nombre histórico ligado expresamente a Autodesk. Prefijos genéricos SGC/PCAD solo son elegibles si su etiqueta visible confirma Autodesk; reglas globales y ajenas quedan excluidas. El nombre es indicio, no certificación de autoría o exclusividad; una regla WebView2 compartida puede afectar a otras aplicaciones. Requiere ID exacto y confirmación.
- Antes de quitar: `netsh advfirewall export` a `%ProgramData%\ParcheCAD\Recovery\PolicyBeforeRestore_*.wfw`, journal atómico y nueva verificación de estado. No se importa automáticamente la exportación, porque reemplazaría otras reglas del equipo.
- Los respaldos nuevos de Apply se escriben en `%ProgramData%\ParcheCAD\Operations`, sobreviven a borrar la carpeta de instalación. El navegador de informes puede permanecer local.
- Fuera de alcance: GPO, cambios de antivirus, servicios Windows, hosts, reglas sin programa verificable y restauración física del runtime Microsoft. Marcar esas causas como «NO VERIFICADAS», no fingir restauración total.

**QA:** reglas sintéticas de AutoCAD y WebView2 exclusivamente en runner Windows efímero; probar reglas PCAD4 huérfanas, identidad de grupo ajena, exportación antes de eliminación, selección por nombre y desaparición verificada. Motor existente de Apply y recuperación normal sin reescritura.

### Gate anti-desbloqueador-general

El restaurador WebView2 NO debe admitir reglas por la ruta del ejecutable únicamente. El test Windows real debe crear en la misma ruta una regla histórica explícitamente vinculada a Autodesk y otra genérica. Solo la vinculada puede seleccionarse y retirarse; la genérica permanece intacta. Rechazar además un prefijo SGC con descripción genérica. Mantener dos botones, sin nuevos módulos ni historial obligatorio.
