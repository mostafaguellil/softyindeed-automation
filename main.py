from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from src.browser import launch_browser, save_debug_screenshot
from src.compare import compare_exports, format_report, list_export_columns
from src.config import Settings
from src.env_check import validate_env
from src.generate import generate_all_exports, print_generated_files

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Génère les exports Softy + Indeed depuis les applications web, "
            "puis compare les références."
        )
    )
    parser.add_argument(
        "--generate-only",
        action="store_true",
        help="Génère uniquement les fichiers (pas de comparaison).",
    )
    parser.add_argument(
        "--skip-indeed",
        action="store_true",
        help="Ne pas lancer Indeed (utiliser des fichiers déjà téléchargés).",
    )
    parser.add_argument(
        "--skip-softy",
        action="store_true",
        help="Ne pas lancer Softy (utiliser un fichier déjà téléchargé).",
    )
    parser.add_argument(
        "--softy-file",
        type=Path,
        help="Chemin vers un export Softy existant.",
    )
    parser.add_argument(
        "--indeed-files",
        type=Path,
        nargs="*",
        help="Chemins vers des exports Indeed existants.",
    )
    parser.add_argument(
        "--list-columns",
        type=Path,
        metavar="FILE",
        help="Affiche les colonnes d'un export déjà généré.",
    )
    return parser.parse_args()


def _print_columns(path: Path) -> int:
    if not path.exists():
        logger.error("Fichier introuvable : %s", path)
        return 1

    columns = list_export_columns(path)
    print(f"Colonnes dans {path.name} :")
    for index, column in enumerate(columns, start=1):
        print(f"  {index:2}. {column}")
    return 0


def _generate_exports(settings: Settings) -> tuple[list[Path], list[Path]]:
    with launch_browser(settings) as (_, _, context):
        try:
            generated = generate_all_exports(context, settings)
            print_generated_files(generated)
            return generated.softy_files, generated.indeed_files
        except Exception:
            page = context.pages[0] if context.pages else None
            if page is not None:
                screenshot = save_debug_screenshot(page, settings.download_dir, "erreur")
                logger.error("Capture d'écran de debug : %s", screenshot)
            raise


def main() -> int:
    args = parse_args()

    if args.list_columns:
        return _print_columns(args.list_columns)

    validate_env()
    settings = Settings.from_env()

    softy_files: list[Path] = []
    indeed_files: list[Path] = []

    if args.softy_file:
        softy_files = [args.softy_file]
    if args.indeed_files:
        indeed_files = list(args.indeed_files)

    must_generate_softy = not args.skip_softy and not softy_files
    must_generate_indeed = not args.skip_indeed and not indeed_files

    if must_generate_softy or must_generate_indeed:
        if must_generate_softy and must_generate_indeed:
            softy_files, indeed_files = _generate_exports(settings)
        else:
            logger.error(
                "Génération partielle non supportée. Lancez sans --skip-* pour tout générer, "
                "ou fournissez --softy-file et --indeed-files."
            )
            return 1

    if args.generate_only:
        logger.info("Génération terminée (--generate-only, comparaison ignorée).")
        return 0

    if not softy_files:
        logger.error("Aucun export Softy. Lancez : python main.py")
        return 1
    if not indeed_files:
        logger.error("Aucun export Indeed. Lancez : python main.py")
        return 1

    logger.info("=== Comparaison des exports ===")
    result = compare_exports(
        softy_paths=softy_files,
        indeed_paths=indeed_files,
        softy_column=settings.softy_reference_column,
        indeed_column=settings.indeed_reference_column,
    )

    report = format_report(result)
    print(report)

    report_path = settings.download_dir / "rapport_comparaison.txt"
    report_path.write_text(report, encoding="utf-8")
    logger.info("Rapport enregistré : %s", report_path)

    return 1 if result.has_differences else 0


if __name__ == "__main__":
    sys.exit(main())
