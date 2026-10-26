# ParcheCAD 4.1 - Auditoria focal y correcciones

## Base y evidencia real
- Base F17 SHA 0ce3dfa554e126e47aad1505f35b5fa16b2fcfbe / PR 19 Draft.
- Log real del usuario (26-10-2026): 357 muestras, 139 eventos, 80 TCP, cuatro UDP endpoints. acad.exe aparecio junto con WebView2 AUTOCAD_PROBABLE con TCP Established/443. No certifica bloqueo, ausencia total de llamadas ni aislamiento.
- Captura: AutoCAD 2027 detectado, pero monitor sobreescribia detalles del diagnostico. Aplicar sin explicacion clara cuando inhabilitado.

## Fallos corregidos, simples y focales
1. Arranque con PS1 sin firma descargado: RemoteSigned bloqueaba launcher y tres procesos secundarios. Bypass solo para cada proceso, no permanente, sin quitar Mark-of-the-Web ni ignorar GPO obligatoria. No se presenta como firma digital.
2. Separacion de detalle por pestañas Diagnostico/Reglas y Monitor/Registro; no se pierden candidatos ni el estado del diagnostico al finalizar monitor.
3. Funcion pura Get-PCADApplyBlockReason explica faltantes de gate (diagnostico incompleto, recovery, plan, conflictos, cero candidatos), preserva CanApply de F8.
4. Diseno moderno WinForms 4.1 estilo mockup: grupos Diagnostico / Operaciones / Monitor / Utilidades, analizar azul, Aplicar verde SOLO si el gate es verdadero, inactivos grises, resumen visible.
5. Operacion elevada con error muestra codigo y advertencia. Nunca se declara bloqueo sin verificacion.

## Guardas sin cambios
- Regla de firewall requiere plan consistente, >0 candidatos, sin conflictos, respaldo, administrador y confirmacion escrita; no forzar activacion.
- Excluir WebView2 global, software ajeno y servicios Autodesk compartidos.
- Monitor temporal observacional, sin prueba de bloqueo. No agregar nuevas dependencias o servicios.
- Main intacto; no merge, release ni regla real durante CI.

## QA
Windows PowerShell 5.1 y 7 para suites existentes; panel SelfTest y eventos; paquete ZIP reproducible con manifest SHA-256; test descargado con Zone.Identifier, smoke CI de firewall sobre EXE de prueba efimero.
Aun pendiente: revisar render de Windows real, UAC, conteo de candidatos AutoCAD 2027, apply/rollback real autorizado y evaluacion F17 antes/despues. RC1 no certificada.
