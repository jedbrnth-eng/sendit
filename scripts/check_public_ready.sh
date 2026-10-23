#!/bin/sh
# Fails if the repo leaks personal data or ships something it should not. CI and the release run it.
# Checks: absolute home paths, personal email addresses, machine-local commit identities, .DS_Store in
# history, build outputs tracked in git, and real car marques in tracked file names.
set -u
cd "$(dirname "$0")/.." || exit 2
fail=0

hits=$(git grep -n -I -E '(/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]+/)' -- . ':!scripts/check_public_ready.sh' ':!.github/workflows/ci.yml')
if [ -n "$hits" ]; then echo "FAIL: absolute user paths in tracked files:"; echo "$hits" | cut -c1-140 | head -10; fail=1; fi

bad=$(git log --all --format='%ae' | grep -E '@local$|\.local$' | sort -u)
if [ -n "$bad" ]; then echo "FAIL: machine-local commit author emails: $bad"; fail=1; fi

ds=$(git log --all --name-only --pretty=format: | grep -c '\.DS_Store')
if [ "$ds" -gt 0 ]; then echo "FAIL: .DS_Store present in history ($ds entries)"; fail=1; fi

em=$(git grep -n -I -E -o '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z.]{2,}' -- . ':!scripts/check_public_ready.sh' | grep -v -E '@(users\.noreply\.github\.com|example\.(com|org|net))$')
if [ -n "$em" ]; then echo "FAIL: email addresses in tracked files:"; echo "$em" | head -5; fail=1; fi

built=$(git ls-files | grep -E '^(dist|export|\.godot)/')
if [ -n "$built" ]; then echo "FAIL: build output tracked in git:"; echo "$built" | head -5; fail=1; fi

brands=$(git ls-files | grep -i -E '(^|[^a-z])(ferrari|lamborghini|porsche|bmw|mercedes|audi|toyota|honda|nissan|tesla|bugatti|mclaren)([^a-z]|$)')
if [ -n "$brands" ]; then echo "FAIL: real car marques in file names:"; echo "$brands" | head -5; fail=1; fi

[ "$fail" -eq 0 ] && echo "OK: no personal data found"
exit "$fail"
