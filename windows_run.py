"""
Lanceur Windows tout-en-un.

Evite le mode CDP (souvent casse sous Windows) :
utilise Chrome via Playwright persistent context.
"""

from __future__ import annotations

import os
import sys
import tempfile
import time
import traceback
from pathlib import Path
from urllib.parse import urlparse

from dotenv import load_dotenv
from playwright.sync_api import sync_playwright

# Ensure project root is on sys.path when launched as a script
ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from src.browser import DEFAULT_TIMEOUT_MS, _page_looks_authenticated, save_debug_screenshot
from src.compare import compare_exports, format_report
from src.config import Settings
from src.env_check import ensure_env_file
from src.generate import generate_all_exports, print_generated_files


def _print(msg: str = "") -> None:
    print(msg, flush=True)


def _profile_dir() -> Path:
    env_dir = os.getenv("CHROME_USER_DATA_DIR", "").strip()
    if env_dir and not env_dir.startswith("/tmp/"):
        path = Path(env_dir)
    else:
        path = Path(tempfile.gettempdir()) / "softyindeed-chrome-profile"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _softy_home(settings: Settings) -> str:
    url = settings.softy_login_url or "https://v2.softy.pro/stats"
    parsed = urlparse(url)
    if "login" in parsed.path.lower() or parsed.path in ("", "/"):
        return f"{parsed.scheme}://{parsed.netloc}/stats"
    return url


def _indeed_home(settings: Settings) -> str:
    return settings.indeed_login_url or "https://employers.indeed.com/jobs"


def _wait_login(page, kind: str, label: str, seconds: int = 300) -> None:
    if _page_looks_authenticated(page, kind):
        _print(f"[OK] Session {label} deja connectee")
        return

    _print("")
    _print("=" * 60)
    _print(f"  Connexion {label} requise")
    _print("  Si un code 2FA apparait dans Chrome : validez-le maintenant.")
    _print("  Cette fenetre attend automatiquement...")
    _print("=" * 60)
    _print("")

    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if _page_looks_authenticated(page, kind):
            _print(f"[OK] Session {label} detectee")
            return
        page.wait_for_timeout(2000)

    raise RuntimeError(f"Session {label} non detectee a temps.")


def run() -> int:
    os.chdir(ROOT)
    ensure_env_file()
    load_dotenv(override=True)

    settings = Settings.from_env(cdp_url=None)
    settings.download_dir.mkdir(parents=True, exist_ok=True)

    indeed_url = _indeed_home(settings)
    softy_url = _softy_home(settings)
    profile = _profile_dir()

    _print("")
    _print("=" * 60)
    _print("  SOFTY / INDEED - Automatisation Windows")
    _print("=" * 60)
    _print(f"  Dossier : {ROOT}")
    _print(f"  Profil Chrome : {profile}")
    _print("")

    softy_files: list[Path] = []
    indeed_files: list[Path] = []

    with sync_playwright() as playwright:
        _print("[.] Ouverture de Chrome...")
        try:
            context = playwright.chromium.launch_persistent_context(
                user_data_dir=str(profile),
                channel="chrome",
                headless=False,
                accept_downloads=True,
                viewport={"width": 1440, "height": 900},
                args=["--disable-session-crashed-bubble", "--no-first-run"],
            )
        except Exception:
            _print("[!] Chrome systeme indisponible, fallback Chromium Playwright...")
            context = playwright.chromium.launch_persistent_context(
                user_data_dir=str(profile),
                headless=False,
                accept_downloads=True,
                viewport={"width": 1440, "height": 900},
            )

        context.set_default_timeout(DEFAULT_TIMEOUT_MS)

        try:
            # Reuse first blank page + open second
            pages = context.pages
            indeed_page = pages[0] if pages else context.new_page()
            softy_page = context.new_page()

            _print(f"[.] Navigation Indeed : {indeed_url}")
            indeed_page.goto(indeed_url, wait_until="domcontentloaded")
            _print(f"[.] Navigation Softy  : {softy_url}")
            softy_page.goto(softy_url, wait_until="domcontentloaded")

            _wait_login(indeed_page, "indeed", "Indeed Employeur")
            _wait_login(softy_page, "softy", "Softy")

            # Ensure Softy is on stats after login
            if "/stats" not in softy_page.url:
                softy_page.goto(softy_url, wait_until="domcontentloaded")

            _print("")
            _print("[.] Exports Softy + Indeed en cours...")
            generated = generate_all_exports(
                context,
                settings,
                softy_page=softy_page,
                indeed_page=indeed_page,
                skip_login=True,
            )
            print_generated_files(generated)
            softy_files = generated.softy_files
            indeed_files = generated.indeed_files
        except Exception:
            _print("")
            _print("[ERREUR] Echec pendant l'automatisation :")
            traceback.print_exc()
            try:
                page = context.pages[0] if context.pages else None
                if page is not None:
                    shot = save_debug_screenshot(page, settings.download_dir, "erreur")
                    _print(f"Capture : {shot}")
            except Exception:
                pass
            return 1
        finally:
            context.close()

    _print("")
    _print("[.] Comparaison des exports...")
    result = compare_exports(
        softy_paths=softy_files,
        indeed_paths=indeed_files,
        softy_column=settings.softy_reference_column,
        indeed_column=settings.indeed_reference_column,
    )
    report = format_report(result)
    report_path = settings.download_dir / "rapport_comparaison.txt"
    report_path.write_text(report, encoding="utf-8")

    _print("")
    _print("=" * 60)
    _print("  RAPPORT FINAL")
    _print("=" * 60)
    _print(report)
    _print("")
    _print(f"Rapport enregistre : {report_path}")
    _print("=" * 60)

    return 1 if result.has_differences else 0


if __name__ == "__main__":
    try:
        code = run()
    except Exception:
        _print("")
        _print("[ERREUR FATALE]")
        traceback.print_exc()
        code = 1

    _print("")
    _print("Termine. Appuyez sur Entree pour fermer...")
    try:
        input()
    except EOFError:
        pass
    sys.exit(code)
