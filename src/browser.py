from __future__ import annotations

from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

from playwright.sync_api import Browser, BrowserContext, Page, Playwright, sync_playwright

from src.config import Settings

DEFAULT_TIMEOUT_MS = 60_000
DOWNLOAD_TIMEOUT_MS = 180_000


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
