@echo off
setlocal
rem Excepcion solo por proceso; no modifica politica de usuario/equipo ni GPO.
set "PCAD_OPTION="
if /I "%~1"=="--selftest" set "PCAD_OPTION=-SelfTest"
echo ParcheCAD 4.3 - Dashboard WPF / Firewall y WebView2
echo Al iniciar no se cambia el firewall. Aplicar o revertir exige confirmacion y administrador.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0src\ParcheCAD.Dashboard.ps1" %PCAD_OPTION%
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
  echo.
  echo No se pudo iniciar el panel. Consulte los detalles del error.
  pause
)
exit /b %RESULT%
