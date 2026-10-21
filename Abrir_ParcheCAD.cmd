@echo off
setlocal
echo ParcheCAD 4.0 - F0 ^(diagnostico de solo lectura^)
echo No instalara bloqueos de firewall.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0src\ParcheCAD.Diagnostico.ps1"
set "RESULTADO=%ERRORLEVEL%"
echo.
if not "%RESULTADO%"=="0" echo Diagnostico incompleto: consulte el informe local.
echo Presione una tecla para cerrar.
pause >nul
exit /b %RESULTADO%
