# F4 — Panel integrado y QA real (ParcheCAD 4.0)

Estado: desarrollo, PR #6 Draft, sin merge ni release. Fecha: 2026-10-20/21.

## Resultados comprobados
- Motor de firewall saliente por EXE exclusivo AutoCAD 2023–2027, con identidad por hash, journal, verificación y rollback de reglas propias.
- Prueba real en GitHub-hosted Windows Server 2022 desechable, sobre copia temporal de whoami.exe ubicada en carpeta ficticia AutoCAD 2023; NUNCA contra AutoCAD, WebView2 o licencias.
- Casos reales PASS: crear regla, comprobar filtro y acción, repetir sin duplicados, eliminar el ejecutable de prueba, revertir y comprobar ausencia final.
- Panel WinForms: vista previa, aplicar con UAC y confirmación escrita, revertir por selección explícita de manifiesto local. No ejecuta cambios automáticamente al abrir.
- El diagnóstico y la observación WebView2 se mantienen de solo lectura.
- Se corrigieron: caracteres no admitidos en DisplayName, referencia a archivo inexistente durante rollback, fallos de lectura que antes podían confundirse con ausencia y handlers GUI que provocaron parser error.

## Evidencia
CI GitHub #32 PASS: https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39532218826
- Windows PowerShell 5.1: PASS suite F0–F4, smoke de diagnóstico y preview, autoevaluación de controles WinForms sin interfaz visible.
- PowerShell 7: PASS suite F0–F4.
- Windows efímero: PASS ciclo real crear/verificar/repetir/revertir una regla temporal.

## NO CERTIFICADO
- No se probó con AutoCAD real 2023, 2024, 2025, 2026 ni 2027.
- No se probó la interacción visual completa de la ventana, UAC denegada, reinicio, bloqueo en GPO ni falla abrupta de energía.
- Bloquear el ejecutable principal NO demuestra bloquear todo Autodesk ni el tráfico originado por WebView2 compartido; este runtime sigue excluido de la política base.
- No se bloquean servicios compartidos Autodesk como Identity/Licensing/ODIS de forma automática.
- Las rutas bajo perfiles Windows se sanean en reportes; queda pendiente cobertura de instalaciones personalizadas sin exponer datos privados.
- Firewall Outbound Program también puede afectar LAN y validación periódica de licencias.

## NEXT
F5: QA integrado GUI + motor en Windows desechable con escritorio; cubrir rutas personalizadas, errores, recuperación, actualizaciones, reglas heredadas y pruebas con software real en RC. No pedir pruebas de cada fase al usuario. No fusionar PRs #3, #4, #5, #6 hasta revisión. Sin release todavía.
