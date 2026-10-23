#!/usr/bin/env bash
# SendIt installer for macOS and Linux. Downloads the latest release, verifies it against the release's
# SHA256SUMS, installs it and (on a Mac) clears the download flag so there is no "Open Anyway" step.
# Source: https://github.com/jedbrnth-eng/sendit
#
#   curl -fsSL https://raw.githubusercontent.com/jedbrnth-eng/sendit/main/install.sh | bash
#
# Environment (all optional): SENDIT_INSTALL_DIR (default /Applications, or ~/Applications; Linux:
# ~/.local/share/sendit), SENDIT_BASE_URL (a mirror or a local test server), SENDIT_NO_OPEN=1 (do not launch).
set -euo pipefail

REPO="jedbrnth-eng/sendit"
BASE="${SENDIT_BASE_URL:-https://github.com/$REPO/releases/latest/download}"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

case "$(uname -s)-$(uname -m)" in
Darwin-*) FILE="SendIt-macOS.zip" ;;
Linux-x86_64) FILE="SendIt-Linux-x86_64.tar.gz" ;;
Linux-*) die "SendIt's Linux build is for x86-64. This machine is $(uname -m)." ;;
*) die "This installer is for macOS and Linux. On Windows, download SendIt-Windows-x86_64.zip from https://github.com/$REPO/releases/latest" ;;
esac

if [ -n "${SENDIT_INSTALL_DIR:-}" ]; then
	DEST="$SENDIT_INSTALL_DIR"
elif [ "$(uname -s)" = Darwin ]; then
	DEST="/Applications"
	[ -w "$DEST" ] || DEST="$HOME/Applications"
else
	DEST="$HOME/.local/share/sendit"
fi
mkdir -p "$DEST"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi; }

say "Downloading SendIt (about 150 MB)..."
curl -fL --progress-bar -o "$TMP/$FILE" "$BASE/$FILE" || die "Download failed. Check your internet connection, or download it by hand from https://github.com/$REPO/releases/latest"
curl -fsSL -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS" || die "Could not download SHA256SUMS to verify the file."

want="$(awk -v f="$FILE" '$2 == f {print $1}' "$TMP/SHA256SUMS")"
[ -n "$want" ] || die "Checksum list has no entry for $FILE. Not installing."
have="$(sha256 "$TMP/$FILE")"
[ "$want" = "$have" ] || die "Checksum mismatch for $FILE (expected $want, got $have). Not installing."
say "Checksum OK."

say "Installing to $DEST..."
if [ "$(uname -s)" = Darwin ]; then
	ditto -x -k "$TMP/$FILE" "$TMP/out"
	APP="$(find "$TMP/out" -maxdepth 2 -name SendIt.app -type d | head -n1)"
	[ -n "$APP" ] || die "The download didn't contain SendIt.app. Please open an issue."
	if pgrep -x SendIt >/dev/null 2>&1; then
		osascript -e 'tell application "SendIt" to quit' >/dev/null 2>&1 || true
		sleep 2
	fi
	rm -rf "$DEST/SendIt.app"
	ditto "$APP" "$DEST/SendIt.app"
	xattr -dr com.apple.quarantine "$DEST/SendIt.app" 2>/dev/null || true
	[ "${SENDIT_NO_OPEN:-}" = 1 ] || { say "Done. Opening SendIt..."; open "$DEST/SendIt.app"; }
else
	tar -xzf "$TMP/$FILE" -C "$TMP"
	DIR="$(find "$TMP" -maxdepth 1 -type d -name 'SendIt-*-Linux-x86_64' | head -n1)"
	[ -n "$DIR" ] || die "The download didn't contain the SendIt folder. Please open an issue."
	cp -R "$DIR"/. "$DEST"/
	chmod +x "$DEST/SendIt.x86_64"
	say "Done. Run it with: $DEST/SendIt.x86_64"
	[ "${SENDIT_NO_OPEN:-}" = 1 ] || { nohup "$DEST/SendIt.x86_64" >/dev/null 2>&1 & }
fi
