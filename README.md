# ParcheCAD 4.3 — Firewall AutoCAD y auditoría WebView2

Aplicación local para Windows y AutoCAD 2023–2027, construida con PowerShell 5.1 y WPF. **Versión de desarrollo, NO RC1 ni release certificado.**

## Abrir y utilizar (sin instalar)

1. Extrae el ZIP completo en una carpeta propia, por ejemplo `C:\ParcheCAD_4.3`. No ejecutes los scripts sueltos desde dentro del ZIP.
2. Ejecuta **`Abrir_ParcheCAD.cmd`**. Se abrirá el tablero WPF; no modifica el firewall al iniciarse.
3. **Ver reglas AutoCAD:** inventaría ejecutables de instalaciones locales, revisa rutas, conflictos y filtros en un proceso de solo lectura; puede tardar mientras muestra progreso y permite cancelar.
4. **Auditar WebView2:** detecta procesos y conexiones observables, clasifica su relación probable con AutoCAD y protege el runtime compartido de Microsoft. Una atribución probable **NO** permite bloquearlo automáticamente.
5. **Iniciar monitor:** observa temporalmente TCP, endpoints UDP y procesos (máximo 10 minutos). Pulsa detener para guardar el informe; el registro tampoco certifica aislamiento ni ausencia de tráfico.
6. **Abrir informes:** consulta los JSON y resúmenes locales. Inspecciónalos antes de compartir: pueden contener metadatos de procesos y equipos.

**Aplicar o revertir reglas:** el motor administrativo sigue disponible, pero **NO se recomienda probarlo en el computador principal** mientras el producto carezca de QA real con AutoCAD, UAC y recuperación verificada. Si se utiliza en un laboratorio autorizado, exige UAC, confirmación escrita, comprobaciones de rutas/filtros/conflictos y respaldo. Un código de salida 0 no demuestra por sí solo que toda conexión esté bloqueada.

Si WPF no abre, usa **`Abrir_ParcheCAD_Clasico.cmd`** como respaldo temporal. No desactives AVG/Defender ni las políticas de seguridad del equipo.

## Qué bloquea y qué no

- El firewall trabaja sobre **ejecutables de AutoCAD identificados y verificados localmente**. Una vista previa como «31 candidatas, 0 conflictos» no significa que haya 31 reglas aplicadas.
- **No instala un bloqueo global de `msedgewebview2.exe`**: WhatsApp, Outlook y otros programas pueden compartir ese ejecutable. El PID o proceso padre no permite una regla persistente exclusiva.
- Un bloqueo de red puede afectar funciones online y licencias legítimas de AutoCAD, y **no impide necesariamente que WebView2 se ejecute**.
- Los sondeos del monitor no capturan todas las conexiones breves, por lo que no certifican aislamiento completo.

## Arquitectura y seguridad

Interfaz única principal **WPF/XAML** + scripts PowerShell existentes. Vista previa y auditoría en procesos separados y cancelables; monitor de duración limitada; reglas y recuperación separadas y elevadas solo con consentimiento. Ningún servicio residente, controlador, dependencia externa ni modificación permanente de ExecutionPolicy. Las políticas obligatorias del equipo tienen prioridad.

**Leyes del proyecto:** KISS, anti-ruido (eliminar, integrar o mejorar con evidencia), no parches sobre parches y diseño legible/adaptable. Git conserva el historial técnico; el ZIP incluye únicamente las piezas ejecutables y documentos vigentes.

## Estado y documentación

Las pruebas de CI incluyen PowerShell 5.1/7, paquete reproducible SHA-256, reglas temporales sintéticas y renderizado WPF. **No reemplazan** una prueba interactiva con AutoCAD en Windows real, distintas escalas DPI, UAC y reversión. Release permanece **BLOCKED**.

- `docs/SPEC_MAESTRA.md`: contrato técnico, alcance y protecciones del motor.
- `docs/V43_DASHBOARD_WPF.md`: auditoría, plan KISS, QA y pendientes de interfaz.
- `docs/F17_PROTOCOLO_QA_INTEGRADA.md`: protocolo único de aceptación en laboratorio aislado.

Proyecto independiente, no afiliado a Autodesk o Microsoft. No alteres licenciamiento, software ajeno ni reglas de terceros.
