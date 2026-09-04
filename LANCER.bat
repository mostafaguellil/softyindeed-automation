@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Keep window open always
if /I not "%~1"=="__RUN__" (
  cmd /k "cd /d "%~dp0" && "%~f0" __RUN__"
  exit /b
)

cd /d "%~dp0"
title Softy Indeed Windows
color 0B

echo.
echo ============================================================
echo   SOFTY / INDEED - LANCEUR WINDOWS
echo ============================================================
echo   Dossier: %CD%
echo.

set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY where python >nul 2>&1 && set "PY=python"
if not defined PY (
  echo [ERREUR] Python introuvable. Installez Python 3.10+ avec PATH.
  goto END
)

echo [1/4] Python OK
%PY% --version

if not exist ".venv\Scripts\python.exe" (
  echo [2/4] Creation .venv ...
  if exist ".venv" rmdir /s /q ".venv" 2>nul
  %PY% -m venv .venv
  if errorlevel 1 (
    echo [ERREUR] venv impossible
    goto END
  )
) else (
  echo [2/4] .venv OK
)

set "VPY=%CD%\.venv\Scripts\python.exe"

echo [3/4] Installation dependances...
"%VPY%" -m pip install -q --upgrade pip
"%VPY%" -m pip install -q -r requirements.txt
if errorlevel 1 (
  echo [ERREUR] pip install
  goto END
)
echo     Playwright Chromium...
"%VPY%" -m playwright install chromium
if errorlevel 1 (
  echo [ERREUR] playwright install chromium
  goto END
)
echo     Playwright Chrome channel helper...
"%VPY%" -m playwright install chrome >nul 2>&1

if not exist ".env" if exist ".env.example" copy /Y ".env.example" ".env" >nul

echo [4/4] Lancement automatisation...
echo.
echo   Chrome/Chromium va s'ouvrir.
echo   Si 2FA : validez-le dans le navigateur.
echo   Le rapport s'affichera ici a la fin.
echo.
echo   Ne fermez PAS cette fenetre.
echo.

"%VPY%" -u windows_run.py
set "ERR=%ERRORLEVEL%"
echo.
echo Code sortie: %ERR%
if exist "downloads\rapport_comparaison.txt" (
  echo.
  echo ========== RAPPORT ==========
  type "downloads\rapport_comparaison.txt"
  echo =============================
)

:END
echo.
echo ============================================================
echo   Pour fermer: tapez exit puis Entree
echo ============================================================
