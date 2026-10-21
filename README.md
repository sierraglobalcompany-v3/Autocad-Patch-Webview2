# ParcheCAD 4.0 — AutoCAD 2023–2027 y WebView2

Proyecto de control y diagnóstico de conectividad para instalaciones de AutoCAD 2023, 2024, 2025, 2026 y 2027 en Windows.

> **Estado: desarrollo F0–F4 en PRs Draft.** CI Windows PS5.1/7 verde; no existe release 4.0 ni validación de firewall real/GUI. Las versiones históricas 2.x y 3.x no son releases de este repositorio.

## Objetivo

- Identificar instalaciones reales de AutoCAD y sus ejecutables, procesos y servicios asociados.
- Mostrar el estado de reglas del firewall y detectar bloqueos heredados.
- Atribuir procesos WebView2 a sus aplicaciones anfitrionas sin confundirlos con el runtime compartido.
- Evaluar un control de red reversible y por componente, sin afectar WhatsApp, Outlook ni otras aplicaciones.
- Informar con evidencia de lo que fue detectado, aplicado, comprobado y de lo que permanece sin verificar.

**Limitación clave:** bloquear `acad.exe` mediante reglas por ruta no bloquea automáticamente todas las conexiones originadas por `msedgewebview2.exe`. Una regla global para WebView2 puede afectar otras aplicaciones; el programa no la instalará como comportamiento predeterminado. Bloquear el tráfico tampoco impide que WebView2 se ejecute localmente.

## Principios del proyecto

- **KISS / anti-ruido:** reutilizar y simplificar; no añadir servicios, controladores ni tareas programadas sin pruebas que lo justifiquen.
- **Primero diagnóstico, luego cambios.** F0 solo lectura, sin reglas, tareas ni modificaciones al registro.
- **Reversión y QA obligatorios.** Ninguna interfaz debe mostrar “bloqueo completo” sin evidencia funcional.
- **Sin desactivar antivirus ni eliminar controles de licenciamiento.** El modo sin conexión puede impedir funcionalidades y verificaciones de suscripciones válidas.
- **Sin datos sensibles en GitHub.** Sanitizar nombres de usuario, rutas personales, IP, tokens y registros antes de compartirlos.

## Plan de ejecución

1. **F0 — Diagnóstico**: descubrir AutoCAD 2023–2027, WebView2, servicios, firewall y tareas heredadas; exportar un reporte sanitizado.
2. **F1 — Clasificación**: distinguir ejecutables exclusivos de producto, componentes Autodesk compartidos y procesos Microsoft compartidos.
3. **F2 — Recuperación y UX**: interfaz responsiva, barra de progreso, estado inicial/final y reversión de reglas propias.
4. **F3 — Pruebas de tráfico**: medir qué conexiones provienen de cada componente; identificar limitaciones de aislamiento.
5. **F4 — Controles de firewall**: solo acciones explícitas, reversibles, probadas y con vista previa de impacto.
6. **F5 — QA / release**: validación real con Windows 10/11, PowerShell 5.1, antivirus activo y varias instalaciones.

**Estado técnico:** F0–F2 diagnóstico/clasificación, F3 atribución observacional de WebView2 y F4 planificador con aplicar/rollback (este último validado únicamente con mocks). La vista previa de F4 no crea reglas.

Para ejecutar el diagnóstico en consola: `powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\src\ParcheCAD.Diagnostico.ps1`. Para visualizar un plan de reglas de solo lectura: `powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\src\ParcheCAD.Reglas.ps1 -Mode Preview`.

**No ejecutar todavía Apply/Rollback en el equipo principal**: el motor tiene pruebas simuladas, pero no ha superado QA de mutaciones reales en VM aislada. El panel gráfico sigue siendo de solo lectura.

**NEXT:** QA de aplicación/reversión en VM aislada; después integración de los controles con el panel y candidata RC1. No se pide probar cada módulo al usuario.

## Desarrollo

Los cambios de código se implementarán en ramas y PRs revisables. No se copiarán los antiguos scripts de bloqueo sin auditoría y pruebas. El diseño técnico vigente estará en `docs/SPEC_MAESTRA.md`.

## Aviso

Herramienta independiente, no afiliada a Autodesk o Microsoft. El comportamiento de conectividad puede afectar funciones o licencias del software; ninguna medición o bloqueo equivale a modificar derechos de uso.
