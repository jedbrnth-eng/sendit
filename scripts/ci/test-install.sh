#!/usr/bin/env bash
# Tests install.sh against a local copy of a release (no network, no real /Applications).
#
#   scripts/ci/test-install.sh <dir-with-release-assets>
#
# The directory must hold SendIt-macOS.zip (or the Linux tarball on Linux) and SHA256SUMS, e.g. the output of
# `gh release download` or scripts/export.sh. Cases: good install, tampered download rejected, unsupported
# platform arguments, missing checksum entry rejected.
set -u
cd "$(dirname "$0")/../.."
ASSETS="${1:?usage: test-install.sh <assets-dir>}"
fail=0
check() { if [ "$2" = "0" ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }

work="$(mktemp -d)"
cleanup() { [ -n "${srv:-}" ] && kill "$srv" 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT

cp "$ASSETS"/SHA256SUMS "$work/"
for f in SendIt-macOS.zip SendIt-Linux-x86_64.tar.gz; do [ -f "$ASSETS/$f" ] && cp "$ASSETS/$f" "$work/"; done
mkdir -p "$work/srv"; cp "$work"/SendIt-* "$work/SHA256SUMS" "$work/srv/"
port=$((20000 + RANDOM % 20000))
(cd "$work/srv" && exec python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) & srv=$!
sleep 1
export SENDIT_BASE_URL="http://127.0.0.1:$port" SENDIT_NO_OPEN=1

echo "good install"
home="$work/home1"; mkdir -p "$home"
HOME="$home" SENDIT_INSTALL_DIR="$work/apps1" bash install.sh >"$work/out1.log" 2>&1
check "installer exits 0" "$?"
if [ "$(uname -s)" = Darwin ]; then
	[ -x "$work/apps1/SendIt.app/Contents/MacOS/SendIt" ]; check "SendIt.app installed" "$?"
	codesign --verify --deep --strict "$work/apps1/SendIt.app" 2>/dev/null; check "signature intact" "$?"
	! xattr -p com.apple.quarantine "$work/apps1/SendIt.app" >/dev/null 2>&1; check "no quarantine flag" "$?"
else
	[ -x "$work/apps1/SendIt.x86_64" ]; check "binary installed and executable" "$?"
fi

echo "tampered download is rejected"
printf 'x' >> "$work/srv/$( [ "$(uname -s)" = Darwin ] && echo SendIt-macOS.zip || echo SendIt-Linux-x86_64.tar.gz )"
HOME="$work/home2" SENDIT_INSTALL_DIR="$work/apps2" bash install.sh >"$work/out2.log" 2>&1
[ $? -ne 0 ]; check "installer exits non-zero" "$?"
grep -qi "checksum" "$work/out2.log"; check "says why (checksum)" "$?"
[ ! -e "$work/apps2/SendIt.app" ] && [ ! -e "$work/apps2/SendIt.x86_64" ]; check "nothing installed" "$?"

echo "missing checksum entry is rejected"
: > "$work/srv/SHA256SUMS"
HOME="$work/home3" SENDIT_INSTALL_DIR="$work/apps3" bash install.sh >"$work/out3.log" 2>&1
[ $? -ne 0 ]; check "installer exits non-zero" "$?"

[ "$fail" -eq 0 ] && echo "INSTALL TESTS: PASS" || echo "INSTALL TESTS: FAIL"
exit "$fail"
