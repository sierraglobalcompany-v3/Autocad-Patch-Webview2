# ParcheCAD 4.0 — AutoCAD 2023–2027 y WebView2

Proyecto de control y diagnóstico de conectividad para instalaciones de AutoCAD 2023, 2024, 2025, 2026 y 2027 en Windows.

> **Estado: desarrollo F0–F11 en PRs Draft, con ZIP técnico DEV disponible en GitHub Actions. NO RC1, NO release.** CI Windows PS5.1/7 y firewall temporal verde; **sin release 4.0 ni QA gráfica integral/AutoCAD real**. Las versiones históricas 2.x y 3.x no son releases de este repositorio.

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

**Estado técnico:** F0–F2 inventario y GUI, F3 atribución observacional WebView2, F4 reglas salientes y reversión verificadas con mocks y un ejecutable temporal en Windows, F5 soporte de rutas personalizadas y saneamiento, F6 detección de DisplayIcon, recuperación de regla real interrumpida simulada y ZIP verificable; F7 bloquea nuevas reglas con respaldos corruptos o pendientes; F8 centraliza la validación del resultado del diagnóstico; F9 corrige el manejo de controles y ejecuta los eventos Analizar/Cancelar/Cerrar en Windows descartable; F10 confirma la terminación del proceso propio y recupera un journal CREATING desde otro proceso PS5.1; F11 añade una matriz de cobertura solo lectura de ejecutables de producto, servicios compartidos, WebView2 y conexiones observadas en JSON/TXT/WinForms. El diagnóstico usa un marcador de finalización explícito para evitar falsos estados completos. La vista previa no crea reglas. **No hay certificación de aislamiento completo de Autodesk/WebView2.**

Para ejecutar el diagnóstico en consola: `powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\src\ParcheCAD.Diagnostico.ps1`. Para visualizar un plan de reglas de solo lectura: `powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\src\ParcheCAD.Reglas.ps1 -Mode Preview`.

**No ejecutar todavía Apply/Rollback en el equipo principal**: aunque los escenarios de reglas temporales y recuperación de journal CREATING pasaron en un Windows descartable, faltan QA visual de la interfaz, AutoCAD instalado, reinicio/interrupción abrupta real y verificaciones de cobertura. El panel ofrece cambios solo tras UAC y doble confirmación.

**Paquete técnico DEV (NO RELEASE):** `tools/Build-ParcheCAD.ps1` genera un ZIP sin logs privados, con manifiesto de hashes. GitHub Actions lo valida dos veces y publica un artifact temporal de desarrollo; no se recomienda ejecutarlo en el computador principal antes de RC1. Ver `docs/F6_PAQUETE_PRE_RC.md`.

**NEXT:** F12: diseñar pruebas de cobertura y efectividad en una VM Windows verdaderamente interactiva con AutoCAD real, medición de tráfico, UAC y reinicio; no presentar ausencia total de tráfico/WebView2 mientras no exista evidencia. F11: `docs/F11_MATRIZ_COBERTURA_WEBVIEW2.md`. No solicitar pruebas parciales al usuario.

## Desarrollo

Los cambios de código se implementarán en ramas y PRs revisables. No se copiarán los antiguos scripts de bloqueo sin auditoría y pruebas. El diseño técnico vigente estará en `docs/SPEC_MAESTRA.md`.

## Aviso

Herramienta independiente, no afiliada a Autodesk o Microsoft. El comportamiento de conectividad puede afectar funciones o licencias del software; ninguna medición o bloqueo equivale a modificar derechos de uso.
