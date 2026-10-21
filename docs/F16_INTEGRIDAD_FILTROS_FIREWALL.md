# F16 — Integridad de filtros de reglas Windows Firewall

**Estado:** corrección implementada en PR #18 Draft, apilado sobre #17; sin merge ni RC1.

## Defecto comprobado

Hasta F15, `Get-PCADActualRuleStatus` comparaba nombre, ruta del EXE, grupo PCAD4, acción Block, dirección Outbound, Enabled y Profile. Windows Firewall mantiene otros filtros independientes. Una regla con esos seis campos iguales, pero limitada a **TCP, un destino IP, un puerto o una sola interfaz**, podía obtener `EXISTS_VALID`, saltándose la creación de una regla realmente amplia.

El fallo afecta también la idempotencia y la reversión: una regla modificada o ajena no debe tratarse como propiedad de ParcheCAD con cobertura completa.

## Cambio funcional KISS

Sin crear otro motor, en `src/ParcheCAD.Policy.ps1`:

- `Get-NetFirewallPortFilter`: protocolo, puerto local y remoto deben estar en `Any`.
- `Get-NetFirewallAddressFilter`: dirección local y remota deben estar en `Any`.
- `Get-NetFirewallServiceFilter`: servicio `Any`.
- `Get-NetFirewallInterfaceTypeFilter`: tipo de interfaz `Any`.
- `Get-NetFirewallInterfaceFilter`: alias de interfaz `Any`.
- Los filtros deben ser **únicos**; ausencia, duplicación, error de consulta o restricciones inesperadas provocan `CONFLICT` o excepción fail-closed.
- `New-PCADRulePlan -CheckExisting` convierte los conflictos en `NO_APLICAR`. `Invoke-PCADApplyPlan` valida de nuevo antes de crear reglas; `Invoke-PCADRollbackRules` no elimina una regla si sus filtros han sido modificados por otra aplicación/administrador.

Se reutiliza `Test-PCADFirewallFilterAny`, pequeña función de validación, para evitar lógica duplicada. No se generan reglas por servicio ni excepciones de WebView2.

## Pruebas en Windows

`tests/F3F4.Tests.ps1` incluye escenarios con filtros simulados modificados: protocolo TCP, IP remota `192.0.2.10`, servicio `Spooler`, tipo de interfaz Wireless y alias Ethernet. Todos deben devolver `CONFLICT`, y un nuevo plan debe impedir Apply.

`tests/F4.RealFirewall.Integration.ps1` modifica la **dirección remota exclusivamente de su propia regla temporal** a `192.0.2.77`, verifica que deje de ser válida y que el plan muestre conflicto, la restaura a `Any` dentro de `finally` y comprueba idempotencia y rollback posterior. Se mantiene la prueba F13 del resultado real TCP IPv4 permitido → bloqueado → recuperado. Ningún cambio en el firewall del usuario.

La sintaxis de estos filtros y su relación uno-a-uno con las reglas está documentada por Microsoft:
- https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewalladdressfilter
- https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallinterfacetypefilter
- https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallinterfacefilter

## Lo que NO demuestra

Verificar los filtros de una regla propia evita falsos `EXISTS_VALID`, pero **no demuestra bloqueo universal** en las políticas efectivas del sistema: reglas de terceros, GPO, configuraciones del antivirus, seguridad avanzada o tráfico delegado aún requieren pruebas reales.

Persisten bloqueos RC1: AutoCAD instalado 2023–2027, tráfico TCP/UDP IPv4/IPv6 de servicios compartidos, WebView2 exclusivo de AutoCAD, GUI/UAC/AVG y reinicio físico. No se cambian licencias, binarios, servicios ni ejecutables de otras aplicaciones.

**NEXT:** conservar una única QA final integrada en un entorno de escritorio Windows aislado con AutoCAD autorizado; no pedir pruebas por módulo ni publicar RC1 con cobertura insuficiente.
