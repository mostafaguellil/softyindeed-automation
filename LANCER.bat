@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM  Always keep window open + stay in project folder
REM ============================================================
if /I not "%~1"=="__KEEP_OPEN__" (
  cmd /k "cd /d "%~dp0" && "%~f0" __KEEP_OPEN__"
  exit /b
)

cd /d "%~dp0"
title Softy / Indeed - Automatisation
color 0B

cls
echo.
echo  ============================================================
echo           SOFTY  /  INDEED  -  LANCEUR WINDOWS
echo  ============================================================
echo  Dossier : %CD%
echo.

set "EXIT_CODE=0"
set "CDP_PORT=9222"
set "CDP_URL=http://localhost:9222"
set "CDP_WAIT_SECONDS=60"
set "CHROME_USER_DATA_DIR=%TEMP%\chrome-cdp-softyindeed"
set "USE_CDP=true"
set "HEADLESS=false"
set "BATCH_UI=1"
set "PYTHON_CMD="
set "VENV_PY="
set "MAIN_ARGS="

echo  [1/5] Python...
where py >nul 2>&1
if !ERRORLEVEL! EQU 0 (
  py -3 -c "import sys; print(sys.version)" 2>nul
  if !ERRORLEVEL! EQU 0 set "PYTHON_CMD=py -3"
)
if not defined PYTHON_CMD (
  where python >nul 2>&1
  if !ERRORLEVEL! EQU 0 (
    python -c "import sys; print(sys.version)" 2>nul
    if !ERRORLEVEL! EQU 0 set "PYTHON_CMD=python"
  )
)
if not defined PYTHON_CMD (
  color 0C
  echo  [ERREUR] Python introuvable. Installez Python 3.10+ avec PATH.
  set "EXIT_CODE=1"
  goto FIN
)
echo  [OK] %PYTHON_CMD%
echo.

echo  [2/5] Environnement .venv...
if not exist ".venv\Scripts\python.exe" (
  if exist ".venv" rmdir /s /q ".venv" 2>nul
  %PYTHON_CMD% -m venv .venv
  if errorlevel 1 (
    color 0C
    echo  [ERREUR] Creation .venv impossible
    set "EXIT_CODE=1"
    goto FIN
  )
)
set "VENV_PY=%CD%\.venv\Scripts\python.exe"
if not exist "%VENV_PY%" (
  color 0C
  echo  [ERREUR] %VENV_PY% introuvable
  set "EXIT_CODE=1"
  goto FIN
)
echo  [OK] %VENV_PY%
echo.

echo  [3/5] Dependances...
if not exist "requirements.txt" (
  color 0C
  echo  [ERREUR] requirements.txt manquant
  set "EXIT_CODE=1"
  goto FIN
)
"%VENV_PY%" -m pip install -q --upgrade pip
"%VENV_PY%" -m pip install -q -r requirements.txt
if errorlevel 1 (
  color 0C
  echo  [ERREUR] pip install a echoue
  set "EXIT_CODE=1"
  goto FIN
)
"%VENV_PY%" -m playwright install chromium
if errorlevel 1 (
  color 0C
  echo  [ERREUR] playwright install a echoue
  set "EXIT_CODE=1"
  goto FIN
)
echo  [OK] Dependances OK
echo.

echo  [4/5] Configuration .env...
if not exist ".env" (
  if not exist ".env.example" (
    color 0C
    echo  [ERREUR] .env.example manquant
    set "EXIT_CODE=1"
    goto FIN
  )
  copy /Y ".env.example" ".env" >nul
  echo  [OK] .env cree automatiquement depuis .env.example
) else (
  echo  [OK] .env deja present
)

REM Load .env values
for /f "usebackq eol=# tokens=1* delims==" %%A in (".env") do (
  if not "%%A"=="" set "%%A=%%B"
)

if defined CDP_PORT set "CDP_URL=http://localhost:!CDP_PORT!"
if not defined CDP_URL set "CDP_URL=http://localhost:9222"
if not defined CDP_WAIT_SECONDS set "CDP_WAIT_SECONDS=60"
if not defined USE_CDP set "USE_CDP=true"
if not defined HEADLESS set "HEADLESS=false"
if not defined INDEED_ATTACH_URL set "INDEED_ATTACH_URL=employers.indeed.com"
if not defined SOFTY_ATTACH_URL set "SOFTY_ATTACH_URL=softy.pro"

echo.!CHROME_USER_DATA_DIR! | findstr /B /C:"/tmp/" >nul
if not errorlevel 1 set "CHROME_USER_DATA_DIR="
if not defined CHROME_USER_DATA_DIR set "CHROME_USER_DATA_DIR=%TEMP%\chrome-cdp-softyindeed"

if /I "!USE_CDP!"=="true" (
  set "MAIN_ARGS=--cdp --cdp-url !CDP_URL! --indeed-url !INDEED_ATTACH_URL! --softy-url !SOFTY_ATTACH_URL!"
)

echo  [OK] CDP=!CDP_URL!
echo.

echo  ============================================================
echo  [5/5] AUTOMATISATION EN COURS
echo.
echo   1. Ouverture Chrome Indeed + Softy
echo   2. Si 2FA : validez-le dans Chrome, attente auto ici
echo   3. Exports + comparaison
echo   4. Rapport affiche ci-dessous
echo.
echo   Ne fermez PAS cette fenetre.
echo  ============================================================
echo.

set "HEADLESS=!HEADLESS!"
set "BATCH_UI=1"
set "CDP_WAIT_SECONDS=!CDP_WAIT_SECONDS!"
set "CHROME_USER_DATA_DIR=!CHROME_USER_DATA_DIR!"
set "CDP_URL=!CDP_URL!"
set "USE_CDP=!USE_CDP!"

"%VENV_PY%" -u main.py !MAIN_ARGS!
set "EXIT_CODE=!ERRORLEVEL!"

echo.
echo  ============================================================
if exist "downloads\rapport_comparaison.txt" (
  echo                       RAPPORT FINAL
  echo  ============================================================
  echo.
  type "downloads\rapport_comparaison.txt"
  echo.
  echo  Fichier : %CD%\downloads\rapport_comparaison.txt
) else (
  echo                       ECHEC / PAS DE RAPPORT
  echo  ============================================================
  echo.
  echo  Aucun rapport genere. Messages d'erreur ci-dessus.
  if exist "downloads\debug_erreur.png" (
    echo  Capture : %CD%\downloads\debug_erreur.png
  )
)

echo.
if "!EXIT_CODE!"=="0" (
  color 0A
  echo  RESULTAT : OK - aucune difference.
) else if exist "downloads\rapport_comparaison.txt" (
  color 0E
  echo  RESULTAT : ecarts detectes ^(voir rapport^).
) else (
  color 0C
  echo  RESULTAT : echec code !EXIT_CODE!.
)

:FIN
echo.
echo  ============================================================
echo   Fini. Fenetre ouverte volontairement.
echo   Pour fermer : tapez exit puis Entree.
echo  ============================================================
echo.
cd /d "%~dp0"
