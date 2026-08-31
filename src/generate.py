from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from playwright.sync_api import BrowserContext

from src.config import Settings
from src.indeed import IndeedAutomation
from src.softy import SoftyAutomation

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class GeneratedExports:
    softy_files: list[Path]
    indeed_files: list[Path]
    manifest_path: Path

    @property
    def all_files(self) -> list[Path]:
        return [*self.softy_files, *self.indeed_files]


def _write_manifest(settings: Settings, softy_files: list[Path], indeed_files: list[Path]) -> Path:
    manifest_path = settings.download_dir / "exports_manifest.json"
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "download_dir": str(settings.download_dir),
        "softy_files": [str(path) for path in softy_files],
        "indeed_files": [str(path) for path in indeed_files],
    }
    manifest_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    return manifest_path


def generate_all_exports(context: BrowserContext, settings: Settings) -> GeneratedExports:
    """Se connecte à Softy et Indeed, télécharge tous les exports dans downloads/."""
    settings.download_dir.mkdir(parents=True, exist_ok=True)

    softy_page = context.new_page()
    indeed_page = context.new_page()

    try:
        logger.info("=== Étape 1/2 : export Softy ===")
        softy = SoftyAutomation(softy_page, settings)
        softy.login()
        softy_file = softy.export_active_offers()
        logger.info("Fichier Softy généré : %s", softy_file)

        logger.info("=== Étape 2/2 : exports Indeed (4 entités) ===")
        indeed = IndeedAutomation(indeed_page, settings)
        indeed.login()
        indeed_files = indeed.export_all_entities()
        for path in indeed_files:
            logger.info("Fichier Indeed généré : %s", path)

        manifest_path = _write_manifest(settings, [softy_file], indeed_files)
        logger.info("Manifeste des exports : %s", manifest_path)

        return GeneratedExports(
            softy_files=[softy_file],
            indeed_files=indeed_files,
            manifest_path=manifest_path,
        )
    finally:
        softy_page.close()
        indeed_page.close()


def print_generated_files(exports: GeneratedExports) -> None:
    print("\n=== Fichiers générés ===")
    for path in exports.all_files:
        size_kb = path.stat().st_size / 1024 if path.exists() else 0
        print(f"  ✓ {path} ({size_kb:.1f} Ko)")
    print(f"\nManifeste : {exports.manifest_path}")
