#!/bin/zsh
# Captures du simulateur par onglet : scripts/shots.sh <dossier> [onglets…]
set -e
SIM=${SIM:-"iPhone 17 Pro"}
OUT=$1; shift
xcodebuild -project Semainier.xcodeproj -scheme Semainier -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath build build -quiet 2>&1 | grep -E "error:" && exit 1
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/Semainier.app
for t in "$@"; do
  name=${t//:/-}
  tab=${t%%:*}; mode=${t#*:}
  xcrun simctl terminate "$SIM" com.ovrplow.Semainier 2>/dev/null || true
  # Écrit directement dans les préférences de l'appli (sinon la valeur qu'elle a enregistrée l'emporte).
  prefs="$(xcrun simctl get_app_container "$SIM" com.ovrplow.Semainier data)/Library/Preferences/com.ovrplow.Semainier"
  xcrun simctl spawn "$SIM" defaults write "$prefs" tab "$tab"
  [[ "$mode" != "$t" ]] && xcrun simctl spawn "$SIM" defaults write "$prefs" planning.mode "$mode"
  xcrun simctl launch "$SIM" com.ovrplow.Semainier >/dev/null
  sleep 3
  xcrun simctl io "$SIM" screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "$OUT/$name.png"
done
