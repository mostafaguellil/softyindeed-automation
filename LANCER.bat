@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ASCII-only batch file (accents break Windows CMD when UTF-8)

cd /d "%~dp0"

title Softy / Indeed - Automatisation
color 0B

cls
echo.
echo  ============================================================
echo.
echo           SOFTY  /  INDEED
echo           Exports + comparaison automatique
echo.
echo  ============================================================
echo.
echo  Lanceur Windows : LANCER.bat
echo  (ne pas ouvrir run.sh - reserve a Mac/Linux)
echo.

set "EXIT_CODE=0"
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
set "CHROME_APP="

if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" (
  set "CHROME_APP=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
)
if not defined CHROME_APP if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" (
  set "CHROME_APP=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
)
if not defined CHROME_APP if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" (
  set "CHROME_APP=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"
)

echo  [.] Recherche de Python...

where py >nul 2>&1
if %ERRORLEVEL%==0 (
  py -3 -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)" >nul 2>&1
  if !ERRORLEVEL!==0 (
    set "PYTHON_CMD=py -3"
  )
)

if not defined PYTHON_CMD (
  where python >nul 2>&1
  if !ERRORLEVEL!==0 (
    python -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)" >nul 2>&1
    if !ERRORLEVEL!==0 (
      set "PYTHON_CMD=python"
    )
  )
)

if not defined PYTHON_CMD (
  color 0C
  echo.
  echo  [ERREUR] Python 3.10+ introuvable dans le PATH.
  echo.
  echo  Python peut etre installe sans etre dans le PATH.
  echo  Solutions :
  echo    1. Reinstallez Python depuis https://www.python.org/downloads/
  echo    2. Cochez "Add python.exe to PATH"
  echo    3. Rouvrez cette fenetre puis relancez LANCER.bat
  echo.
  echo  Test manuel : ouvrez cmd et tapez :  py -3 --version
  echo.
  set "EXIT_CODE=1"
  goto END_PAUSE
)

echo  [OK] Python trouve
call %PYTHON_CMD% --version
if errorlevel 1 (
  color 0C
  echo  [ERREUR] Python ne demarre pas correctement.
  set "EXIT_CODE=1"
  goto END_PAUSE
)

echo  [.] Preparation de l'environnement Windows...

if exist ".venv\Scripts\python.exe" goto VENV_OK

if exist ".venv" (
  echo  [!] Ancien .venv incompatible ^(souvent copie depuis Mac^).
  echo      Recreation d'un .venv Windows...
  rmdir /s /q ".venv" 2>nul
)

call %PYTHON_CMD% -m venv .venv
if errorlevel 1 (
  color 0C
  echo  [ERREUR] Impossible de creer .venv
  set "EXIT_CODE=1"
  goto END_PAUSE
)

:VENV_OK
if not exist ".venv\Scripts\python.exe" (
  color 0C
  echo  [ERREUR] .venv\Scripts\python.exe introuvable.
  set "EXIT_CODE=1"
  goto END_PAUSE
)

set "VENV_PY=%~dp0.venv\Scripts\python.exe"
set "VENV_PIP=%~dp0.venv\Scripts\pip.exe"

if not exist "requirements.txt" (
  color 0C
  echo  [ERREUR] requirements.txt introuvable dans :
  echo           %CD%
  set "EXIT_CODE=1"
  goto END_PAUSE
)

echo  [.] Installation des dependances ^(1-2 min la 1ere fois^)...
"%VENV_PY%" -m pip install -q --upgrade pip
if errorlevel 1 (
  color 0C
  echo  [ERREUR] Echec upgrade pip
  set "EXIT_CODE=1"
  goto END_PAUSE
)
"%VENV_PY%" -m pip install -q -r requirements.txt
if errorlevel 1 (
  color 0C
  echo  [ERREUR] Echec pip install -r requirements.txt
  set "EXIT_CODE=1"
  goto END_PAUSE
)

echo  [.] Installation Playwright Chromium...
"%VENV_PY%" -m playwright install chromium
if errorlevel 1 (
  color 0C
  echo  [ERREUR] Echec playwright install chromium
  set "EXIT_CODE=1"
  goto END_PAUSE
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
    goto END_PAUSE
  )
  color 0C
  echo  [ERREUR] Ni .env ni .env.example trouves.
  set "EXIT_CODE=1"
  goto END_PAUSE
)

for /f "usebackq eol=# tokens=1* delims==" %%A in (".env") do (
  if not "%%A"=="" set "%%A=%%B"
)

if defined CDP_PORT set "CDP_URL=http://localhost:!CDP_PORT!"
if not defined CDP_URL set "CDP_URL=http://localhost:9222"
if not defined CDP_WAIT_SECONDS set "CDP_WAIT_SECONDS=25"
if not defined LOGIN_WAIT_SECONDS set "LOGIN_WAIT_SECONDS=300"
if not defined USE_CDP set "USE_CDP=true"
if not defined HEADLESS set "HEADLESS=false"
if defined INDEED_LOGIN_URL set "INDEED_HOME=!INDEED_LOGIN_URL!"
set "SOFTY_HOME=https://v2.softy.pro/stats"

echo.!CHROME_USER_DATA_DIR! | findstr /B /C:"/tmp/" >nul
if not errorlevel 1 set "CHROME_USER_DATA_DIR="
if not defined CHROME_USER_DATA_DIR set "CHROME_USER_DATA_DIR=%TEMP%\chrome-cdp-softyindeed"

set "MAIN_ARGS="

if /I not "!USE_CDP!"=="true" goto RUN_PYTHON

echo  [.] Verification Chrome CDP...
call :IS_CDP_READY
if not errorlevel 1 (
  echo  [OK] Chrome CDP deja disponible
  goto WAIT_LOGIN
)

if not defined CHROME_APP (
  color 0C
  echo  [ERREUR] Google Chrome introuvable.
  set "EXIT_CODE=1"
  goto END_PAUSE
)

if not exist "!CHROME_USER_DATA_DIR!" mkdir "!CHROME_USER_DATA_DIR!"
echo  [.] Ouverture de Chrome ^(fenetre dediee^)...
start "" "!CHROME_APP!" --remote-debugging-port=!CDP_PORT! --user-data-dir="!CHROME_USER_DATA_DIR!" --new-window "!INDEED_HOME!" "!SOFTY_HOME!"

call :WAIT_FOR_CDP
if errorlevel 1 (
  color 0C
  echo  [ERREUR] Impossible de joindre Chrome sur !CDP_URL!
  echo           Fermez toutes les fenetres Chrome puis relancez.
  set "EXIT_CODE=1"
  goto END_PAUSE
)
echo  [OK] Chrome CDP pret

:WAIT_LOGIN
echo.
echo  ============================================================
echo   Connexion Indeed Employeur + Softy dans Chrome
echo.
echo   Si un code 2FA apparait :
echo     1. Validez-le dans Chrome
echo     2. Ne fermez PAS cette fenetre noire
echo     3. N'appuyez sur rien ici - attente automatique
echo  ============================================================
echo.

call :WAIT_FOR_AUTH_TABS
if errorlevel 1 (
  color 0C
  echo  [ERREUR] Sessions non detectees a temps.
  echo           Connectez-vous dans Chrome puis relancez LANCER.bat
  set "EXIT_CODE=1"
  goto END_PAUSE
)
echo  [OK] Sessions Indeed et Softy detectees

set "MAIN_ARGS=--cdp --cdp-url !CDP_URL!"
if defined INDEED_ATTACH_URL set "MAIN_ARGS=!MAIN_ARGS! --indeed-url !INDEED_ATTACH_URL!"
if defined SOFTY_ATTACH_URL set "MAIN_ARGS=!MAIN_ARGS! --softy-url !SOFTY_ATTACH_URL!"

:RUN_PYTHON
echo.
echo  [.] Export Softy + Indeed + comparaison...
echo.
set "HEADLESS=!HEADLESS!"
set "BATCH_UI=1"
"%VENV_PY%" main.py !MAIN_ARGS!
set "EXIT_CODE=!ERRORLEVEL!"

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
if "!EXIT_CODE!"=="0" (
  color 0A
  echo  RESULTAT : aucune difference detectee.
) else if exist "downloads\rapport_comparaison.txt" (
  color 0E
  echo  RESULTAT : des ecarts ont ete detectes ^(voir rapport^).
) else (
  color 0C
  echo  RESULTAT : echec ^(code !EXIT_CODE!^).
)

:END_PAUSE
echo.
echo  Appuyez sur une touche pour fermer...
pause >nul
exit /b !EXIT_CODE!

:IS_CDP_READY
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { (Invoke-WebRequest -UseBasicParsing '%CDP_URL%/json/version' -TimeoutSec 2).StatusCode | Out-Null; exit 0 } catch { exit 1 }"
exit /b %ERRORLEVEL%

:WAIT_FOR_CDP
set /a ELAPSED=0
:WAIT_CDP_LOOP
call :IS_CDP_READY
if not errorlevel 1 exit /b 0
if !ELAPSED! GEQ !CDP_WAIT_SECONDS! exit /b 1
timeout /t 1 /nobreak >nul
set /a ELAPSED+=1
goto WAIT_CDP_LOOP

:WAIT_FOR_AUTH_TABS
set /a ELAPSED=0
set "WARNED=0"
:WAIT_AUTH_LOOP
powershell -NoProfile -ExecutionPolicy Bypass -Command "$tabs=@(); try { $tabs=Invoke-RestMethod -Uri '%CDP_URL%/json/list' -TimeoutSec 2 } catch { exit 2 }; $indeed=$tabs | Where-Object { $_.url -match 'employers\.indeed\.com' -and $_.url -notmatch 'login|account\.indeed' } | Select-Object -First 1; $softy=$tabs | Where-Object { $_.url -match 'softy\.pro' -and $_.url -notmatch 'login' } | Select-Object -First 1; if ($indeed -and $softy) { exit 0 } else { exit 1 }"
if not errorlevel 1 exit /b 0
if "!WARNED!"=="0" (
  echo  [..] En attente de connexion dans Chrome...
  echo       Validez le 2FA si demande.
  set "WARNED=1"
)
if !ELAPSED! GEQ !LOGIN_WAIT_SECONDS! exit /b 1
timeout /t 2 /nobreak >nul
set /a ELAPSED+=2
goto WAIT_AUTH_LOOP
