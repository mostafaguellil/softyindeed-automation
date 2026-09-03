#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

CDP_PORT="${CDP_PORT:-9222}"
CDP_URL="${CDP_URL:-http://localhost:${CDP_PORT}}"
CHROME_APP="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
CHROME_USER_DATA_DIR="${CHROME_USER_DATA_DIR:-/tmp/chrome-cdp-softyindeed}"
CDP_WAIT_SECONDS="${CDP_WAIT_SECONDS:-15}"

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

# Charge les variables utiles depuis .env (CDP, URLs d'attachement, etc.)
set -a
# shellcheck disable=SC1091
source .env
set +a

USE_CDP="${USE_CDP:-true}"
MAIN_ARGS=()

wait_for_cdp() {
  local elapsed=0
  while [ "${elapsed}" -lt "${CDP_WAIT_SECONDS}" ]; do
    if curl -sf "${CDP_URL}/json/version" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

if [ "${USE_CDP}" = "true" ]; then
  if ! curl -sf "${CDP_URL}/json/version" >/dev/null 2>&1; then
    echo ""
    echo "=== Chrome CDP non détecté sur ${CDP_URL} ==="

    if pgrep -xq "Google Chrome" 2>/dev/null; then
      echo ""
      echo "Chrome est déjà ouvert. Sur macOS, un Chrome déjà lancé ignore"
      echo "--remote-debugging-port si on le relance."
      echo ""
      echo "→ Ce script ouvre une fenêtre Chrome dédiée (profil séparé) pour le CDP."
      echo "  Connectez-vous à Indeed et Softy dans CETTE fenêtre."
    fi

    if [ -x "${CHROME_APP}" ]; then
      mkdir -p "${CHROME_USER_DATA_DIR}"
      echo "→ Lancement de Chrome CDP (profil : ${CHROME_USER_DATA_DIR})…"
      "${CHROME_APP}" \
        --remote-debugging-port="${CDP_PORT}" \
        --user-data-dir="${CHROME_USER_DATA_DIR}" \
        >/dev/null 2>&1 &

      if ! wait_for_cdp; then
        echo ""
        echo "Erreur : impossible de joindre Chrome sur ${CDP_URL}."
        echo ""
        echo "Causes fréquentes :"
        echo "  • le port ${CDP_PORT} est déjà utilisé par un autre programme"
        echo "  • Chrome n'a pas eu le temps de démarrer (augmentez CDP_WAIT_SECONDS)"
        echo ""
        echo "Essayez manuellement :"
        echo "  ${CHROME_APP} \\"
        echo "    --remote-debugging-port=${CDP_PORT} \\"
        echo "    --user-data-dir=${CHROME_USER_DATA_DIR}"
        exit 1
      fi
    else
      echo "Lancez Chrome manuellement :"
      echo ""
      echo "  ${CHROME_APP} \\"
      echo "    --remote-debugging-port=${CDP_PORT} \\"
      echo "    --user-data-dir=${CHROME_USER_DATA_DIR}"
      echo ""
      echo "Connectez-vous à Indeed et Softy (2FA inclus), puis relancez ./run.sh"
      exit 1
    fi
  fi

  MAIN_ARGS+=(--cdp --cdp-url "${CDP_URL}")

  if [ -n "${INDEED_ATTACH_URL:-}" ]; then
    MAIN_ARGS+=(--indeed-url "${INDEED_ATTACH_URL}")
  fi
  if [ -n "${SOFTY_ATTACH_URL:-}" ]; then
    MAIN_ARGS+=(--softy-url "${SOFTY_ATTACH_URL}")
  fi
fi

HEADLESS="${HEADLESS:-false}" python main.py "${MAIN_ARGS[@]}" "$@"
