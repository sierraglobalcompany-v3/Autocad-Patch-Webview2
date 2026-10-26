# ParcheCAD 4.3 | Diseño WPF — especificación y QA

## Objetivo
El usuario rechazó las versiones 4.1 y 4.2 porque la interfaz WinForms se veía como un formulario clásico, lejos del mockup aprobado. Rediseñar solo la capa visual con WPF/XAML de Windows: moderno, legible, sin añadir framework externo y sin Codex.

## Composición visual
- Cabecera, indicador dinámico y cuatro tarjetas: AutoCAD, candidatas/conflictos, WebView2 y AutoCAD probable.
- Advertencia visible sobre runtime Microsoft compartido.
- Dos tarjetas de trabajo: Firewall AutoCAD con vista previa / aplicar / revertir y WebView2 con auditar / monitor / detener.
- Progreso animado indeterminado con contador cuando no hay % real.
- Registros separados por pestañas AutoCAD, WebView2 y monitor.
- Accesos Abrir informes, Cancelar consulta, Salir, con tipografía Segoe UI, sombras suaves, bordes redondeados.

## Contrato KISS: backend intacto
- `src/ParcheCAD.Preview.ps1`: consulta de reglas read-only en proceso hijo.
- `src/ParcheCAD.WebViewAudit.ps1`: auditoría de WebView2 read-only, sin bloqueo global.
- `src/ParcheCAD.Monitor.ps1`: polling limitado a diez minutos, detener por archivo de señal.
- `src/ParcheCAD.Reglas.ps1`: aplicar y revertir solo con UAC, respaldo, validación de rutas y confirmación escrita.
- Cancelar solo detiene consultas de lectura propias; nunca AutoCAD, servicios ajenos o operaciones administrativas.
- Salir con operación administrativa abierta no termina procesos elevados; exige terminar operación.
- Fallback clásico `Abrir_ParcheCAD_Clasico.cmd` durante la validación.

## Gates
Windows PowerShell 5.1 STA: cargar XAML y revisar existencia de controles, botones de cancelación/parada inicialmente inactivos.
F6: comprobar XAML y launcher desde ZIP extraído descargado, incluyendo Mark-of-the-Web.
Pruebas originales de PowerShell 5.1 y 7, reglas temporales sintéticas y monitor.
**Pendiente:** captura del nuevo diseño en el Windows del usuario, DPI/zoom, accesibilidad, UI interactiva, AutoCAD 2027 y Apply/Rollback real autorizado. No RC1, no merge.