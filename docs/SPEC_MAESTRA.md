# SPEC MAESTRA — ParcheCAD 4.3 (vigente)

**Estado:** desarrollo en rama Draft · NO RC1 ni release · Windows / AutoCAD 2023–2027.  
**Fuente de verdad:** código y pruebas del repositorio. Los informes de etapas F0–F16 quedan en Git, pero no son la arquitectura actual. QA integrada: `docs/F17_PROTOCOLO_QA_INTEGRADA.md`. Auditoría de interfaz: `docs/V43_DASHBOARD_WPF.md`.

## Objetivo y límites

ParcheCAD identifica ejecutables reales de AutoCAD, presenta reglas de firewall existentes y permite una operación reversible por ejecutable autorizado. **Separadamente**, observa WebView2 y su posible relación con AutoCAD sin bloquear componentes compartidos de otras aplicaciones.

- **Regla instalada != tráfico demostrado bloqueado.** El tráfico debe verificarse en red bajo condiciones reales para afirmar efectividad.
- **Bloquear tráfico != impedir ejecución de WebView2.** Un firewall por archivo no distingue dos instancias del mismo runtime Microsoft según PID o proceso padre.
- **No afirmar cobertura total:** AutoCAD/Autodesk pueden utilizar procesos compartidos, proxies, servicios, IPv4/IPv6 o UDP no medidos. Reportar PARCIAL / NO VERIFICADO.
- **No modificar licenciamiento, antivirus, software ajeno o GPO.** El bloqueo puede degradar funcionalidades y comprobaciones de suscripciones legítimas. No recomendarlo en equipos principales sin aceptación.

## Arquitectura KISS ejecutable

```text
Abrir_ParcheCAD.cmd
  src/ParcheCAD.Dashboard.xaml      Diseño WPF
  src/ParcheCAD.Dashboard.ps1       Estados / acciones / progreso
  src/ParcheCAD.Preview.ps1         Plan AutoCAD SOLO LECTURA (proceso hijo)
  src/ParcheCAD.WebViewAudit.ps1    Auditoría WebView2 SOLO LECTURA
  src/ParcheCAD.Monitor.ps1         Monitor temporal observacional
  src/ParcheCAD.Reglas.ps1         Apply/Rollback UAC + confirmación
  src/ParcheCAD.*.ps1              Motores compartidos de detección, firewall y QA
Abrir_ParcheCAD_Clasico.cmd        Respaldo WinForms temporal, no una nueva línea de producto
```

PowerShell 5.1 en Windows, WPF nativo sin instalación de otros runtimes, servicios residentes, drivers, tareas programadas, bases de datos, frameworks UI o descarga de módulos en ejecución. Mismo diseño responsive en ventanas grandes y pequeñas; el scroll vertical garantiza accesibilidad.

## Firewall AutoCAD — contrato inviolable

1. Construir catálogo con instalaciones AutoCAD **reales** (2023–2027) y rutas locales existentes; no inventar una lista fija histórica de ejecutables. Excluir ejecutables Autodesk compartidos y Microsoft WebView2.
2. Rechazar truncamientos peligrosos del catálogo, rutas UNC/enlazadas/symlinks/junctions, rutas fuera de instalación y conflictos. No continuar por asumir un resultado ausente como OK.
3. Vista previa de solo lectura: fases, temporizador y cancelación exclusivamente de su proceso hijo. No depende del auditor WebView2.
4. Apply: un **motor administrativo independiente** revalida el catálogo, rutas, reglas, filtros y recuperación antes y después de las confirmaciones. Requiere UAC y palabra escrita. Un fallo aborta sin fingir éxito.
5. Una regla propia incluye dirección saliente, EXE exacto y filtros efectivos amplios `Any` (protocolo, puertos, IP, servicio e interfaz). Una coincidencia parcial o inspección fallida es CONFLICT / ERROR_INSPECCION, no `EXISTS_VALID`.
6. Journals `PCAD4_...` respaldan cada cambio propio. Los respaldos nuevos viven en `%ProgramData%\ParcheCAD\Operations`, independientes del directorio extraído. Registro incompleto, corrupto, `.pending` o huérfano bloquea nuevas aplicaciones. La restauración sin respaldo verifica firma persistente PCAD4 y todos los filtros; reglas externas requieren selección explícita y exportación previa de la política. Nunca borrar reglas a ciegas.
7. Un exit code administrativo 0 representa **proceso terminado**; solo una comprobación de journal y del estado efectivo puede confirmar operación local. Ninguna de ellas demuestra aislamiento universal de red.

## WebView2 y monitor — contrato inviolable

- Auditoría por procesos, árbol, tiempos y conexiones observadas: atribución solo PROBABLE/INDETERMINADA cuando no es demostrable. La ausencia de conexiones en instantánea no prueba que no existieran.
- `msedgewebview2.exe` compartido tiene `AutomaticFirewallEligible=false`: ninguna regla global basada en PID, padre o una ruta compartida.
- Monitor read-only temporal de hasta 10 minutos. Registra solo campos saneados de procesos/puertos/tipos, no URL, IP, tokens o rutas privadas completas; el muestreo no capta todos los eventos breves.
- Detener de forma cooperativa mediante señal; salir con monitor activo solicita guardar y se cierra tras finalizar el worker. El proceso AutoCAD no se termina.

## UX y trazabilidad

- Una función visual de estados evita punto verde en error, falso 100 % en informe parcial y confusión entre finalización y éxito.
- Botones separan claramente Ver reglas / Auditar WebView2 / Monitor de Aplicar (acción de riesgo), con progreso indeterminado donde no hay porcentaje real.
- Interfaz WPF adaptable a ventanas y DPI; etiquetas multilínea, contraste y navegación de teclado.
- Informes JSON/TXT sanitizados, marcadores de salida coherentes y directorios de sesiones únicos. Nunca subir informes privados completos sin inspección.

## QA y puerta de salida (NO AUTOCERTIFICACIÓN)

- En CI: PowerShell 5.1/7, parser/fixtures, workers empaquetados extraídos, hashes SHA256 deterministas, ejercicio sintético de firewall e integridad NetSecurity, recuperación y visualización WPF offscreen; sin afirmaciones sobre AutoCAD real.
- Evaluación F12/F17 mantiene diez puertas: DIAGNOSTICOS, AUTOCAD_INSTALADO, REGLAS_SALIENTES, TRAFICO_AUTODESK, WEBVIEW2_AUTOCAD, OTRAS_APLICACIONES, GUI_UAC, REINICIO_Y_ROLLBACK, AVG_ACTIVO y AUTOCAD_FUNCIONAL. `Decision=BLOCKED` y `ProductionCertified=false` sin evidencia externa verificable.
- Pendientes: escritorio real Windows con DPI/zoom y texto largo, operación autorizada con AutoCAD genuino, trazas TCP/UDP IPv4/IPv6, GPO/AVG activo, otras aplicaciones intactas, reinicio y rollback comprobado.
- Sin aprobación explícita: **no merge a main, no release, no publicación como producción, no aplicación de reglas reales**.

## Leyes y mantenimiento

**KISS / anti-ruido / no parches / diseño humano.** Solo añadir elementos que demuestren valor concreto; corregir causa raíz en su módulo, pruebas focales y QA integral una vez. Mantener documentación vigente (este archivo, README, V43, F17) en ZIP; el historial F0–F16 se conserva en Git. La interfaz WinForms clásica se retirará en una sola limpieza cuando WPF apruebe prueba interactiva; no retirarla antes.

### Fuentes técnicas
- https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/rules
- https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/process-model
- https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/user-data-folder


## Accesos de la interfaz compacta

Los botones de consulta se denominan **Analizar firewall** y **Analizar WebView2** para aclarar que son consultas de solo lectura. El acceso **Bloqueo general AutoCAD** en la pestaña WebView2 reutiliza la misma función elevada del firewall de AutoCAD, sin analizar WebView2 y sin instalar reglas sobre `msedgewebview2.exe`. **Restaurar Firewall** y **Restaurar WebView2** son las únicas dos operaciones de recuperación visibles. Cada una analiza las reglas persistentes del firewall y ofrece restauración confirmada: la primera recupera reglas PCAD4 de firma exacta sin carpeta/JSON, o una regla AutoCAD seleccionada expresamente; la segunda necesita el filtro `msedgewebview2.exe` y **además** un ID/nombre históricamente ligado a Autodesk/ParcheCAD (los prefijos SGC/PCAD genéricos necesitan también etiqueta explícita Autodesk). Reglas WebView2 genéricas se excluyen. La vinculación histórica no demuestra aislamiento por aplicación y el retiro puede afectar otros usuarios del runtime compartido. Previamente se exporta política .wfw, se registra la transacción fuera del programa y se revalidan filtros, sin eliminar reglas por aproximación. Las reglas GPO, antivirus, tareas, HOSTS y configuración de Edge/WebView2 no se reparan con estas acciones.
