#!/usr/bin/env bash
# Installs the pinned Godot editor and export templates (Linux x86_64 or macOS), verifying SHA-512
# against the values published with the official release:
#   https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable  (SHA512-SUMS.txt)
# Puts `godot` on PATH (GITHUB_PATH) when run in GitHub Actions. Bump GODOT_VERSION and the hashes together.
set -euo pipefail

GODOT_VERSION="4.7.2"
BASE="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable"
TEMPLATES_SHA512="ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"

case "$(uname -s)" in
Linux)
	EDITOR_ZIP="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
	EDITOR_SHA512="9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65"
	TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
	;;
Darwin)
	EDITOR_ZIP="Godot_v${GODOT_VERSION}-stable_macos.universal.zip"
	EDITOR_SHA512="38aa16e5bba2083941fc5b3e54be0089bd4cc35e32415f5b9fd9a8a6a7b9818255d44532ea8ef94b5aef56c4b407c2d634fa4f657e4ebe681ebbf59b7bac69ca"
	TEMPLATE_DIR="$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION}.stable"
	;;
*) echo "unsupported OS: $(uname -s)"; exit 1 ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
verify() { echo "$2  $1" | shasum -a 512 -c - >/dev/null || { echo "::error::checksum mismatch for $1"; exit 1; }; }

curl -fsSL --retry 3 -o "$work/editor.zip" "$BASE/$EDITOR_ZIP"
verify "$work/editor.zip" "$EDITOR_SHA512"
mkdir -p "$HOME/godot"
unzip -q -o "$work/editor.zip" -d "$HOME/godot"
if [ "$(uname -s)" = Darwin ]; then
	ln -sf "$HOME/godot/Godot.app/Contents/MacOS/Godot" "$HOME/godot/godot"
else
	ln -sf "$HOME/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64" "$HOME/godot/godot"
fi

curl -fsSL --retry 3 -o "$work/templates.tpz" "$BASE/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
verify "$work/templates.tpz" "$TEMPLATES_SHA512"
mkdir -p "$TEMPLATE_DIR"
unzip -q -o "$work/templates.tpz" -d "$work/tpl"
cp "$work"/tpl/templates/* "$TEMPLATE_DIR/"

[ -n "${GITHUB_PATH:-}" ] && echo "$HOME/godot" >> "$GITHUB_PATH"
"$HOME/godot/godot" --version
