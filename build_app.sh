#!/bin/bash
# Construit « Sillage.app » (Apple Silicon), autonome : aucune dépendance à installer.
# Prérequis pour CONSTRUIRE (pas pour utiliser l'app) : Xcode ou ses outils en ligne de commande.
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/Sillage.app"
BIN="Sillage"

echo "▶ Compilation (release, arm64)…"
swift build -c release --arch arm64

echo "▶ Icône…"
ICONSET="$(mktemp -d)/icon.iconset"
swift tools/make_icon.swift "$ICONSET" >/dev/null
mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/icon.icns

echo "▶ Assemblage de l'app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/arm64-apple-macosx/release/$BIN" "$APP/Contents/MacOS/$BIN"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/icon.icns "$APP/Contents/Resources/icon.icns"

echo "▶ Signature ad hoc…"
# macOS ajoute parfois des attributs de fichier (« provenance ») qui font échouer la signature : on les retire et on réessaie.
sign() {
  for essai in 1 2 3 4 5; do
    xattr -cr "$APP" 2>/dev/null || true
    codesign --force --sign - --timestamp=none "$1" && return 0
    sleep 1
  done
  return 1
}
sign "$APP/Contents/MacOS/$BIN"
sign "$APP"
# macOS ajoute parfois un attribut « provenance » après coup : on vérifie la signature sur une copie propre.
CHK="$(mktemp -d)"
ditto --noextattr --norsrc "$APP" "$CHK/check.app"
xattr -cr "$CHK/check.app" 2>/dev/null || true
codesign --verify --strict "$CHK/check.app"
rm -rf "$CHK"

echo "▶ Vérifications…"
echo "  Architecture : $(lipo -archs "$APP/Contents/MacOS/$BIN")"
echo "  macOS minimum : $(vtool -show-build "$APP/Contents/MacOS/$BIN" | awk '/minos/ {print $2}')"
echo "  Bibliothèques liées :"
otool -L "$APP/Contents/MacOS/$BIN" | tail -n +2 | awk '{print "    " $1}'
if otool -L "$APP/Contents/MacOS/$BIN" | grep -Eq '/opt/homebrew|/usr/local'; then
  echo "✗ L'app dépend d'une bibliothèque hors système !" >&2; exit 1
fi
echo "✓ App prête : $APP"
