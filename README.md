# Softy ↔ Indeed — automatisation de comparaison

Script Python qui :

1. se connecte à **Softy**, va dans Statistique → **Année en cours** → Suivi en temps réel, puis exporte ;
2. se connecte à **Indeed**, exporte les emplois pour chaque entité via Campagnes → Créer une campagne ;
3. compare les numéros de référence et signale les écarts.

## Faisabilité

**Oui, c'est faisable**, avec quelques nuances :

| Aspect | Difficulté | Commentaire |
|--------|------------|-------------|
| Connexion email/mot de passe | Facile | Pas de 2FA selon vos réponses |
| Export via bouton | Facile | Plus fiable que le scraping d'un tableau |
| Comparaison des fichiers | Facile | Pandas sur une colonne commune |
| Navigation Indeed (4 entités) | Moyen | Parcours répétitif, sélecteurs à valider une fois |
| Parcours Softy | Moyen | À documenter selon votre interface |
| Maintenance | À prévoir | Si Indeed/Softy changent l'UI, les sélecteurs devront être mis à jour |

## Prérequis

- Python 3.11+
- Comptes Indeed Employeur et Softy

## Installation

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
playwright install chromium
cp .env.example .env
# Éditez .env avec vos identifiants et URLs
```

## Lancement (génère les fichiers automatiquement)

**Vous n'avez pas besoin de fichiers au départ.** Le script se connecte aux sites, télécharge les exports, puis compare.

### Première fois

**macOS / Linux**

```bash
chmod +x run.sh
./run.sh
```

**Windows**

```bat
run.bat
```

`run.sh` / `run.bat` lancent le **mode Chrome attaché** par défaut (2FA manuelle) :
1. démarrent Chrome avec `--remote-debugging-port=9222` si besoin ;
2. vous connectez à Indeed Employeur et Softy dans Chrome ;
3. détectent automatiquement les onglets ;
4. naviguent et exportent automatiquement, puis comparent.

Pour revenir au mode login automatique : `USE_CDP=false ./run.sh` (ou `set USE_CDP=false` puis `run.bat` sous Windows).

Ou manuellement :

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
playwright install chromium
cp .env.example .env
# Éditez .env avec vos identifiants Indeed + Softy
python main.py
```

### Fichiers générés dans `./downloads/`

| Fichier | Source |
|---------|--------|
| `softy_suivi_temps_reel.xlsx` | Softy — Suivi en temps réel |
| `indeed_globe_effective_shooper.*` | Indeed — entité 1 |
| `indeed_globe_travel_retail.*` | Indeed — entité 2 |
| `indeed_globe_groupe_siege.*` | Indeed — entité 3 |
| `indeed_techsell.*` | Indeed — entité 4 |
| `exports_manifest.json` | Liste de tous les fichiers générés |
| `rapport_comparaison.txt` | Résultat de la comparaison |

### Options utiles

```bash
# Générer les fichiers sans comparer
python main.py --generate-only

# Voir les colonnes d'un export généré
python main.py --list-columns ./downloads/softy_suivi_temps_reel.xlsx
```

Mode debug (navigateur visible, recommandé la première fois) :

```bash
HEADLESS=false python main.py
```

### Mode Chrome attaché (2FA / authenticator Indeed)

Si Indeed demande un authenticator, connectez-vous manuellement dans Chrome puis laissez le script naviguer :

```bash
# 1. Fermez Chrome, puis relancez-le avec le port de débogage :
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=9222

# 2. Connectez-vous à Indeed et Softy dans ce Chrome (2FA inclus)

# 3. Lancez le script — il vous demandera quel onglet utiliser pour chaque site
python main.py --cdp
```

Options utiles :

```bash
# Auto-sélectionner les onglets par fragment d'URL (sans prompt interactif)
python main.py --cdp --indeed-url indeed.com/recrutement --softy-url softy.pro

# Ou via .env :
# CDP_URL=http://localhost:9222
# INDEED_ATTACH_URL=indeed.com/recrutement
# SOFTY_ATTACH_URL=softy.pro
```

Le script affiche la liste des onglets ouverts ; entrez le **numéro** ou un **fragment d'URL** (ex. `2`, `indeed.com`, `softy.pro`).

## Entités Indeed traitées

- GLOBE EFFECTIVE SHOOPER
- GLOBE TRAVEL RETAIL
- GLOBE GROUPE SIEGE
- TECHSELL

## Parcours automatisés

### Softy
1. Onglet **Statistique**
2. Filtre période : **Année en cours** (en haut à droite)
3. Onglet gauche **Suivi en temps réel**
4. Bouton **Exporter** (en haut à droite)

### Indeed
1. Onglet gauche **Campagnes**
2. **Créer une campagne** (en haut à droite)
3. **Source d'emploi** → sélectionner l'entité
4. **Exporter** → **Tous les emplois**
5. Répéter pour les 4 entités (aucune campagne n'est créée)

## Colonnes référence (proposition)

Par défaut, le script utilise **`auto`** : il cherche la colonne la plus probable dans chaque export.

| Source | Colonnes testées en priorité |
|--------|------------------------------|
| **Softy** | `Référence`, `Référence offre`, `Numéro offre`, `ID offre`, `Code offre` |
| **Indeed** | `Job Reference`, `Reference`, `Reference Number`, `Job ID` |

Pour voir les colonnes d'un fichier exporté :

```bash
python main.py --list-columns ./downloads/softy_suivi_temps_reel.xlsx
python main.py --list-columns ./downloads/indeed_techsell.xlsx
```

Si la détection auto se trompe, forcez le nom exact dans `.env` :

```env
SOFTY_REFERENCE_COLUMN=Référence offre
INDEED_REFERENCE_COLUMN=Job Reference
```

## Configuration à compléter

1. **Identifiants** Indeed et Softy dans `.env`
2. (Optionnel) noms de colonnes si `auto` ne convient pas
3. (Optionnel) ajuster les sélecteurs si les libellés UI diffèrent légèrement
