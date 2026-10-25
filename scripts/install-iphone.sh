#!/bin/zsh
# Compile Semainier et l'installe sur l'iPhone (câble ou même Wi-Fi).
# Avec un compte Apple gratuit, la signature expire au bout de 7 jours :
# relancer ce script pour la renouveler. Les données sont conservées.
set -euo pipefail
cd "${0:A:h}/.."

json=$(mktemp)
xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || true
read -r UDID NAME < <(python3 - "$json" <<'PY'
import json, sys
try:
    devs = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devs = []
for d in devs:
    hw, props = d.get("hardwareProperties", {}), d.get("deviceProperties", {})
    if hw.get("platform") == "iOS" and hw.get("deviceType") == "iPhone" and hw.get("udid"):
        print(hw["udid"], props.get("name", "iPhone").replace(" ", "_"))
        break
PY
) || true
rm -f "$json"

if [[ -z "${UDID:-}" ]]; then
  echo "Aucun iPhone trouvé. Le brancher (ou le mettre sur le même Wi-Fi), le déverrouiller et choisir « Se fier à cet ordinateur »."
  exit 1
fi
echo "→ iPhone : ${NAME//_/ } ($UDID)"

echo "→ Compilation et signature…"
xcodebuild -project Semainier.xcodeproj -scheme Semainier -configuration Release \
  -destination "id=$UDID" -derivedDataPath build -allowProvisioningUpdates -quiet build

echo "→ Installation…"
if ! out=$(xcrun devicectl device install app --device "$UDID" build/Build/Products/Release-iphoneos/Semainier.app 2>&1); then
  # On masque l'avertissement sans conséquence « No provider was found » de devicectl.
  print -r -- "$out" | grep -v -e "provisioning paramter" -e "reduced set"
  exit 1
fi
xcrun devicectl device process launch --device "$UDID" com.ovrplow.Semainier >/dev/null 2>&1 || true
echo "✓ Installé. Valable jusqu'au $(LC_ALL=fr_FR.UTF-8 date -v+7d '+%A %-d %B')."
