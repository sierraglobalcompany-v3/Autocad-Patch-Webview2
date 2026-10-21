# F13 — Prueba del resultado real de una regla saliente (TCP IPv4)

**Estado:** prueba automatizada PASS en Windows GitHub-hosted, no en AutoCAD real. **No RC1, no merge, no Release.**  
**PR:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/pull/15  
**Evidencia inicial:** https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39548196571

## Por qué era necesaria

Las pruebas previas podían demostrar creación, coincidencia e idempotencia de reglas de Windows Firewall y su reversión. Eso no basta para decir que las reglas **impiden una conexión TCP real**.

F13 agrega una prueba distinta, sin ampliar la política de producción ni bloquear procesos Microsoft o Autodesk compartidos.

## Prueba de extremo a extremo efectivamente ejecutada

En `tests/F13.SyntheticEgress.Integration.ps1`:

1. Un Windows Server 2022 temporal de GitHub genera un EXE de consola C# con `Add-Type`, **no Autodesk real**. El EXE solamente establece una conexión TCP IPv4 hacia `1.1.1.1:443` (servicio público HTTPS), sin enviar datos de usuarios o archivos.
2. Lo coloca en una ruta simulada `.../Autodesk/AutoCAD 2023/acad.exe` y copia exactamente el mismo binario con nombre `ProbeControl.exe` en una ubicación diferente.
3. Comprueba que **ambos** establecen conexión antes de aplicar una regla. Si no hay línea base, la prueba detiene el CI (BLOCKED), en vez de fabricar un resultado.
4. Con el motor actual PCAD4, genera una única regla saliente para el EXE ficticio y verifica que Windows la reconoce como válida.
5. Ejecuta **dos intentos** del programa bloqueado: deben fallar. Simultáneamente, el ejecutable de control debe seguir conectando, para reducir la posibilidad de confundir un corte global de red con éxito del bloqueo.
6. Invoca el rollback del motor, comprueba que la regla desaparece y exige que ambos programas vuelvan a conectarse.
7. Un `finally` inspecciona nombre, grupo, filtro y ruta antes de limpiar únicamente su regla temporal. No retira reglas ajenas, ni desactiva el firewall/antivirus.

**Resultado registrado en los logs del CI:** `F13 BASELINE PASS`, `F13 EGRESS PASS`, `PASS F13: IPv4 outbound synthetic TCP allowed / denied / restored; unrelated process unaffected`.

## Garantías y limitaciones

| Comprobación | Resultado |
|---|---|
| El EXE ficticio tenía conexión saliente inicialmente | PASS |
| La regla de programa impidió dos conexiones TCP IPv4 | PASS |
| Otro EXE con mismo código y otra ruta siguió conectado | PASS |
| Al revertir, volvió la conexión del EXE ficticio | PASS |
| AutoCAD 2023–2027 instalado, con servicios reales | **NO PROBADO** |
| Bloqueo de todos los servicios Autodesk/proxies | **NO PROBADO** |
| IPv6, UDP y redes LAN | **NO PROBADO** |
| WebView2 exclusivo de AutoCAD / impedir que se inicie | **NO RESUELTO** |
| UAC GUI real, AVG del usuario y reinicio físico | **NO PROBADO** |

Es una prueba efectiva de la **política de Windows Firewall por ruta de ejecutable**, no un certificado global de ausencia de conexiones Autodesk. El evaluador F12 continúa `Decision=BLOCKED`.

## Decisión arquitectónica

Aplicar las cuatro leyes KISS / anti-ruido / no parches / UX: se reutilizaron `ParcheCAD.Policy.ps1` y `ParcheCAD.Firewall.ps1`, sin crear un segundo motor de reglas. F13 es **solo un test de integración del repositorio**, no un botón, servicio, dependencia o módulo nuevo que deba ejecutarse en el PC del usuario.

**NEXT único:** preparar una sesión final realmente interactiva de QA con AutoCAD legítimo instalado, AVG activo, mediciones TCP/UDP IPv4/IPv6 en sus procesos y servicios, UAC, reinicio y comprobación de WhatsApp/Outlook. Hasta entonces, PRs Draft, sin merge/release, sin pruebas fragmentadas para el usuario.
