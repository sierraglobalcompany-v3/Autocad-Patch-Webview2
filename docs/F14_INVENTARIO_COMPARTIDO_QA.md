# F14 — Inventario controlado de componentes Autodesk compartidos

**Estado:** desarrollo en PR #16 Draft, sin merge, despliegue ni RC1.

## Problema demostrado por auditoría

Hasta F13 el catálogo exploraba las carpetas de las instalaciones de AutoCAD confirmadas, además de las rutas de servicios que Windows reportaba. No inspeccionaba explícitamente directorios habituales de herramientas y componentes compartidos como AdODIS, Autodesk Access o Autodesk Shared. Por otro lado, al alcanzar `MaxDepth` en una carpeta profunda no quedaba advertencia de que el resultado podía omitir ejecutables.

No se deduce de ello que todos esos componentes deban ser bloqueados. Pueden servir a más de una aplicación y pueden manejar actualización, identificación o licenciamiento.

## Cambio de arquitectura KISS

`src/ParcheCAD.Catalogo.ps1` usa **un solo recorrido acotado** para raíces de AutoCAD y raíces compartidas, con límites independientes de archivos y profundidad. No sigue junctions ni enlaces simbólicos; no admite raíces de red. Conserva el escaneo de instalaciones instaladas y añade descubrimiento selectivo de carpetas existentes en Program Files y Common Files: AdODIS, Autodesk Access, Autodesk Desktop App, Identity Services y Autodesk Shared.

- Máximo por producto: 900 EXE y profundidad 7 por defecto.
- Máximo por raíz compartida: 250 EXE y profundidad 5 por defecto.
- La profundidad/cantidad excedida y errores de lectura producen advertencias. **Producto incompleto:** `Status=PARCIAL`, por lo que no se debe convertir a diagnóstico completo apto para aplicar reglas.
- **Compartido incompleto:** `SharedStatus=PARCIAL` y advertencia, sin bloquear automáticamente operaciones exclusivas del producto. Incluso en recorrido completo, el indicador `INVENTARIO_LIMITADO` recuerda que son solo directorios conocidos y no todos los Autodesk.
- Todos los EXE compartidos quedan con `Classification=AUTODESK_COMPARTIDO` o `WEBVIEW2_COMPARTIDO`, `Year=0`, `Policy=SOLO_INVENTARIO` y nunca se incorporan al plan F4 de bloqueo automático.
- `Sections.CatalogScope` informa `ProductStatus`, `SharedStatus`, `SharedAutomaticBlocking=false` y `InventoryOnly=true`. JSON y WinForms muestran esta distinción.

## QA de código y Windows

`tests/F14.SharedCatalog.Tests.ps1` genera instalaciones y directorios compartidos ficticios bajo TEMP. Comprueba que el plan incluya solamente EXE del producto, no los compartidos, y que límites de profundidad y archivos den estado parcial. Se ejecuta en PowerShell 5.1 y 7.

El test WinForms F9/F14 carga un diagnóstico real desde el proceso hijo y exige que la interfaz muestre la advertencia de cobertura compartida, sin elevar privilegios ni crear nuevas reglas.

Las pruebas F13 de TCP IPv4 sintético, el rollback de regla temporal y el ZIP SHA256 reproducible continúan como regresión.

## Limitaciones de cobertura

Las raíces son conocidas, **no exhaustivas**: otros servicios Autodesk, instalaciones personalizadas, ejecutables en perfiles de usuario y tráfico delegado pueden permanecer fuera. La clasificación por directorio no demuestra proveedor, firma ni que el EXE pertenezca exclusivamente a un producto. Aún falta ver AutoCAD auténtico funcionando y medir TCP/UDP IPv4/IPv6 de sus procesos, con AVG activo.

WebView2 de Microsoft sigue compartido: no se bloquea su ejecutable global ni se ha implementado impedir que AutoCAD lo inicie. No se modifican licencias, binarios Autodesk, servicios ni firewall mediante este inventario.

**NEXT:** continuar hacia una única QA final con AutoCAD verdadero y escritorio Windows interactivo. Hasta obtener evidencia, las diez puertas F12 siguen `BLOCKED` para RC1. No pedir al usuario pruebas fragmentadas.
