from __future__ import annotations

import logging
from pathlib import Path

from playwright.sync_api import Page, TimeoutError as PlaywrightTimeoutError

from src.browser import wait_for_download
from src.config import INDEED_ENTITIES, Settings

logger = logging.getLogger(__name__)


class IndeedAutomation:
    """
    Parcours Indeed (sans création de campagne) :
    Campagnes → Créer une campagne → Source d'emploi (par entité) → Exporter → Tous les emplois
    """

    def __init__(self, page: Page, settings: Settings) -> None:
        self.page = page
        self.settings = settings

    def login(self) -> None:
        logger.info("Connexion Indeed…")
        self.page.goto(self.settings.indeed_login_url, wait_until="domcontentloaded")

        self.page.get_by_label("Email", exact=False).fill(self.settings.indeed_email)
        self.page.get_by_label("Password", exact=False).fill(self.settings.indeed_password)

        for sign_in_label in ("Sign in", "Se connecter", "Connexion"):
            button = self.page.get_by_role("button", name=sign_in_label, exact=False)
            if button.count() > 0:
                button.first.click()
                break
        else:
            self.page.locator("button[type='submit']").first.click()

        self.page.wait_for_load_state("networkidle")

    def _open_campaign_creation(self) -> None:
        self.page.get_by_role("link", name="Campagnes", exact=False).click()
        self.page.get_by_role("button", name="Créer une campagne", exact=False).click()
        self.page.wait_for_load_state("networkidle")

    def _select_job_source(self, entity_name: str) -> None:
        source_field = self.page.get_by_label("Source d'emploi", exact=False)
        source_field.click()
        self.page.get_by_role("option", name=entity_name, exact=True).click()

    def _export_all_jobs(self, entity_name: str) -> Path:
        logger.info("Export Indeed pour l'entité : %s", entity_name)

        def trigger_export() -> None:
            self.page.get_by_role("button", name="Exporter", exact=False).click()
            self.page.get_by_role("menuitem", name="Tous les emplois", exact=False).click()

        download_path = wait_for_download(self.page, self.settings.download_dir, trigger_export)
        renamed = self.settings.download_dir / f"indeed_{self._slug(entity_name)}{download_path.suffix}"
        download_path.replace(renamed)
        return renamed

    def export_entity(self, entity_name: str) -> Path:
        self._open_campaign_creation()
        self._select_job_source(entity_name)
        return self._export_all_jobs(entity_name)

    def export_all_entities(self) -> list[Path]:
        exports: list[Path] = []
        for entity in INDEED_ENTITIES:
            try:
                exports.append(self.export_entity(entity))
            except PlaywrightTimeoutError as exc:
                logger.error("Échec export Indeed pour %s : %s", entity, exc)
                raise
        return exports

    @staticmethod
    def _slug(value: str) -> str:
        return value.lower().replace(" ", "_")
