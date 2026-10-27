@echo off
setlocal
rem Interfaz WinForms de emergencia, sin tocar politica persistente.
set "PCAD_OPTION="
if /I "%~1"=="--selftest" set "PCAD_OPTION=-SelfTest"
echo ParcheCAD - UI clasica de respaldo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0src\ParcheCAD.Panel.ps1" %PCAD_OPTION%
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
  echo Error al iniciar el panel clasico.
  pause
)
exit /b %RESULT%
