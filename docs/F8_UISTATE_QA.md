# F8 — Estado único de la interfaz y validación defensiva

**Repositorio:** sierraglobalcompany-v3/Autocad-Patch-Webview2  
**Rama:** `feat/f8-ui-report-safety` · **PR #10 Draft**, apilado sobre #9.  
**Estado:** desarrollo validado por CI; **SIN RC1, Release ni merge a main**.

## Defecto localizado y corrección de origen

Antes de F8, `ParcheCAD.Panel.ps1` evaluaba el código de salida para anunciar «diagnóstico completo» aunque el informe JSON fuera parcial o no tuviese todas sus secciones. Además, tenía lógica duplicada de seguridad para la habilitación de Aplicar, y algunas secciones inexistentes podían lanzar excepciones bajo `Set-StrictMode`.

En F8 se extrajo **una única fuente de estado puro y solo lectura** en `src/ParcheCAD.UIState.ps1`, sin agregar servicios ni dependencias. El estado valida simultáneamente:

1. Código de salida del proceso: debe ser 0.
2. Informe identificado como `ParcheCAD`, versión de esquema 1 y `ReadOnly=true`.
3. Resultado exacto `DIAGNOSTICO_COMPLETADO_SIN_CAMBIOS`.
4. Diez etapas conocidas, una vez cada una, todas con `Status=OK`.
5. Recuperación existente, sana, sin operaciones pendientes ni respaldos corruptos.
6. Plan de bloqueo coherente: `PLAN_NO_APLICADO`, candidatos positivos y conflictos igual a cero.

El mismo objeto de estado alimenta **texto de resultado, Vista previa y Aplicar**. Si falta una sección, hay estado parcial, error o contradicción entre JSON y proceso, no se habilita Aplicar. Un histórico de recuperación incongruente también impide mostrar **COMPLETO**, aunque las diez etapas del JSON digan OK. El CLI mantiene sus verificaciones propias y la confirmación administrativa.

## Pruebas

**CI #73 — PASS 4/4:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39540161818

- PowerShell 5.1 y 7: `tests/F8.UIState.Tests.ps1` comprueba informes sanos, inexistentes, corruptos, semánticamente incompletos, etapas duplicadas, sección de recuperación ausente, conflictos, `ReadOnly=false`, herramienta ajena, código no cero y resultado parcial contradictorio.
- WinForms `-SelfTest` verifica que Aplicar no se active con un informe parcial, sin histórico, con recuperación pendiente o código de salida 2, y que se deshabilite durante un proceso activo.
- Windows efímero: test F4 de firewall temporal y reversión PASS, sin AutoCAD real.
- ZIP DEV: se incluye el nuevo módulo de estado, se compila dos veces con hashes coincidentes y se ejecuta el panel desde el ZIP extraído.
- Se detectó una expresión de formato incompatible con el analizador de PowerShell durante el primer CI; se reestructuraron las variables de presentación en vez de añadir excepciones, y se repitió la QA hasta PASS.

## Lo que NO prueban estos resultados

- No es QA de ventanas visuales operadas por una persona ni prueba completa de clics en escritorio: el SelfTest ejecuta lógica interna y construcción WinForms.
- No se probó UAC con aceptación/rechazo, cancelación durante escritura real, cambio de DPI ni apagado brusco.
- No se ha probado AutoCAD real en las versiones 2023–2027 ni medido conexiones efectivas de todas las apps y servicios Autodesk.
- **No hay aislamiento exclusivo comprobado de WebView2 de AutoCAD**. El ejecutable Microsoft compartido sigue excluido del bloqueo global para no afectar WhatsApp, Outlook, etc.
- Las reglas de firewall basadas en EXE pueden bloquear también LAN y afectar funciones/validaciones de suscripción. No se modifican binarios/licencias/antivirus.
- Las listas de respaldo contienen rutas privadas locales; se excluyen del repositorio y de los ZIP.

## NEXT

**F9 — QA integrada de interfaz y recuperación:** en Windows de escritorio descartable, ejecutar interacción de botones, UAC denegada y aceptada, cierre/cancelación, resultados administrativos y validación de DPI; probar escenarios de reinicio y validar lo que sea posible con instalaciones AutoCAD reales. No anunciar RC1 mientras existan estos bloqueos. Mantener los PR #3–#10 Draft sin merge.
