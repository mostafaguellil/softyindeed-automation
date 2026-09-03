from __future__ import annotations

import sys
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator
from urllib.parse import urlparse

from playwright.sync_api import Browser, BrowserContext, Page, Playwright, sync_playwright

from src.config import Settings

DEFAULT_TIMEOUT_MS = 60_000
DOWNLOAD_TIMEOUT_MS = 180_000
DEFAULT_CDP_URL = "http://localhost:9222"
DEFAULT_INDEED_ATTACH_HINT = "employers.indeed.com"
DEFAULT_SOFTY_ATTACH_HINT = "softy.pro"
CDP_ATTACH_WAIT_SECONDS = 120


@contextmanager
def launch_browser(settings: Settings) -> Iterator[tuple[Playwright, Browser, BrowserContext]]:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=settings.headless, slow_mo=150)
        context = browser.new_context(accept_downloads=True)
        context.set_default_timeout(DEFAULT_TIMEOUT_MS)
        try:
            yield playwright, browser, context
        finally:
            context.close()
            browser.close()


@contextmanager
def connect_browser_cdp(cdp_url: str) -> Iterator[tuple[Playwright, Browser, BrowserContext]]:
    """Se connecte à un Chrome déjà ouvert (--remote-debugging-port)."""
    with sync_playwright() as playwright:
        browser = playwright.chromium.connect_over_cdp(cdp_url)
        if not browser.contexts:
            print(
                "Erreur : aucun contexte Chrome trouvé. Ouvrez au moins un onglet dans Chrome.",
                file=sys.stderr,
            )
            sys.exit(1)

        context = browser.contexts[0]
        context.set_default_timeout(DEFAULT_TIMEOUT_MS)
        try:
            yield playwright, browser, context
        finally:
            browser.close()


def collect_open_pages(context: BrowserContext) -> list[Page]:
    return list(context.pages)


def print_open_pages(pages: list[Page]) -> None:
    print("\n=== Onglets Chrome ouverts ===")
    if not pages:
        print("  (aucun onglet — ouvrez Indeed et Softy dans Chrome)")
        return

    for index, page in enumerate(pages, start=1):
        title = page.title() or "(sans titre)"
        print(f"  {index}. {page.url}")
        print(f"     → {title}")


def _match_pages_by_url(pages: list[Page], url_hint: str) -> list[Page]:
    hint = url_hint.strip().lower()
    if not hint:
        return []

    matches: list[Page] = []
    for page in pages:
        page_url = page.url.lower()
        if hint in page_url:
            matches.append(page)
            continue

        parsed_hint = urlparse(hint if "://" in hint else f"https://{hint}")
        parsed_page = urlparse(page_url)
        if parsed_hint.netloc and parsed_hint.netloc in parsed_page.netloc:
            matches.append(page)

    return matches


def _resolve_page_choice(pages: list[Page], raw_choice: str) -> Page | None:
    choice = raw_choice.strip()
    if not choice:
        return None

    if choice.isdigit():
        index = int(choice) - 1
        if 0 <= index < len(pages):
            return pages[index]
        return None

    matches = _match_pages_by_url(pages, choice)
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        print(f"  Plusieurs onglets correspondent à « {choice} » :")
        for index, page in enumerate(matches, start=1):
            print(f"    {index}. {page.url}")
        nested = input("  Choisissez le numéro dans cette liste : ").strip()
        if nested.isdigit():
            nested_index = int(nested) - 1
            if 0 <= nested_index < len(matches):
                return matches[nested_index]
    return None


def _prompt_for_page(pages: list[Page], label: str, url_hint: str | None) -> Page:
    if url_hint:
        matches = _match_pages_by_url(pages, url_hint)
        if len(matches) == 1:
            page = matches[0]
            print(f"\n✓ Onglet {label} détecté automatiquement : {page.url}")
            return page
        if len(matches) > 1:
            print(f"\n⚠ Plusieurs onglets correspondent à INDEED_ATTACH_URL / SOFTY_ATTACH_URL pour {label}.")

    while True:
        print(f"\n→ Onglet {label} : entrez le numéro ou un fragment d'URL")
        print("  (ex. 2, indeed.com, softy.pro)")
        raw = input(f"  {label} : ").strip()
        page = _resolve_page_choice(pages, raw)
        if page is not None:
            print(f"  ✓ Sélectionné : {page.url}")
            return page
        print("  Choix invalide. Réessayez.")


def print_cdp_instructions(cdp_url: str) -> None:
    print("\n=== Mode Chrome attaché (CDP) ===")
    print("1. Fermez toutes les fenêtres Chrome.")
    print("2. Relancez Chrome avec le débogage distant :")
    print()
    print('   /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome \\')
    print("     --remote-debugging-port=9222")
    print()
    print("3. Connectez-vous manuellement à Indeed Employeur et Softy (2FA / authenticator inclus).")
    print("4. Le script détecte automatiquement les bons onglets et lance les exports.")
    print(f"\nConnexion CDP : {cdp_url}")


def _find_indeed_page(pages: list[Page]) -> Page | None:
    employers = [page for page in pages if "employers.indeed.com" in page.url.lower()]
    if employers:
        return employers[0]

    indeed_pages = [
        page
        for page in pages
        if "indeed.com" in page.url.lower() and page.url.lower().startswith(("http://", "https://"))
    ]
    return indeed_pages[0] if indeed_pages else None


def _find_softy_page(pages: list[Page]) -> Page | None:
    softy_pages = [page for page in pages if "softy.pro" in page.url.lower()]
    return softy_pages[0] if softy_pages else None


def _open_page(context: BrowserContext, url: str) -> Page:
    page = context.new_page()
    page.goto(url, wait_until="domcontentloaded")
    return page


def resolve_attach_pages(
    context: BrowserContext,
    *,
    indeed_url_hint: str | None = None,
    softy_url_hint: str | None = None,
    softy_login_url: str | None = None,
    indeed_login_url: str | None = None,
    wait_seconds: int = CDP_ATTACH_WAIT_SECONDS,
) -> tuple[Page, Page]:
    """Sélectionne automatiquement les onglets Indeed employeur et Softy."""
    indeed_hint = indeed_url_hint or DEFAULT_INDEED_ATTACH_HINT
    softy_hint = softy_url_hint or DEFAULT_SOFTY_ATTACH_HINT
    deadline = time.monotonic() + wait_seconds

    while time.monotonic() < deadline:
        pages = collect_open_pages(context)

        indeed_page = None
        softy_page = None

        if indeed_hint:
            matches = _match_pages_by_url(pages, indeed_hint)
            if matches:
                indeed_page = matches[0]

        if softy_hint:
            matches = _match_pages_by_url(pages, softy_hint)
            if matches:
                softy_page = matches[0]

        indeed_page = indeed_page or _find_indeed_page(pages)
        softy_page = softy_page or _find_softy_page(pages)

        if indeed_page and softy_page and indeed_page != softy_page:
            print(f"\n✓ Onglet Indeed détecté : {indeed_page.url}")
            print(f"✓ Onglet Softy détecté  : {softy_page.url}")
            return indeed_page, softy_page

        time.sleep(2)

    pages = collect_open_pages(context)
    indeed_page = _find_indeed_page(pages)
    softy_page = _find_softy_page(pages)

    if indeed_page is None:
        target = indeed_login_url or "https://employers.indeed.com/jobs"
        print(f"\n→ Ouverture automatique de l'onglet Indeed : {target}")
        indeed_page = _open_page(context, target)

    if softy_page is None:
        target = softy_login_url or "https://v2.softy.pro/stats"
        parsed = urlparse(target)
        if parsed.path in ("", "/"):
            target = f"{parsed.scheme}://{parsed.netloc}/stats"
        print(f"→ Ouverture automatique de l'onglet Softy : {target}")
        softy_page = _open_page(context, target)

    if indeed_page == softy_page:
        print("Erreur : Indeed et Softy doivent être deux onglets différents.", file=sys.stderr)
        sys.exit(1)

    print(f"\n✓ Onglet Indeed : {indeed_page.url}")
    print(f"✓ Onglet Softy  : {softy_page.url}")
    return indeed_page, softy_page


def save_debug_screenshot(page: Page, download_dir: Path, label: str) -> Path:
    download_dir.mkdir(parents=True, exist_ok=True)
    path = download_dir / f"debug_{label}.png"
    page.screenshot(path=path, full_page=True)
    return path


def wait_for_download(page: Page, download_dir: Path, trigger, timeout_ms: int = DOWNLOAD_TIMEOUT_MS) -> Path:
    """Déclenche une action puis attend le fichier téléchargé."""
    download_dir.mkdir(parents=True, exist_ok=True)

    with page.expect_download(timeout=timeout_ms) as download_info:
        trigger()

    download = download_info.value
    target = download_dir / download.suggested_filename
    download.save_as(target)
    return target
