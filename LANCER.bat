@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Keep the window open even if something fails (double-click safe)
if /I not "%~1"=="__KEEP_OPEN__" (
  cmd /k call "%~f0" __KEEP_OPEN__
  exit /b
)

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

echo  [1/5] Recherche de Python...
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
  echo.
  echo  [ERREUR] Python 3.10+ introuvable dans le PATH.
  echo  Installez Python et cochez "Add python.exe to PATH".
  echo  Testez dans cmd :  py -3 --version
  echo.
  set "EXIT_CODE=1"
  goto FIN
)
echo  [OK] Python : %PYTHON_CMD%
echo.

echo  [2/5] Environnement virtuel...
if not exist ".venv\Scripts\python.exe" (
  if exist ".venv" (
    echo  Suppression ancien .venv incompatible...
    rmdir /s /q ".venv" 2>nul
  )
  echo  Creation de .venv ...
  %PYTHON_CMD% -m venv .venv
  if errorlevel 1 (
    color 0C
    echo  [ERREUR] Impossible de creer .venv
    set "EXIT_CODE=1"
    goto FIN
  )
)

set "VENV_PY=%CD%\.venv\Scripts\python.exe"
if not exist "%VENV_PY%" (
  color 0C
  echo  [ERREUR] Introuvable : %VENV_PY%
  set "EXIT_CODE=1"
  goto FIN
)
echo  [OK] %VENV_PY%
echo.

echo  [3/5] Dependances Python...
if not exist "requirements.txt" (
  color 0C
  echo  [ERREUR] requirements.txt manquant
  set "EXIT_CODE=1"
  goto FIN
)
"%VENV_PY%" -m pip install -q --upgrade pip
if errorlevel 1 (
  color 0C
  echo  [ERREUR] pip upgrade a echoue
  set "EXIT_CODE=1"
  goto FIN
)
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
echo  [OK] Dependances installees
echo.

echo  [4/5] Fichier .env ...
if not exist ".env" (
  if exist ".env.example" (
    copy /Y ".env.example" ".env" >nul
    echo  [!] .env cree depuis .env.example
    echo      Editez .env avec vos identifiants puis relancez.
    set "EXIT_CODE=1"
    goto FIN
  )
  color 0C
  echo  [ERREUR] .env et .env.example absents
  set "EXIT_CODE=1"
  goto FIN
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
echo  [OK] Configuration chargee
echo.

echo  ============================================================
echo   [5/5] Automatisation
echo.
echo   - Ouverture Chrome Indeed + Softy
echo   - Attente 2FA si besoin ^(validez dans Chrome^)
echo   - Exports + comparaison
echo   - Affichage du rapport ici
echo.
echo   Ne fermez PAS cette fenetre.
echo  ============================================================
echo.

set "HEADLESS=!HEADLESS!"
set "BATCH_UI=1"
set "CDP_WAIT_SECONDS=!CDP_WAIT_SECONDS!"
set "CHROME_USER_DATA_DIR=!CHROME_USER_DATA_DIR!"

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
  echo                       PAS DE RAPPORT
  echo  ============================================================
  echo.
  echo  L'automatisation n'a pas produit de rapport.
  echo  Regardez les messages d'erreur ci-dessus.
)

echo.
if "!EXIT_CODE!"=="0" (
  color 0A
  echo  RESULTAT : aucune difference detectee.
) else if exist "downloads\rapport_comparaison.txt" (
  color 0E
  echo  RESULTAT : des ecarts ont ete detectes.
) else (
  color 0C
  echo  RESULTAT : echec ^(code !EXIT_CODE!^).
)

:FIN
echo.
echo  ============================================================
echo   Termine. La fenetre reste ouverte.
echo   Tapez  exit  puis Entree pour fermer.
echo  ============================================================
echo.
