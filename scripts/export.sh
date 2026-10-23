#!/usr/bin/env bash
# Builds the three downloadable archives into dist/ and writes dist/SHA256SUMS.
# Archive names are fixed (SendIt-macOS.zip, SendIt-Windows-x86_64.zip, SendIt-Linux-x86_64.tar.gz) so the
# README can link to .../releases/latest/download/<name>; the folder inside carries the version.
#
#   scripts/export.sh            # all platforms
#   scripts/export.sh macos      # one of: macos windows linux
#
# Needs Godot (GODOT=/path/to/godot, default `godot`) with the matching export templates, and macOS for the
# macOS build (it is ad-hoc signed with `codesign`, which Apple Silicon requires to run at all).
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
VERSION="$(tr -d '[:space:]' < VERSION)"
PLATFORMS=("${@:-macos windows linux}")
[ $# -eq 0 ] && PLATFORMS=(macos windows linux)

rm -rf export dist
mkdir -p export dist
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true   # first import can exit non-zero; the export below is the real check

stage_docs() {  # $1 = platform, $2 = folder
	cp scripts/dist/README-"$1".txt "$2/README.txt"
	cp LICENSE CREDITS.md "$2/"
}

for p in "${PLATFORMS[@]}"; do
	case "$p" in
	macos)
		[ "$(uname -s)" = Darwin ] || { echo "macOS build needs a Mac (codesign)"; exit 1; }
		"$GODOT" --headless --path . --export-release macOS "$PWD/export/SendIt-macos.zip"
		name="SendIt-$VERSION-macOS"
		mkdir -p "export/$name"
		ditto -x -k export/SendIt-macos.zip "export/$name"
		stage_docs macOS "export/$name"
		xattr -cr "export/$name"   # no AppleDouble (._*) files in the zip
		codesign --verify --deep --strict "export/$name/SendIt.app"
		(cd export && ditto -c -k --keepParent --norsrc --noextattr --noacl "$name" "../dist/SendIt-macOS.zip")
		;;
	windows)
		name="SendIt-$VERSION-Windows-x86_64"
		mkdir -p "export/$name"
		"$GODOT" --headless --path . --export-release Windows "$PWD/export/$name/SendIt.exe"
		stage_docs Windows "export/$name"
		(cd export && python3 -c "
import shutil,sys; shutil.make_archive('../dist/SendIt-Windows-x86_64','zip','.','$name')")
		;;
	linux)
		name="SendIt-$VERSION-Linux-x86_64"
		mkdir -p "export/$name"
		"$GODOT" --headless --path . --export-release Linux "$PWD/export/$name/SendIt.x86_64"
		chmod +x "export/$name/SendIt.x86_64"
		stage_docs Linux "export/$name"
		COPYFILE_DISABLE=1 tar -C export -czf "dist/SendIt-Linux-x86_64.tar.gz" "$name"
		;;
	*) echo "unknown platform: $p"; exit 2 ;;
	esac
done

(cd dist && shasum -a 256 -- * > SHA256SUMS && cat SHA256SUMS)
