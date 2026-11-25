#!/bin/bash
# Crée dist/Sillage.dmg avec un lien vers « Applications », et sa somme SHA-256.
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/Sillage.app"
DMG="dist/Sillage.dmg"
[ -d "$APP" ] || { echo "Construisez d'abord l'app : ./build_app.sh" >&2; exit 1; }

STAGE="$(mktemp -d)"
ditto --noextattr --norsrc "$APP" "$STAGE/Sillage.app"
xattr -cr "$STAGE/Sillage.app" 2>/dev/null || true
# Garde-fou : jamais de .dmg dont l'app a une signature invalide.
codesign --verify --strict "$STAGE/Sillage.app" || { echo "✗ signature invalide : .dmg non créé" >&2; exit 1; }
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Sillage" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

( cd dist && shasum -a 256 Sillage.dmg | tee Sillage.dmg.sha256 )
echo "✓ $DMG"
