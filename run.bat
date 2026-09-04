@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

cd /d "%~dp0"

title Softy / Indeed — Automatisation
color 0B
mode con: cols=100 lines=40 >nul 2>&1

call :banner

set "CDP_PORT=9222"
set "CDP_URL=http://localhost:%CDP_PORT%"
set "CDP_WAIT_SECONDS=20"
set "LOGIN_WAIT_SECONDS=300"
set "CHROME_USER_DATA_DIR=%TEMP%\chrome-cdp-softyindeed"
set "USE_CDP=true"
set "HEADLESS=false"
set "BATCH_UI=1"
set "INDEED_HOME=https://employers.indeed.com/jobs"
set "SOFTY_HOME=https://v2.softy.pro/stats"

set "CHROME_APP="
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" (
  set "CHROME_APP=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
) else if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" (
  set "CHROME_APP=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
) else if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" (
  set "CHROME_APP=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"
)

call :step "Verification de Python..."
where python >nul 2>&1
if errorlevel 1 (
  where py >nul 2>&1
  if errorlevel 1 (
    call :fail "Python introuvable. Installez Python 3.11+ et cochez Add to PATH."
  )
  set "PYTHON=py -3"
) else (
  set "PYTHON=python"
)
call :ok "Python OK"

call :step "Preparation de l'environnement..."
if not exist ".venv" (
  %PYTHON% -m venv .venv
  if errorlevel 1 call :fail "Impossible de creer .venv"
)
call ".venv\Scripts\activate.bat"
if errorlevel 1 call :fail "Impossible d'activer .venv"
python -m pip install -q -r requirements.txt
if errorlevel 1 call :fail "Echec installation des dependances"
python -m playwright install chromium >nul
if errorlevel 1 call :fail "Echec installation Playwright Chromium"
call :ok "Environnement pret"

if not exist ".env" (
  copy /Y ".env.example" ".env" >nul
  echo.
  echo  [!] Fichier .env cree a partir de .env.example
  echo      Editez vos identifiants, puis relancez run.bat
  echo.
  pause
  exit /b 1
)

for /f "usebackq eol=# tokens=1* delims==" %%A in (".env") do (
  if not "%%A"=="" set "%%A=%%B"
)

if "%CDP_PORT%"=="" set "CDP_PORT=9222"
if "%CDP_URL%"=="" set "CDP_URL=http://localhost:%CDP_PORT%"
if "%CDP_WAIT_SECONDS%"=="" set "CDP_WAIT_SECONDS=20"
if "%LOGIN_WAIT_SECONDS%"=="" set "LOGIN_WAIT_SECONDS=300"
if "%USE_CDP%"=="" set "USE_CDP=true"
if "%HEADLESS%"=="" set "HEADLESS=false"
if not "%INDEED_LOGIN_URL%"=="" set "INDEED_HOME=%INDEED_LOGIN_URL%"
if not "%SOFTY_LOGIN_URL%"=="" (
  set "SOFTY_HOME=%SOFTY_LOGIN_URL%"
  echo.!SOFTY_HOME! | findstr /I "login" >nul
  if not errorlevel 1 set "SOFTY_HOME=https://v2.softy.pro/stats"
)

echo.%CHROME_USER_DATA_DIR% | findstr /B /C:"/tmp/" >nul
if not errorlevel 1 set "CHROME_USER_DATA_DIR="
if "%CHROME_USER_DATA_DIR%"=="" set "CHROME_USER_DATA_DIR=%TEMP%\chrome-cdp-softyindeed"

set "MAIN_ARGS="

if /I not "%USE_CDP%"=="true" goto :run_python

call :step "Verification de Chrome CDP..."
call :is_cdp_ready
if not errorlevel 1 (
  call :ok "Chrome CDP deja disponible"
  goto :wait_login
)

if "%CHROME_APP%"=="" call :fail "Google Chrome introuvable sur ce PC."

if not exist "%CHROME_USER_DATA_DIR%" mkdir "%CHROME_USER_DATA_DIR%"
call :step "Ouverture de Chrome ^(profil CDP separe^)..."
start "" "%CHROME_APP%" --remote-debugging-port=%CDP_PORT% --user-data-dir="%CHROME_USER_DATA_DIR%" --new-window "%INDEED_HOME%" "%SOFTY_HOME%"

call :wait_for_cdp
if errorlevel 1 call :fail "Impossible de joindre Chrome sur %CDP_URL%."
call :ok "Chrome CDP pret"

:wait_login
call :step "Verification des sessions Indeed / Softy..."
echo.
echo  ============================================================
echo   Si un code 2FA / authenticator s'affiche dans Chrome :
echo     1. Validez-le dans la fenetre Chrome
echo     2. Laissez cette fenetre ouverte
echo     3. N'appuyez sur rien ici — le script attend tout seul
echo  ============================================================
echo.

call :wait_for_authenticated_tabs
if errorlevel 1 call :fail "Sessions Indeed / Softy non detectees a temps. Relancez apres connexion."
call :ok "Sessions Indeed et Softy detectees"

set "MAIN_ARGS=--cdp --cdp-url %CDP_URL%"
if not "%INDEED_ATTACH_URL%"=="" set "MAIN_ARGS=!MAIN_ARGS! --indeed-url %INDEED_ATTACH_URL%"
if not "%SOFTY_ATTACH_URL%"=="" set "MAIN_ARGS=!MAIN_ARGS! --softy-url %SOFTY_ATTACH_URL%"

:run_python
echo.
call :step "Export Softy + Indeed + comparaison en cours..."
echo.
set "HEADLESS=%HEADLESS%"
set "BATCH_UI=1"
python main.py %MAIN_ARGS% %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if exist "downloads\rapport_comparaison.txt" (
  call :banner_result
  type "downloads\rapport_comparaison.txt"
  echo.
  echo  ------------------------------------------------------------
  echo   Rapport enregistre : downloads\rapport_comparaison.txt
  echo  ------------------------------------------------------------
) else (
  echo  [!] Aucun rapport de comparaison trouve.
)

echo.
if "%EXIT_CODE%"=="0" (
  color 0A
  echo  RESULTAT : aucune difference detectee.
) else if exist "downloads\rapport_comparaison.txt" (
  color 0E
  echo  RESULTAT : des ecarts ont ete detectes ^(voir le rapport ci-dessus^).
) else (
  color 0C
  echo  RESULTAT : echec de l'automatisation ^(code %EXIT_CODE%^).
)

echo.
echo  Appuyez sur une touche pour fermer...
pause >nul
exit /b %EXIT_CODE%

:banner
cls
echo.
echo  ============================================================
echo.
echo           SOFTY  /  INDEED
echo           Automatisation des exports + comparaison
echo.
echo  ============================================================
echo.
exit /b 0

:banner_result
echo.
echo  ============================================================
echo                       RAPPORT FINAL
echo  ============================================================
echo.
exit /b 0

:step
echo  [.] %~1
exit /b 0

:ok
echo  [OK] %~1
exit /b 0

:fail
color 0C
echo.
echo  [ERREUR] %~1
echo.
echo  Appuyez sur une touche pour fermer...
pause >nul
exit 1

:is_cdp_ready
powershell -NoProfile -Command "try { (Invoke-WebRequest -UseBasicParsing '%CDP_URL%/json/version' -TimeoutSec 2).StatusCode | Out-Null; exit 0 } catch { exit 1 }"
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
powershell -NoProfile -Command ^
  "$tabs = @(); try { $tabs = Invoke-RestMethod -Uri '%CDP_URL%/json/list' -TimeoutSec 2 } catch { exit 2 };" ^
  "$indeed = $tabs | Where-Object { $_.url -match 'employers\.indeed\.com' -and $_.url -notmatch 'login|account\.indeed' } | Select-Object -First 1;" ^
  "$softy  = $tabs | Where-Object { $_.url -match 'softy\.pro' -and $_.url -notmatch 'login' } | Select-Object -First 1;" ^
  "if ($indeed -and $softy) { exit 0 } else { exit 1 }"
if not errorlevel 1 exit /b 0

if "!WARNED!"=="0" (
  echo  [..] En attente de connexion dans Chrome...
  echo       Validez le 2FA si demande, le script reprendra automatiquement.
  set "WARNED=1"
)

if !ELAPSED! GEQ %LOGIN_WAIT_SECONDS% exit /b 1
timeout /t 2 /nobreak >nul
set /a ELAPSED+=2
goto wait_auth_loop
