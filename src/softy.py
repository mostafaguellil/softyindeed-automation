from __future__ import annotations

import logging
from datetime import date
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import Frame, Page

from src.browser import wait_for_download
from src.config import Settings

logger = logging.getLogger(__name__)

STATS_FRAME_URL_FRAGMENT = "statistiques"
STATS_NAV_LINK_NAMES = ("Statistique", "Statistiques", "Statistics")
REALTIME_TRACKING_LABELS = ("Suivi en temps réel", "Real-time tracking", "Real time tracking")
REALTIME_TRACKING_MARKERS = ("Suivi des offres en ligne", "Online job offer tracking")
DASHBOARD_LABELS = ("Candidatures", "Applications")


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

    def _find_stats_frame(self) -> Frame | None:
        """Retourne l'iframe des statistiques si elle est déjà chargée."""
        self.page.wait_for_load_state("domcontentloaded")

        for _ in range(60):
            for frame in self.page.frames:
                if STATS_FRAME_URL_FRAGMENT in frame.url:
                    frame.wait_for_load_state("domcontentloaded")
                    return frame
            self.page.wait_for_timeout(500)

        return None

    def _stats_frame(self) -> Frame:
        frame = self._find_stats_frame()
        if frame is None:
            raise RuntimeError(
                "Iframe statistiques introuvable — ouvrez l'onglet Statistiques dans Softy."
            )
        return frame

    def _stats_page_url(self) -> str:
        origin = urlparse(self.page.url)
        base = f"{origin.scheme}://{origin.netloc}"
        if self.settings.softy_login_url:
            softy_origin = urlparse(self.settings.softy_login_url)
            if softy_origin.scheme and softy_origin.netloc:
                base = f"{softy_origin.scheme}://{softy_origin.netloc}"
        return f"{base}/stats"

    def _open_statistics(self) -> None:
        if self._find_stats_frame() is not None:
            return

        if "/stats" not in self.page.url:
            for name in STATS_NAV_LINK_NAMES:
                link = self.page.get_by_role("link", name=name, exact=False)
                if link.count() > 0:
                    link.first.click()
                    self.page.wait_for_load_state("networkidle")
                    break
            else:
                logger.info("Navigation directe vers %s", self._stats_page_url())
                self.page.goto(self._stats_page_url(), wait_until="domcontentloaded")
                self.page.wait_for_load_state("networkidle")

        self._stats_frame()

    def _dismiss_modals(self, frame: Frame) -> None:
        modal = frame.locator("[class*='Modal_Container']")
        if modal.count() == 0 or not modal.first.is_visible():
            return

        logger.info("Fermeture d'une modale Softy ouverte…")
        for label in ("Annuler", "Cancel", "Fermer", "Close"):
            button = modal.get_by_role("button", name=label, exact=False)
            if button.count() > 0:
                button.first.click()
                frame.wait_for_timeout(500)
                if modal.count() == 0 or not modal.first.is_visible():
                    return

        close_button = modal.locator("[class*='ModalHeader'] button").first
        if close_button.count() > 0:
            close_button.click()
            frame.wait_for_timeout(500)
            if modal.count() == 0 or not modal.first.is_visible():
                return

        self.page.keyboard.press("Escape")
        frame.wait_for_timeout(500)

    def _is_on_realtime_tracking(self, frame: Frame) -> bool:
        body_text = frame.locator("body").inner_text()
        return any(marker in body_text for marker in REALTIME_TRACKING_MARKERS)

    def _open_dashboard_view(self, frame: Frame) -> None:
        self._dismiss_modals(frame)

        for label in DASHBOARD_LABELS:
            link = frame.get_by_role("link", name=label, exact=True)
            if link.count() > 0:
                link.first.click()
                frame.wait_for_load_state("networkidle")
                return

        frame.get_by_alt_text("Candidatures", exact=False).first.click()
        frame.wait_for_load_state("networkidle")

    def _select_current_year(self) -> None:
        """Définit la période du 1er janvier à aujourd'hui (équivalent « Année en cours »)."""
        frame = self._stats_frame()
        self._dismiss_modals(frame)

        start_input = frame.locator('input[name="start"]')
        if start_input.count() == 0 and self._is_on_realtime_tracking(frame):
            logger.info("Retour au tableau de bord pour régler la période…")
            self._open_dashboard_view(frame)
            start_input = frame.locator('input[name="start"]')

        end_input = frame.locator('input[name="end"]')

        if start_input.count() == 0:
            logger.info("Filtre période absent sur cette vue, poursuite…")
            return

        today = date.today()
        start = f"{today.year}-01-01"
        end = today.isoformat()

        if start_input.input_value() == start and end_input.input_value() == end:
            logger.info("Période déjà sur l'année en cours (%s → %s)", start, end)
            return

        start_input.fill(start)
        end_input.fill(end)
        end_input.press("Tab")
        frame.wait_for_load_state("networkidle")

    def _open_realtime_tracking(self) -> None:
        frame = self._stats_frame()
        self._dismiss_modals(frame)

        if self._is_on_realtime_tracking(frame):
            logger.info("Déjà sur Suivi en temps réel")
            return

        for label in REALTIME_TRACKING_LABELS:
            link = frame.get_by_role("link", name=label, exact=True)
            if link.count() > 0:
                link.first.click()
                frame.wait_for_load_state("networkidle")
                return

        frame.get_by_alt_text("Suivi en temps réel", exact=False).first.click()
        frame.wait_for_load_state("networkidle")

    def _select_export_format(self, modal) -> None:
        format_select = modal.locator("select").filter(has=modal.locator('option[value="xlsx"]'))
        if format_select.count() == 0:
            return

        current_value = format_select.first.evaluate("el => el.value")
        if current_value == "xlsx":
            logger.info("Format d'export déjà sur Excel")
            return

        format_select.first.select_option("xlsx", force=True)

    def _trigger_export(self, frame: Frame) -> None:
        self._dismiss_modals(frame)
        frame.get_by_role("button", name="Exporter", exact=False).first.click()

        modal = frame.locator("[class*='Modal_Container']")
        modal.wait_for(state="visible", timeout=10_000)

        self._select_export_format(modal)
        modal.get_by_role("button", name="Exporter", exact=False).click()

    def export_active_offers(self) -> Path:
        logger.info("Export Softy (Statistique → Année en cours → Suivi en temps réel)…")

        self._open_statistics()
        self._select_current_year()
        self._open_realtime_tracking()

        frame = self._stats_frame()

        def trigger_export() -> None:
            self._trigger_export(frame)

        download_path = wait_for_download(self.page, self.settings.download_dir, trigger_export)
        target = self.settings.download_dir / f"softy_suivi_temps_reel{download_path.suffix}"
        download_path.replace(target)
        return target
