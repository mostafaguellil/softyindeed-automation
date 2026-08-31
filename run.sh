#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -d ".venv" ]; then
  python3 -m venv .venv
fi

source .venv/bin/activate
pip install -q -r requirements.txt
playwright install chromium

if [ ! -f ".env" ]; then
  cp .env.example .env
  echo ""
  echo "→ Fichier .env créé. Éditez-le avec vos identifiants, puis relancez :"
  echo "   ./run.sh"
  exit 1
fi

HEADLESS="${HEADLESS:-false}" python main.py "$@"
