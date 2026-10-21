# F0 — Guía de uso y validación de ParcheCAD 4.0

**Estado:** pendiente de QA funcional en Windows; módulo exclusivamente de lectura.

## Cómo ejecutarlo
Extrae/clona este repositorio en una carpeta local. Abre \`Abrir_ParcheCAD.cmd\` sin elevar permisos inicialmente. Si AVG o Defender alertan, detén la prueba; no desactives el antivirus.

Se presentan seis etapas: instalaciones 2023–2027, procesos/WebView2, servicios, firewall, tareas heredadas y conexiones. Cada etapa muestra OK/ERROR y elementos encontrados. Si falla, **0 no significa que no existan elementos**.

Guarda \`informes/<marca de tiempo>/diagnostico.json\` y \`resumen.txt\` (no están en Git). No los subas a repositorios públicos sin inspección adicional: nombres de programas, tareas y rutas sanitizadas pueden seguir siendo identificables.

Por consola, desde el repositorio:

\`\`\`powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\src\ParcheCAD.Diagnostico.ps1
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\src\ParcheCAD.Diagnostico.ps1 -NoExport
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\F0.Tests.ps1
\`\`\`

El flag \`RemoteSigned\` solo afecta a ese proceso y no modifica la política permanente. Si la seguridad del sistema impide ejecutar el script, no la desactives: consulta las propiedades del archivo o la política con tu administrador.

## QA en equipo real
- Escenarios: cero AutoCAD, 2023, 2027, varias versiones, ruta personalizada y registro sin InstallLocation.
- AutoCAD abierto/cerrado: comparar PID, PPID, UDF de WebView2 y servicios reales.
- Cotejar filtros del firewall y tareas heredadas contra la administración de Windows.
- Medir si el inventario es completo; ActiveStore puede incluir GPO y ser inaccesible.
- Comprobar que el sistema y la conectividad de WhatsApp/Outlook no cambian.
- Identificar como PARCIAL cualquier error por acceso o comando faltante.
- Verificar que informes no tengan IP remotas ni command lines completos.
- No declarar «bloqueo completo» ni «WebView2 deshabilitado»: esta fase no bloquea nada.
- Pruebas estáticas y CI no reemplazan QA real sobre Windows con AVG activo.

**NEXT:** revisar resultados del PR y probar F0 en Windows antes de avanzar al catálogo F1.
