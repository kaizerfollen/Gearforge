#!/usr/bin/env bash
# Regenerate docs/research/01-04 + data JSON from Factorio 1.1.110 prototype data.
# Usage: tools/regenerate.sh <path-to-factorio-data-1.1.110-checkout> [work-dir]
#   git clone --depth 1 --branch 1.1.110 https://github.com/wube/factorio-data <checkout>
# Requires: python3 + lupa (pip install lupa; uses the bundled Lua 5.2 runtime).
# 05_mechanics.md and GDD.md are hand-written and are NOT regenerated.
set -euo pipefail
FD="$1"; WORK="${2:-$(mktemp -d)}"
HERE="$(cd "$(dirname "$0")" && pwd)"; OUT="$(dirname "$HERE")"
python3 -I "$HERE/load_data.py" "$FD" "$WORK/raw.json"
python3 "$HERE/gen_items.py"    "$WORK/raw.json" "$OUT/01_items.md"
python3 "$HERE/gen_recipes.py"  "$WORK/raw.json" "$OUT/02_recipes.md"
python3 "$HERE/gen_entities.py" "$WORK/raw.json" "$OUT/03_entities.md"
python3 "$HERE/gen_techs.py"    "$WORK/raw.json" "$OUT/04_technologies.md"
python3 "$HERE/gen_json.py"     "$WORK/raw.json" "$OUT/data/gearforge_base_1_1.json"
python3 "$HERE/gen_gamedata.py"   "$OUT/data/gearforge_base_1_1.json" "$(dirname "$(dirname "$OUT")")/Core/Sources/FactoryCore/Resources/GameData.json"
