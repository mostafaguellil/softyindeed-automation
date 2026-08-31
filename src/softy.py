from __future__ import annotations

import logging
from pathlib import Path

from playwright.sync_api import Page

from src.browser import wait_for_download
from src.config import Settings

logger = logging.getLogger(__name__)


class SoftyAutomation:
    """
    Parcours Softy :
    Statistique → Année en cours → Suivi en temps réel → Exporter
    """

    def __init__(self, page: Page, settings: Settings) -> None:
        self.page = page
        self.settings = settings

    def login(self) -> None:
        logger.info("Connexion Softy…")
        self.page.goto(self.settings.softy_login_url, wait_until="domcontentloaded")

        self.page.get_by_label("Email", exact=False).fill(self.settings.softy_email)
        self.page.get_by_label("Mot de passe", exact=False).fill(self.settings.softy_password)
        self.page.get_by_role("button", name="Connexion").click()
        self.page.wait_for_load_state("networkidle")

    def _open_statistics(self) -> None:
        self.page.get_by_role("link", name="Statistique", exact=False).click()
        self.page.wait_for_load_state("networkidle")

    def _select_current_year(self) -> None:
        """Sélectionne « Année en cours » dans le filtre période (en haut à droite)."""
        period_filter = self.page.get_by_role("button", name="Année en cours", exact=False)
        if period_filter.count() > 0:
            period_filter.first.click()
            return

        # Ouvrir le sélecteur de période puis choisir « Année en cours »
        for opener in (
            self.page.get_by_label("Période", exact=False),
            self.page.locator("[class*='period'], [class*='date']").first,
        ):
            if opener.count() > 0:
                opener.first.click()
                break

        self.page.get_by_role("option", name="Année en cours", exact=False).click()
        self.page.wait_for_load_state("networkidle")

    def _open_realtime_tracking(self) -> None:
        self.page.get_by_role("link", name="Suivi en temps réel", exact=False).click()
        self.page.wait_for_load_state("networkidle")

    def export_active_offers(self) -> Path:
        logger.info("Export Softy (Statistique → Année en cours → Suivi en temps réel)…")

        self._open_statistics()
        self._select_current_year()
        self._open_realtime_tracking()

        def trigger_export() -> None:
            self.page.get_by_role("button", name="Exporter", exact=False).click()

        download_path = wait_for_download(self.page, self.settings.download_dir, trigger_export)
        target = self.settings.download_dir / f"softy_suivi_temps_reel{download_path.suffix}"
        download_path.replace(target)
        return target
