from __future__ import annotations

import logging
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path

import pandas as pd

from src.config import INDEED_REFERENCE_CANDIDATES, SOFTY_REFERENCE_CANDIDATES

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ComparisonResult:
    softy_references: set[str]
    indeed_references: set[str]
    missing_in_indeed: set[str]
    extra_in_indeed: set[str]
    softy_column_used: str
    indeed_column_used: str

    @property
    def has_differences(self) -> bool:
        return bool(self.missing_in_indeed or self.extra_in_indeed)


def _read_export(path: Path) -> pd.DataFrame:
    suffix = path.suffix.lower()
    if suffix == ".csv":
        return pd.read_csv(path, dtype=str)
    if suffix in {".xlsx", ".xls"}:
        return pd.read_excel(path, dtype=str)
    raise ValueError(f"Format non supporté : {path}")


def _normalize_column_name(name: str) -> str:
    text = unicodedata.normalize("NFKD", str(name))
    text = "".join(char for char in text if not unicodedata.combining(char))
    text = re.sub(r"\s+", " ", text).strip().lower()
    return text


def _normalize_reference(value: object) -> str | None:
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return None
    text = str(value).strip()
    return text or None


def list_export_columns(path: Path) -> list[str]:
    frame = _read_export(path)
    return [str(column) for column in frame.columns]


def resolve_reference_column(
    frame: pd.DataFrame,
    preferred: str,
    candidates: list[str],
    source_label: str,
) -> str:
    columns = [str(column) for column in frame.columns]
    normalized_map = {_normalize_column_name(column): column for column in columns}

    if preferred.lower() != "auto":
        if preferred in columns:
            return preferred
        normalized_preferred = _normalize_column_name(preferred)
        if normalized_preferred in normalized_map:
            resolved = normalized_map[normalized_preferred]
            logger.info("Colonne %s : correspondance '%s' → '%s'", source_label, preferred, resolved)
            return resolved
        available = ", ".join(columns)
        raise KeyError(
            f"Colonne '{preferred}' introuvable pour {source_label}. Colonnes disponibles : {available}"
        )

    for candidate in candidates:
        if candidate in columns:
            logger.info("Colonne %s détectée automatiquement : '%s'", source_label, candidate)
            return candidate
        normalized_candidate = _normalize_column_name(candidate)
        if normalized_candidate in normalized_map:
            resolved = normalized_map[normalized_candidate]
            logger.info("Colonne %s détectée automatiquement : '%s'", source_label, resolved)
            return resolved

    reference_patterns = ("reference", "ref", "numero", "numero offre", "id offre", "code offre", "job id")
    for column in columns:
        normalized = _normalize_column_name(column)
        if any(pattern in normalized for pattern in reference_patterns):
            logger.info("Colonne %s détectée par motif : '%s'", source_label, column)
            return column

    available = ", ".join(columns)
    raise KeyError(
        f"Impossible de détecter la colonne référence pour {source_label}. "
        f"Colonnes disponibles : {available}. "
        f"Définissez SOFTY_REFERENCE_COLUMN ou INDEED_REFERENCE_COLUMN dans .env"
    )


def load_references(
    paths: list[Path],
    column_name: str,
    candidates: list[str],
    source_label: str,
) -> tuple[set[str], str]:
    references: set[str] = set()
    column_used: str | None = None

    for path in paths:
        frame = _read_export(path)
        resolved_column = resolve_reference_column(frame, column_name, candidates, source_label)
        if column_used is None:
            column_used = resolved_column
        elif column_used != resolved_column:
            raise ValueError(
                f"Colonnes référence incohérentes pour {source_label} : "
                f"'{column_used}' vs '{resolved_column}' dans {path.name}"
            )

        for raw in frame[resolved_column].tolist():
            normalized = _normalize_reference(raw)
            if normalized is not None:
                references.add(normalized)

    assert column_used is not None
    return references, column_used


def compare_exports(
    softy_paths: list[Path],
    indeed_paths: list[Path],
    softy_column: str,
    indeed_column: str,
) -> ComparisonResult:
    softy_refs, softy_column_used = load_references(
        softy_paths,
        softy_column,
        SOFTY_REFERENCE_CANDIDATES,
        "Softy",
    )
    indeed_refs, indeed_column_used = load_references(
        indeed_paths,
        indeed_column,
        INDEED_REFERENCE_CANDIDATES,
        "Indeed",
    )

    return ComparisonResult(
        softy_references=softy_refs,
        indeed_references=indeed_refs,
        missing_in_indeed=softy_refs - indeed_refs,
        extra_in_indeed=indeed_refs - softy_refs,
        softy_column_used=softy_column_used,
        indeed_column_used=indeed_column_used,
    )


def format_report(result: ComparisonResult) -> str:
    lines = [
        "=== Rapport de comparaison Softy / Indeed ===",
        f"Colonne Softy utilisée : {result.softy_column_used}",
        f"Colonne Indeed utilisée : {result.indeed_column_used}",
        f"Offres Softy (suivi temps réel) : {len(result.softy_references)}",
        f"Offres exportées Indeed : {len(result.indeed_references)}",
        f"Manquantes sur Indeed : {len(result.missing_in_indeed)}",
        f"Présentes sur Indeed mais absentes de Softy : {len(result.extra_in_indeed)}",
        "",
    ]

    if result.missing_in_indeed:
        lines.append("Références Softy absentes de Indeed :")
        lines.extend(f"  - {ref}" for ref in sorted(result.missing_in_indeed))
        lines.append("")

    if result.extra_in_indeed:
        lines.append("Références Indeed absentes de Softy :")
        lines.extend(f"  - {ref}" for ref in sorted(result.extra_in_indeed))
        lines.append("")

    if not result.has_differences:
        lines.append("Aucune différence détectée.")

    return "\n".join(lines)
