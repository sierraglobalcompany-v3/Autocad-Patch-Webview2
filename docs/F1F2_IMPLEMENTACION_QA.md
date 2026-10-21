# F1/F2 — Implementacion y checkpoints

## Alcance comprobado
- F1: Inventario acotado de EXE por instalacion AutoCAD 2023–2027; cada fila tiene version, clase, confianza, efecto potencial y una etiqueta SOLO_INVENTARIO.
- El escaneo no atraviesa reparse points ni busca a ciegas en todo C:\ o ProgramData; limite por producto configurable. Si hay error/limite, avisa PARCIAL.
- Los servicios Autodesk se clasifican COMPARTIDO, separados de la carpeta del producto.
- El WebView2 de Microsoft se clasifica COMPARTIDO, nunca como EXE exclusivo de AutoCAD.
- F2: Resumen read-only de reglas históricas SGC/PCAD/WebView2 y tareas potencialmente antiguas, pero NUNCA prueba propiedad por el nombre o borra reglas.
- Panel WinForms: ejecuta el diagnostico en un proceso independiente sin privilegios especiales, barra por etapa, cronometro, archivos locales e interfaz disponible.
- CLI F0 mantenido para QA/no interfaz y diagnósticos de errores.

## Evidencia automatizada
- GitHub Actions workflow F0 static QA, run #7, https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39527536436 : **PASS** Windows PowerShell 5.1 y PowerShell 7 (parser + tests). 
- Smoke Windows Server 2022 sin AutoCAD: 8/8 etapas reportadas OK; 1 regla firewall coincidió, 0 versiones instaladas, sin cambios.
- Fixtures de F1 prueban dos EXE sintéticos, límite de escaneo, exclusión de ruta ajena, Autodesk compartido, WebView2 compartido y bloqueo antiguo.
- UI WinForms: parser PASS; **no probado visualmente**. No confundir con PASS funcional completo.

## Limitaciones y decisiones
1. F1/F2 no bloquea ni quita reglas todavía. El panel se presenta como diagnóstico.
2. 8 etapas no equivalen a «todas las conexiones bloqueadas».
3. No atribuir WebView2 a AutoCAD con certeza si solo se encontró por parent PID o directorio UDF.
4. El inventario puede depender de permisos locales, firma de archivos y rutas instaladas; los valores de un equipo limpio no son certificación de las cinco versiones reales.
5. Una licencia Autodesk válida puede necesitar conectividad periódica; las futuras políticas deben indicar impacto y no interferir con mecanismos de licencia del proveedor.
6. El panel GUI puede tener bugs de visualización o inicio de procesos aún no observados; corregir con QA automatizado donde sea posible y reservando QA de usuario para la candidata integrada 4.0.

## Arquitectura
- src/ParcheCAD.Core.ps1: observación de Windows, F0
- src/ParcheCAD.Catalogo.ps1: clasificación acotada, F1
- src/ParcheCAD.Historico.ps1: evaluación de históricos, F2
- src/ParcheCAD.Diagnostico.ps1: 8 etapas e informe, F0+F1+F2
- src/ParcheCAD.Panel.ps1: WinForms, proceso externo, estado y progreso, F2
- Abrir_ParcheCAD.cmd: arranque GUI; CLI sigue disponible.
- tests/F0.Tests.ps1, tests/F1F2.Tests.ps1: CI

## Próximos pasos sin intervención del usuario
1. F3: observación y relación de conexiones con el host WebView2; laboratorio automatizado, no inventar bloqueo exclusivo si no existe.
2. F4: planeador de reglas exactas por ruta con preview; identidad determinista y control de reglas propias; rollback verificable.
3. F4 UI: habilitar aplicar/deshacer únicamente tras gate de seguridad, confirmación de usuario final y evidencia de estado.
4. F5: QA final integrando motor+UI con prueba de mutaciones en VM aislada. No pedir validación del PC real por módulos; probar RC completa una sola vez.

## PASS / BLOCKED
**PASS: F1 clasificación + F2 resumen de históricos en CI.**
**PARTIAL: F2 GUI parser PASS pero no QA visual real.**
**BLOCKED: F4 bloqueo, aislamiento WebView2 exclusivo, RC/release.**
