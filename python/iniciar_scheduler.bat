@echo off

cd /d "C:\Proyectos\GamesDB"


set PYTHONW=

:: 1. Intentar desde PATH
where pythonw >nul 2>&1
if %errorlevel% equ 0 (
    set PYTHONW=pythonw
    goto :iniciar
)

:: 2. Buscar en instalaciones estandar del usuario (Python 3.9 - 3.13)
for %%V in (313 312 311 310 39) do (
    if exist "%LOCALAPPDATA%\Programs\Python\Python%%V\pythonw.exe" (
        set PYTHONW="%LOCALAPPDATA%\Programs\Python\Python%%V\pythonw.exe"
        goto :iniciar
    )
)

:: 3. Buscar en instalacion global (C:\Python3x)
for %%V in (313 312 311 310 39) do (
    if exist "C:\Python%%V\pythonw.exe" (
        set PYTHONW="C:\Python%%V\pythonw.exe"
        goto :iniciar
    )
)

echo [ERROR] pythonw.exe no encontrado.
echo Verifica que Python este instalado y agrega su carpeta al PATH.
pause
exit /b 1

:: ------------------------------------------------------------
:iniciar
:: ------------------------------------------------------------
echo Iniciando GamesDB Steam Scheduler...
echo Ejecutable : %PYTHONW%
echo Script     : C:\Proyectos\GamesDB\python\steam_scheduler.py
echo Log        : C:\Proyectos\GamesDB\python\steam_scheduler.log
echo.


start "" %PYTHONW% "C:\Proyectos\GamesDB\python\steam_scheduler.py"

echo Scheduler iniciado en segundo plano.
echo Para detenerlo: taskkill /F /IM pythonw.exe
timeout /t 4 /nobreak >nul
exit /b 0

