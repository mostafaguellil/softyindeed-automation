from __future__ import annotations

import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlparse


def _default_user_data_dir() -> Path:
    env_dir = os.getenv("CHROME_USER_DATA_DIR", "").strip()
    if env_dir and not env_dir.startswith("/tmp/"):
        return Path(env_dir)
    return Path(tempfile.gettempdir()) / "chrome-cdp-softyindeed"


def find_chrome_executable() -> Path | None:
    system = platform.system()
    candidates: list[Path] = []

    if system == "Darwin":
        candidates.append(Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"))
    elif system == "Windows":
        local_app = os.environ.get("LOCALAPPDATA", "")
        program_files = os.environ.get("ProgramFiles", r"C:\Program Files")
        program_files_x86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
        candidates.extend(
            [
                Path(program_files) / "Google/Chrome/Application/chrome.exe",
                Path(program_files_x86) / "Google/Chrome/Application/chrome.exe",
                Path(local_app) / "Google/Chrome/Application/chrome.exe",
            ]
        )
    else:
        for name in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser"):
            found = shutil.which(name)
            if found:
                return Path(found)

    for path in candidates:
        if path.exists():
            return path
    return None


def cdp_port_from_url(cdp_url: str) -> int:
    parsed = urlparse(cdp_url)
    if parsed.port:
        return parsed.port
    return 9222


def is_cdp_ready(cdp_url: str, timeout_sec: float = 2.0) -> bool:
    try:
        with urllib.request.urlopen(f"{cdp_url.rstrip('/')}/json/version", timeout=timeout_sec) as response:
            return 200 <= response.status < 300
    except (urllib.error.URLError, TimeoutError, ValueError):
        return False


def wait_for_cdp(cdp_url: str, wait_seconds: int = 60) -> bool:
    deadline = time.monotonic() + wait_seconds
    while time.monotonic() < deadline:
        if is_cdp_ready(cdp_url):
            return True
        time.sleep(1)
    return False


def launch_chrome_with_cdp(
    *,
    cdp_url: str,
    indeed_url: str,
    softy_url: str,
    user_data_dir: Path | None = None,
    wait_seconds: int = 60,
) -> None:
    """
    Lance une instance Chrome dediee avec remote debugging.
    Sur Windows, utilise subprocess (plus fiable que `start` du .bat).
    """
    if is_cdp_ready(cdp_url):
        print(f"[OK] Chrome CDP deja disponible : {cdp_url}")
        return

    chrome = find_chrome_executable()
    if chrome is None:
        raise RuntimeError("Google Chrome introuvable sur ce PC.")

    profile_dir = user_data_dir or _default_user_data_dir()
    profile_dir.mkdir(parents=True, exist_ok=True)
    port = cdp_port_from_url(cdp_url)

    softy_target = softy_url
    if "login" in softy_target.lower():
        parsed = urlparse(softy_target)
        softy_target = f"{parsed.scheme}://{parsed.netloc}/stats"

    args = [
        str(chrome),
        f"--remote-debugging-port={port}",
        "--remote-debugging-address=127.0.0.1",
        f"--user-data-dir={profile_dir}",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-session-crashed-bubble",
        "--new-window",
        indeed_url,
        softy_target,
    ]

    print(f"[.] Lancement Chrome CDP (port {port})...")
    print(f"    Profil : {profile_dir}")

    popen_kwargs: dict = {
        "stdout": subprocess.DEVNULL,
        "stderr": subprocess.DEVNULL,
        "stdin": subprocess.DEVNULL,
    }
    if platform.system() == "Windows":
        # Detach without hiding the Chrome GUI window.
        popen_kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        popen_kwargs["start_new_session"] = True

    subprocess.Popen(args, **popen_kwargs)

    if wait_for_cdp(cdp_url, wait_seconds=wait_seconds):
        print(f"[OK] Chrome CDP pret : {cdp_url}")
        return

    # Second essai : parfois Chrome met plus longtemps au premier demarrage du profil
    print("[!] CDP pas encore pret, nouvel essai de lancement...")
    subprocess.Popen(args, **popen_kwargs)
    if wait_for_cdp(cdp_url, wait_seconds=wait_seconds):
        print(f"[OK] Chrome CDP pret : {cdp_url}")
        return

    raise RuntimeError(
        f"Impossible de joindre Chrome CDP sur {cdp_url}.\n"
        f"Verifiez que le port {port} n'est pas bloque, puis relancez."
    )


def ensure_chrome_cdp(settings) -> None:
    cdp_url = settings.cdp_url
    if not cdp_url:
        return

    indeed_url = settings.indeed_login_url or "https://employers.indeed.com/jobs"
    softy_url = settings.softy_login_url or "https://v2.softy.pro/stats"
    wait_seconds = int(os.getenv("CDP_WAIT_SECONDS", "60"))

    try:
        launch_chrome_with_cdp(
            cdp_url=cdp_url,
            indeed_url=indeed_url,
            softy_url=softy_url,
            wait_seconds=wait_seconds,
        )
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        raise
