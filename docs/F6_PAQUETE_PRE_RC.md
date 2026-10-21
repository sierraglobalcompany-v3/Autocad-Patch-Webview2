# ParcheCAD 4.0 — empaquetado técnico de desarrollo (NO RELEASE)

**Estado:** F6 implementada y pruebas automáticas verificadas (CI #49, 4/4 PASS); pruebas de aplicación real AutoCAD pendientes. Rama `feat/f6-recovery-package` (PR Draft). No se ha publicado ni aprobado RC1.

## Contenido y política de paquete

La fuente de verdad es GitHub. `tools/Build-ParcheCAD.ps1` crea `dist/ParcheCAD_4.0_DEV_NO_RELEASE.zip` con una **lista blanca explícita** de lanzador CMD, motores PowerShell, README, SPEC, documentación de pruebas y continuidad. El ZIP lleva `SHA256SUMS.txt` interno para verificar cada archivo y genera un `.zip.sha256` externo.

No incluye registros de usuarios, `informes/`, claves, cachés, archivos de AVG, binarios de Autodesk, runtime WebView2, parches de licenciamiento, instaladores ajenos ni scripts remotos. No hace downloads ni instala servicios. El empaquetado normaliza marca de tiempo y orden de entradas para facilitar compilaciones repetibles.

**No interpretar el nombre ZIP como release, instalador aprobado ni certificación de seguridad en AutoCAD real.**

## Nuevas pruebas Windows

1. `DisplayIcon` como fuente adicional de ubicación, únicamente cuando se puede extraer una ruta local real hacia `acad.exe`. No ejecutar comandos del registro ni inferir una instalación de iconos inexistentes.
2. Simulación de fallo real entre creación de regla y escritura del journal `CREATED`: una regla temporal Windows queda representada como `CREATING`, y se revierte posteriormente con su identidad comprobada, incluso si falta el EXE.
3. Construcción repetida del ZIP en Windows; los hashes de los bytes deben coincidir. Extraer a una carpeta temporal, comprobar hashes internos, ejecutar parser y vista previa read-only sobre los archivos extraídos.
4. Subir a GitHub Actions un **artifact de desarrollo no publicado en Releases** con ZIP y checksum. Mantener todos los PR Draft.

## QA efectivamente realizado

**CI #49: PASS (4/4)** — https://github.com/sierraglobalcompany-v3/Autocad-Patch-Webview2/actions/runs/39536342870

- Windows PowerShell 5.1 y PowerShell 7: análisis de sintaxis y fixtures F0–F5 y DisplayIcon.
- Windows efímero: creación de regla temporal real, idempotencia y recuperación desde journal CREATING después de interrupción **simulada**, sin ejecutable y sin bloqueos residuales.
- ZIP de desarrollo: dos compilaciones con hash idéntico, lista blanca, SHA256 de cada archivo, checksum ZIP, extracción, ejecución CLI Preview y WinForms SelfTest desde carpeta extraída.
- El artifact temporal de GitHub Actions se denomina `ParcheCAD_4.0_DEV_NOT_RELEASE`; se guarda con retención limitada, no en GitHub Releases.

## Límites

- El ZIP no se instala automáticamente ni aplica bloqueos al abrirse. El panel pide confirmaciones.
- No se ha conseguido impedir que AutoCAD cree procesos WebView2 ni aislar su tráfico de forma demostrada respecto de otras aplicaciones. El ejecutable Microsoft compartido queda fuera del bloqueo automático.
- No se certifica todo Autodesk: servicios y procesos compartidos pueden realizar conexiones fuera de la política de EXE del producto.
- Licencias y servicios online pueden dejar de funcionar si se aplican bloqueos. No se modifica ninguna licencia ni antivirus.
- QA visual interactiva, UAC denegada/aceptada, AutoCAD real 2023–2027, escenarios múltiples y medición de tráfico todavía pendientes.

## NEXT

Completar CI de ZIP y test de interrupción de firewall; corregir lo que revele Windows. Actualizar continuidad y plan RC1. No pedir pruebas fragmentadas al usuario.
