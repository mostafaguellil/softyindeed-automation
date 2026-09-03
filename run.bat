@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0"

set "CDP_PORT=9222"
set "CDP_URL=http://localhost:%CDP_PORT%"
set "CDP_WAIT_SECONDS=15"
set "CHROME_USER_DATA_DIR=%TEMP%\chrome-cdp-softyindeed"
set "USE_CDP=true"
set "HEADLESS=false"

set "CHROME_APP="
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" (
  set "CHROME_APP=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
) else if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" (
  set "CHROME_APP=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
) else if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" (
  set "CHROME_APP=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"
)

where python >nul 2>&1
if errorlevel 1 (
  where py >nul 2>&1
  if errorlevel 1 (
    echo Erreur : Python introuvable. Installez Python 3.11+ et cochez "Add to PATH".
    exit /b 1
  )
  set "PYTHON=py -3"
) else (
  set "PYTHON=python"
)

if not exist ".venv" (
  echo → Creation de l'environnement virtuel .venv...
  %PYTHON% -m venv .venv
  if errorlevel 1 exit /b 1
)

call ".venv\Scripts\activate.bat"
if errorlevel 1 (
  echo Erreur : impossible d'activer .venv
  exit /b 1
)

echo → Installation des dependances...
python -m pip install -q -r requirements.txt
if errorlevel 1 exit /b 1
python -m playwright install chromium
if errorlevel 1 exit /b 1

if not exist ".env" (
  copy /Y ".env.example" ".env" >nul
  echo.
  echo → Fichier .env cree. Editez-le avec vos identifiants, puis relancez :
  echo    run.bat
  exit /b 1
)

REM Charge les variables utiles depuis .env (ignore commentaires et lignes vides)
for /f "usebackq eol=# tokens=1* delims==" %%A in (".env") do (
  if not "%%A"=="" (
    set "%%A=%%B"
  )
)

if "%CDP_PORT%"=="" set "CDP_PORT=9222"
if "%CDP_URL%"=="" set "CDP_URL=http://localhost:%CDP_PORT%"
if "%CDP_WAIT_SECONDS%"=="" set "CDP_WAIT_SECONDS=15"
if "%USE_CDP%"=="" set "USE_CDP=true"
if "%HEADLESS%"=="" set "HEADLESS=false"

REM Sur Windows, ignore un chemin macOS/Linux provenant du .env
echo.%CHROME_USER_DATA_DIR% | findstr /B /C:"/tmp/" >nul
if not errorlevel 1 set "CHROME_USER_DATA_DIR="
if "%CHROME_USER_DATA_DIR%"=="" set "CHROME_USER_DATA_DIR=%TEMP%\chrome-cdp-softyindeed"

set "MAIN_ARGS="

if /I "%USE_CDP%"=="true" (
  call :is_cdp_ready
  if errorlevel 1 (
    echo.
    echo === Chrome CDP non detecte sur %CDP_URL% ===

    tasklist /FI "IMAGENAME eq chrome.exe" 2>nul | find /I "chrome.exe" >nul
    if not errorlevel 1 (
      echo.
      echo Chrome est deja ouvert. Une fenetre Chrome dediee ^(profil separe^) sera lancee pour le CDP.
      echo Connectez-vous a Indeed Employeur et Softy dans CETTE fenetre.
    )

    if "%CHROME_APP%"=="" (
      echo.
      echo Google Chrome introuvable.
      echo Lancez manuellement Chrome avec :
      echo   chrome.exe --remote-debugging-port=%CDP_PORT% --user-data-dir="%CHROME_USER_DATA_DIR%"
      echo.
      echo Connectez-vous a Indeed et Softy ^(2FA inclus^), puis relancez run.bat
      exit /b 1
    )

    if not exist "%CHROME_USER_DATA_DIR%" mkdir "%CHROME_USER_DATA_DIR%"
    echo → Lancement de Chrome CDP ^(profil : %CHROME_USER_DATA_DIR%^)...
    start "" "%CHROME_APP%" --remote-debugging-port=%CDP_PORT% --user-data-dir="%CHROME_USER_DATA_DIR%"

    call :wait_for_cdp
    if errorlevel 1 (
      echo.
      echo Erreur : impossible de joindre Chrome sur %CDP_URL%.
      echo.
      echo Causes frequentes :
      echo   - le port %CDP_PORT% est deja utilise
      echo   - Chrome n'a pas eu le temps de demarrer ^(augmentez CDP_WAIT_SECONDS dans .env^)
      echo.
      echo Essayez manuellement :
      echo   "%CHROME_APP%" --remote-debugging-port=%CDP_PORT% --user-data-dir="%CHROME_USER_DATA_DIR%"
      exit /b 1
    )
  )

  set "MAIN_ARGS=--cdp --cdp-url %CDP_URL%"
  if not "%INDEED_ATTACH_URL%"=="" set "MAIN_ARGS=!MAIN_ARGS! --indeed-url %INDEED_ATTACH_URL%"
  if not "%SOFTY_ATTACH_URL%"=="" set "MAIN_ARGS=!MAIN_ARGS! --softy-url %SOFTY_ATTACH_URL%"
)

echo → Lancement de l'automatisation...
set "HEADLESS=%HEADLESS%"
python main.py %MAIN_ARGS% %*
set "EXIT_CODE=%ERRORLEVEL%"
exit /b %EXIT_CODE%

:is_cdp_ready
powershell -NoProfile -Command "try { (Invoke-WebRequest -UseBasicParsing '%CDP_URL%/json/version').StatusCode }" >nul 2>&1
exit /b %ERRORLEVEL%

:wait_for_cdp
set /a ELAPSED=0
:wait_loop
call :is_cdp_ready
if not errorlevel 1 exit /b 0
if !ELAPSED! GEQ %CDP_WAIT_SECONDS% exit /b 1
timeout /t 1 /nobreak >nul
set /a ELAPSED+=1
goto wait_loop
