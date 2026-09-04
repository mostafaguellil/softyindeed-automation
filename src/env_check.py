from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

from dotenv import load_dotenv

PLACEHOLDER_VALUES = {
    "votre.email@exemple.com",
    "votre_mot_de_passe",
    "https://votre-url-softy.exemple.com/login",
}


def ensure_env_file() -> Path:
    env_path = Path(".env")
    example_path = Path(".env.example")

    if env_path.exists():
        return env_path

    if not example_path.exists():
        print("Erreur : fichier .env.example introuvable.", file=sys.stderr)
        sys.exit(1)

    shutil.copy(example_path, env_path)
    print("Fichier .env créé automatiquement depuis .env.example.")
    return env_path


def validate_env(*, cdp_url: str | None = None) -> None:
    load_dotenv()
    ensure_env_file()
    load_dotenv(override=True)

    uses_cdp = bool(cdp_url or os.getenv("CDP_URL"))

    if uses_cdp:
        required = ["SOFTY_LOGIN_URL"]
    else:
        required = [
            "INDEED_EMAIL",
            "INDEED_PASSWORD",
            "SOFTY_EMAIL",
            "SOFTY_PASSWORD",
            "SOFTY_LOGIN_URL",
        ]

    missing = [key for key in required if not os.getenv(key)]
    if missing:
        print(f"Erreur : variables manquantes dans .env : {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)

    invalid = [
        key
        for key in required
        if os.getenv(key, "").strip() in PLACEHOLDER_VALUES
    ]
    if invalid:
        print(
            "Erreur : remplacez les valeurs d'exemple dans .env pour : "
            + ", ".join(invalid),
            file=sys.stderr,
        )
        print("Ouvrez .env et mettez vos vrais identifiants, puis relancez.", file=sys.stderr)
        sys.exit(1)
