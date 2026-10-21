# ParcheCAD 4.0 — F5: rutas personalizadas, privacidad y recuperación

**Estado:** F5 parcialmente completada. Rama `feat/f5-rutas-recuperacion`, PR #7 Draft apilado sobre #6. **Sin merge ni release.**

## Objetivo y reglas no negociables

- KISS, optimización y ley anti-ruido: integrar las mejoras en las fuentes originales, sin servicios residentes, drivers nuevos ni parches duplicados.
- Inventario sin alterar Windows; bloqueo saliente exclusivamente tras diagnóstico completo y confirmación administrativa.
- Evitar bloqueos globales del runtime compartido `msedgewebview2.exe`; no afectar intencionalmente WhatsApp, Outlook u otras apps.
- No modificar binarios, licencias, antivirus, tareas ajenas ni servicios Autodesk por defecto.
- No declarar `bloqueo total Autodesk` ni `WebView2 aislado` sin evidencia de tráfico por componente.

## Cambios entregados

### 1. Separación explícita de rutas privadas y reportes

- `Get-PCADInstallations -InternalPaths` mantiene rutas completas solo en memoria para operaciones internas.
- `Get-PCADExecutableCatalog -InternalPaths` entrega la raíz real de instalación y los ejecutables para clasificación.
- El diagnóstico usa ese catálogo privado para el plan, pero exporta **copias saneadas** mediante `ParcheCAD.Evidence.ps1`.
- En la consola de administración se redescubre la ruta real: **nunca se reconstruye la ruta a partir del JSON público**.

### 2. Soporte para instalaciones personalizadas

- `Assert-PCADProgramInstallRoot` valida versión 2023–2027, que el EXE esté dentro de la raíz elegida y, en aplicación normal, que exista `acad.exe` allí.
- La raíz se propaga desde el catálogo al plan, al journal y a la recuperación.
- Compatibilidad con reglas históricas anteriores que no incluían raíz: se conserva el caso de ruta tradicional `AutoCAD 20XX`.
- Se rechazan rutas sin raíz coherente, UNC, archivos inexistentes al aplicar y WebView2 compartido.

### 3. Recuperación conservadora y visibilidad

- Un estado `CREATING` no se omite como si se hubiese completado la reversión.
- `Get-PCADRecoveryOverview` inventaría sin cambios los manifiestos locales: válidos, registrados como aplicados, interrumpidos y corruptos.
- El panel advierte operaciones que requieren revisión, **sin afirmar que el journal certifica las reglas realmente activas**.
- Si el EXE de AutoCAD ya no está, se puede comprobar la identidad estructural y revertir su regla propia; una regla ajena no se borra.

### 4. Controles de interfaz

- El botón Aplicar se habilita solamente con reporte completo, candidatos válidos y sin conflictos.
- Las acciones durante diagnóstico o administración están deshabilitadas.
- Los controles se han validado en un arranque de WinForms sin interacción visible; UAC, clics y renderizado real siguen sin certificar.

## Pruebas y evidencias

**CI #40 — PASS 3/3:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39534804275

- Windows PowerShell 5.1: parser y suites F0–F5 PASS, diagnóstico de 10 etapas PASS sin AutoCAD, WinForms selftest PASS y vista previa read-only PASS.
- PowerShell 7 en Windows: parser y suites F0–F5 PASS.
- Firewall real Windows efímero: alta/verificación/idempotencia/borrado del EXE de prueba/rollback/limpieza PASS, sin instalar ni alterar Autodesk.
- Fixtures F5: instalación custom, privacidad del JSON, raíz ajena rechazada, journal interrumpido, journal aplicado y corrupto, resumen histórico con advertencias.

Los archivos de prueba usan ejecutables ficticios y no realizan verificación de conexiones de AutoCAD. Una prueba limpia en runner no demuestra soporte funcional con todas las versiones.

## Bloqueos abiertos de RC1

1. **QA visual e interacción:** WinForms en escritorio Windows con UAC aceptada/rechazada, botón Cancelar, informe parcial, reinicio y cierre durante administración. Arranque básico no es QA visual integral.
2. **Instalaciones reales:** verificar al menos ambientes con AutoCAD instalado; registro sin `InstallLocation` o rutas no estándar que el instalador real no publique siguen siendo detección incompleta.
3. **Cobertura Autodesk:** servicios compartidos y proxies no se bloquean automáticamente; tráfico TCP/UDP IPv4/IPv6 aún no certificado con AutoCAD.
4. **WebView2 exclusivo de AutoCAD:** sigue NO RESUELTO. No usar bloqueo global del runtime Microsoft.
5. **Reversión en cortes abruptos:** la lógica detecta journals incompletos, pero aún falta prueba de interrupción deliberada durante una modificación real y recuperación tras reinicio.
6. **Distribución:** aún no existe RC1 ni instalador/ZIP final certificado. AVG debe continuar activo durante cualquier QA.

## NEXT único

**F5 cierre hacia RC1 integrada:** realizar QA gráfica/control de errores sobre Windows aislado, comprobar reconexión y reversión en fallos, resolver detección de rutas Autodesk verdaderas y documentar cobertura efectiva. Luego empaquetar versión candidata completa para una única aceptación del usuario. Mantener los PR #3–#7 Draft y `main` sin merge hasta revisión.
