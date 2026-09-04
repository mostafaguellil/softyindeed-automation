@echo off
REM ============================================================
REM  SOFTY / INDEED — Lanceur Windows
REM  Double-cliquez CE fichier (pas "run" Shell Script).
REM ============================================================
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>&1

cd /d "%~dp0"

title Softy / Indeed - Automatisation
color 0B

cls
echo.
echo  ============================================================
echo.
echo           SOFTY  /  INDEED
echo           Automatisation des exports + comparaison
echo.
echo  ============================================================
echo.
echo  IMPORTANT : utilisez ce fichier .bat ^(Windows Batch File^).
echo  Ne pas ouvrir "run" de type Shell Script ^(c'est pour Mac^).
echo.

set "CDP_PORT=9222"
set "CDP_URL=http://localhost:9222"
set "CDP_WAIT_SECONDS=25"
set "LOGIN_WAIT_SECONDS=300"
set "CHROME_USER_DATA_DIR=%TEMP%\chrome-cdp-softyindeed"
set "USE_CDP=true"
set "HEADLESS=false"
set "BATCH_UI=1"
set "INDEED_HOME=https://employers.indeed.com/jobs"
set "SOFTY_HOME=https://v2.softy.pro/stats"
set "PYTHON_CMD="
set "EXIT_CODE=0"

set "CHROME_APP="
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "CHROME_APP=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if "%CHROME_APP%"=="" if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "CHROME_APP=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if "%CHROME_APP%"=="" if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" set "CHROME_APP=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"

echo  [.] Recherche de Python...
py -3 --version >nul 2>&1
if not errorlevel 1 (
  set "PYTHON_CMD=py -3"
) else (
  python --version >nul 2>&1
  if not errorlevel 1 (
    set "PYTHON_CMD=python"
  )
)

if "%PYTHON_CMD%"=="" (
  color 0C
  echo.
  echo  [ERREUR] Python introuvable.
  echo.
  echo  Installez Python 3.11+ depuis https://www.python.org/downloads/
  echo  Cochez bien "Add python.exe to PATH" pendant l'installation.
  echo.
  set "EXIT_CODE=1"
  goto :end_pause
)
echo  [OK] Python trouve : %PYTHON_CMD%
%PYTHON_CMD% --version

echo  [.] Preparation de l'environnement Windows...
if exist ".venv\Scripts\python.exe" goto :venv_ok

REM .venv absent ou copie depuis Mac (pas de Scripts\) -> a recreer
if exist ".venv" (
  echo  [!] Ancien .venv incompatible detecte ^(souvent copie depuis Mac^).
  echo      Recreation d'un .venv Windows...
  rmdir /s /q ".venv" 2>nul
)

%PYTHON_CMD% -m venv .venv
if errorlevel 1 (
  color 0C
  echo  [ERREUR] Impossible de creer .venv
  set "EXIT_CODE=1"
  goto :end_pause
)

:venv_ok
if not exist ".venv\Scripts\activate.bat" (
  color 0C
  echo  [ERREUR] .venv\Scripts\activate.bat introuvable.
  set "EXIT_CODE=1"
  goto :end_pause
)

call ".venv\Scripts\activate.bat"
if errorlevel 1 (
  color 0C
  echo  [ERREUR] Activation .venv impossible
  set "EXIT_CODE=1"
  goto :end_pause
)

if not exist "requirements.txt" (
  color 0C
  echo  [ERREUR] requirements.txt introuvable dans ce dossier.
  set "EXIT_CODE=1"
  goto :end_pause
)

echo  [.] Installation des dependances ^(peut prendre 1-2 min la 1ere fois^)...
python -m pip install -q --upgrade pip
python -m pip install -q -r requirements.txt
if errorlevel 1 (
  color 0C
  echo  [ERREUR] Echec pip install
  set "EXIT_CODE=1"
  goto :end_pause
)

echo  [.] Installation Playwright Chromium...
python -m playwright install chromium
if errorlevel 1 (
  color 0C
  echo  [ERREUR] Echec playwright install chromium
  set "EXIT_CODE=1"
  goto :end_pause
)
echo  [OK] Environnement pret

if not exist ".env" (
  if exist ".env.example" (
    copy /Y ".env.example" ".env" >nul
    echo.
    echo  [!] Fichier .env cree depuis .env.example
    echo      Ouvrez .env, verifiez les identifiants, puis relancez LANCER.bat
    echo.
    set "EXIT_CODE=1"
    goto :end_pause
  )
  color 0C
  echo  [ERREUR] Ni .env ni .env.example trouves.
  set "EXIT_CODE=1"
  goto :end_pause
)

for /f "usebackq eol=# tokens=1* delims==" %%A in (".env") do (
  if not "%%A"=="" set "%%A=%%B"
)

if not "%CDP_PORT%"=="" set "CDP_URL=http://localhost:%CDP_PORT%"
if "%CDP_URL%"=="" set "CDP_URL=http://localhost:9222"
if "%CDP_WAIT_SECONDS%"=="" set "CDP_WAIT_SECONDS=25"
if "%LOGIN_WAIT_SECONDS%"=="" set "LOGIN_WAIT_SECONDS=300"
if "%USE_CDP%"=="" set "USE_CDP=true"
if "%HEADLESS%"=="" set "HEADLESS=false"
if not "%INDEED_LOGIN_URL%"=="" set "INDEED_HOME=%INDEED_LOGIN_URL%"
if not "%SOFTY_LOGIN_URL%"=="" set "SOFTY_HOME=https://v2.softy.pro/stats"

echo.%CHROME_USER_DATA_DIR% | findstr /B /C:"/tmp/" >nul
if not errorlevel 1 set "CHROME_USER_DATA_DIR="
if "%CHROME_USER_DATA_DIR%"=="" set "CHROME_USER_DATA_DIR=%TEMP%\chrome-cdp-softyindeed"

set "MAIN_ARGS="

if /I not "%USE_CDP%"=="true" goto :run_python

echo  [.] Verification Chrome CDP...
call :is_cdp_ready
if not errorlevel 1 (
  echo  [OK] Chrome CDP deja disponible
  goto :wait_login
)

if "%CHROME_APP%"=="" (
  color 0C
  echo  [ERREUR] Google Chrome introuvable.
  set "EXIT_CODE=1"
  goto :end_pause
)

if not exist "%CHROME_USER_DATA_DIR%" mkdir "%CHROME_USER_DATA_DIR%"
echo  [.] Ouverture de Chrome ^(fenetre dediee^)...
start "" "%CHROME_APP%" --remote-debugging-port=%CDP_PORT% --user-data-dir="%CHROME_USER_DATA_DIR%" --new-window "%INDEED_HOME%" "%SOFTY_HOME%"

call :wait_for_cdp
if errorlevel 1 (
  color 0C
  echo  [ERREUR] Impossible de joindre Chrome sur %CDP_URL%
  echo           Fermez toutes les fenetres Chrome puis relancez.
  set "EXIT_CODE=1"
  goto :end_pause
)
echo  [OK] Chrome CDP pret

:wait_login
echo.
echo  ============================================================
echo   Connexion Indeed Employeur + Softy dans Chrome
echo.
echo   Si un code 2FA apparait :
echo     1. Validez-le dans Chrome
echo     2. Ne fermez PAS cette fenetre noire
echo     3. N'appuyez sur rien ici — attente automatique
echo  ============================================================
echo.

call :wait_for_authenticated_tabs
if errorlevel 1 (
  color 0C
  echo  [ERREUR] Sessions non detectees a temps.
  echo           Connectez-vous dans Chrome puis relancez LANCER.bat
  set "EXIT_CODE=1"
  goto :end_pause
)
echo  [OK] Sessions Indeed et Softy detectees

set "MAIN_ARGS=--cdp --cdp-url %CDP_URL%"
if not "%INDEED_ATTACH_URL%"=="" set "MAIN_ARGS=!MAIN_ARGS! --indeed-url !INDEED_ATTACH_URL!"
if not "%SOFTY_ATTACH_URL%"=="" set "MAIN_ARGS=!MAIN_ARGS! --softy-url !SOFTY_ATTACH_URL!"

:run_python
echo.
echo  [.] Export Softy + Indeed + comparaison...
echo.
set "HEADLESS=%HEADLESS%"
set "BATCH_UI=1"
python main.py %MAIN_ARGS%
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if exist "downloads\rapport_comparaison.txt" (
  echo  ============================================================
  echo                       RAPPORT FINAL
  echo  ============================================================
  echo.
  type "downloads\rapport_comparaison.txt"
  echo.
  echo  ------------------------------------------------------------
  echo   Fichier : downloads\rapport_comparaison.txt
  echo  ------------------------------------------------------------
) else (
  echo  [!] Aucun rapport genere.
)

echo.
if "%EXIT_CODE%"=="0" (
  color 0A
  echo  RESULTAT : aucune difference detectee.
) else if exist "downloads\rapport_comparaison.txt" (
  color 0E
  echo  RESULTAT : des ecarts ont ete detectes ^(voir rapport^).
) else (
  color 0C
  echo  RESULTAT : echec ^(code %EXIT_CODE%^).
)

:end_pause
echo.
echo  Appuyez sur une touche pour fermer...
pause >nul
exit /b %EXIT_CODE%

:is_cdp_ready
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { (Invoke-WebRequest -UseBasicParsing '%CDP_URL%/json/version' -TimeoutSec 2).StatusCode | Out-Null; exit 0 } catch { exit 1 }"
exit /b %ERRORLEVEL%

:wait_for_cdp
set /a ELAPSED=0
:wait_cdp_loop
call :is_cdp_ready
if not errorlevel 1 exit /b 0
if !ELAPSED! GEQ %CDP_WAIT_SECONDS% exit /b 1
timeout /t 1 /nobreak >nul
set /a ELAPSED+=1
goto wait_cdp_loop

:wait_for_authenticated_tabs
set /a ELAPSED=0
set "WARNED=0"
:wait_auth_loop
powershell -NoProfile -ExecutionPolicy Bypass -Command "$tabs=@(); try { $tabs=Invoke-RestMethod -Uri '%CDP_URL%/json/list' -TimeoutSec 2 } catch { exit 2 }; $indeed=$tabs | Where-Object { $_.url -match 'employers\.indeed\.com' -and $_.url -notmatch 'login|account\.indeed' } | Select-Object -First 1; $softy=$tabs | Where-Object { $_.url -match 'softy\.pro' -and $_.url -notmatch 'login' } | Select-Object -First 1; if ($indeed -and $softy) { exit 0 } else { exit 1 }"
if not errorlevel 1 exit /b 0
if "!WARNED!"=="0" (
  echo  [..] En attente de connexion dans Chrome...
  echo       Validez le 2FA si demande.
  set "WARNED=1"
)
if !ELAPSED! GEQ %LOGIN_WAIT_SECONDS% exit /b 1
timeout /t 2 /nobreak >nul
set /a ELAPSED+=2
goto wait_auth_loop
