from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

# Entités Indeed à traiter une par une dans "Source d'emploi"
INDEED_ENTITIES: list[str] = [
    "GLOBE EFFECTIVE SHOOPER",
    "GLOBE TRAVEL RETAIL",
    "GLOBE GROUPE SIEGE",
    "TECHSELL",
]

# Colonnes probables pour la référence offre (utilisées en mode auto)
SOFTY_REFERENCE_CANDIDATES: list[str] = [
    "Référence",
    "Reference",
    "Référence offre",
    "Ref offre",
    "Numéro offre",
    "N° offre",
    "Numero offre",
    "ID offre",
    "Code offre",
    "Réf.",
    "Ref",
]

INDEED_REFERENCE_CANDIDATES: list[str] = [
    "Job Reference",
    "Reference",
    "Référence",
    "Reference Number",
    "Job ID",
    "External ID",
    "Ref",
    "Job ref",
    "Référence offre",
]


@dataclass(frozen=True)
class Settings:
    indeed_email: str
    indeed_password: str
    softy_email: str
    softy_password: str
    indeed_login_url: str
    softy_login_url: str
    indeed_reference_column: str
    softy_reference_column: str
    headless: bool
    download_dir: Path

    @classmethod
    def from_env(cls) -> Settings:
        download_dir = Path(os.getenv("DOWNLOAD_DIR", "./downloads")).resolve()
        download_dir.mkdir(parents=True, exist_ok=True)

        return cls(
            indeed_email=os.environ["INDEED_EMAIL"],
            indeed_password=os.environ["INDEED_PASSWORD"],
            softy_email=os.environ["SOFTY_EMAIL"],
            softy_password=os.environ["SOFTY_PASSWORD"],
            indeed_login_url=os.getenv("INDEED_LOGIN_URL", "https://employers.indeed.com/"),
            softy_login_url=os.environ["SOFTY_LOGIN_URL"],
            indeed_reference_column=os.getenv("INDEED_REFERENCE_COLUMN", "auto"),
            softy_reference_column=os.getenv("SOFTY_REFERENCE_COLUMN", "auto"),
            headless=os.getenv("HEADLESS", "false").lower() == "true",
            download_dir=download_dir,
        )
