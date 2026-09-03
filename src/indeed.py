from __future__ import annotations

import logging
from pathlib import Path

from playwright.sync_api import Page, TimeoutError as PlaywrightTimeoutError

from src.browser import wait_for_download
from src.config import INDEED_ENTITIES, Settings

logger = logging.getLogger(__name__)

INDEED_EMPLOYER_HOST = "employers.indeed.com"
INDEED_CAMPAIGN_URL = "https://employers.indeed.com/objective-campaign/create/job-selection"
JOB_SOURCE_LABELS = ("Source d'emploi", "Job source", "Source")
EXPORT_BUTTON_LABELS = ("Exporter", "Export")
ALL_JOBS_LABELS = ("Tous les emplois", "All jobs")


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

    def _employer_portal_url(self) -> str:
        login_url = self.settings.indeed_login_url
        if INDEED_EMPLOYER_HOST in login_url:
            return login_url
        return INDEED_CAMPAIGN_URL

    def _ensure_employer_portal(self) -> None:
        if INDEED_EMPLOYER_HOST in self.page.url:
            return

        target = self._employer_portal_url()
        logger.info("Navigation vers le portail employeur Indeed : %s", target)
        self.page.goto(target, wait_until="domcontentloaded")
        self.page.wait_for_load_state("networkidle")

    def _open_campaign_creation(self) -> None:
        self._ensure_employer_portal()

        if "objective-campaign" not in self.page.url:
            logger.info("Ouverture de la création de campagne Indeed…")
            self.page.goto(INDEED_CAMPAIGN_URL, wait_until="domcontentloaded")
            self.page.wait_for_load_state("networkidle")

    def _click_first_matching_role(self, role: str, labels: tuple[str, ...]) -> None:
        for label in labels:
            locator = self.page.get_by_role(role, name=label, exact=False)
            if locator.count() > 0:
                locator.first.click()
                return
        raise RuntimeError(f"Aucun élément {role!r} trouvé parmi {labels!r}")

    def _job_source_combobox(self):
        for label in JOB_SOURCE_LABELS:
            locator = self.page.get_by_role("combobox", name=label, exact=False)
            if locator.count() > 0:
                return locator.first
        raise RuntimeError(f"Aucun combobox trouvé parmi {JOB_SOURCE_LABELS!r}")

    def _select_job_source(self, entity_name: str) -> None:
        combo = self._job_source_combobox()
        current_value = combo.inner_text()
        if entity_name.upper() in current_value.upper():
            logger.info("Source d'emploi déjà sur %s", entity_name)
            return

        combo.click()
        option = self.page.get_by_role("option", name=entity_name, exact=False)
        option.first.wait_for(state="visible", timeout=10_000)
        option.first.click()
        self.page.wait_for_load_state("networkidle")

    def _export_all_jobs(self, entity_name: str) -> Path:
        logger.info("Export Indeed pour l'entité : %s", entity_name)

        def trigger_export() -> None:
            self._click_first_matching_role("button", EXPORT_BUTTON_LABELS)
            self._click_first_matching_role("button", ALL_JOBS_LABELS)

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
