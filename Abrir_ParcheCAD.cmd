@echo off
setlocal
echo ParcheCAD 4.0 - Panel de diagnostico y monitor temporal
echo Al iniciar no se cambia el firewall. Aplicar o revertir exige confirmacion y administrador.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0src\ParcheCAD.Panel.ps1"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
  echo.
  echo No se pudo iniciar el panel. Consulte los detalles del error.
  pause
)
exit /b %RESULT%
