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
set "CDP_WAIT_SECONDS=60"
set "LOGIN_WAIT_SECONDS=300"
set "CHROME_USER_DATA_DIR=%TEMP%\chrome-cdp-softyindeed"
set "USE_CDP=true"
set "HEADLESS=false"
set "BATCH_UI=1"
set "PYTHON_CMD="

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
  echo  Installez Python depuis https://www.python.org/downloads/
  echo  Cochez "Add python.exe to PATH", puis relancez.
  echo.
  echo  Test :  py -3 --version
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
if not defined CDP_WAIT_SECONDS set "CDP_WAIT_SECONDS=60"
if not defined USE_CDP set "USE_CDP=true"
if not defined HEADLESS set "HEADLESS=false"

echo.!CHROME_USER_DATA_DIR! | findstr /B /C:"/tmp/" >nul
if not errorlevel 1 set "CHROME_USER_DATA_DIR="
if not defined CHROME_USER_DATA_DIR set "CHROME_USER_DATA_DIR=%TEMP%\chrome-cdp-softyindeed"

set "MAIN_ARGS="
if /I "!USE_CDP!"=="true" (
  set "MAIN_ARGS=--cdp --cdp-url !CDP_URL!"
  if defined INDEED_ATTACH_URL set "MAIN_ARGS=!MAIN_ARGS! --indeed-url !INDEED_ATTACH_URL!"
  if defined SOFTY_ATTACH_URL set "MAIN_ARGS=!MAIN_ARGS! --softy-url !SOFTY_ATTACH_URL!"
)

echo.
echo  ============================================================
echo   Le script va :
echo     1. Ouvrir Chrome tout seul ^(Indeed + Softy^)
echo     2. Attendre votre 2FA si besoin
echo     3. Exporter et comparer automatiquement
echo     4. Afficher le rapport ici
echo.
echo   Si un code 2FA apparait dans Chrome :
echo     - Validez-le dans Chrome
echo     - Ne fermez PAS cette fenetre noire
echo  ============================================================
echo.

set "HEADLESS=!HEADLESS!"
set "BATCH_UI=1"
set "CDP_WAIT_SECONDS=!CDP_WAIT_SECONDS!"
set "CHROME_USER_DATA_DIR=!CHROME_USER_DATA_DIR!"

echo  [.] Lancement de l'automatisation...
echo.
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
