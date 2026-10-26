#!/usr/bin/env bash
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

# Build one car + its preview sheet: tools/blender/build_car.sh <script stem> <preview prefix>
set -u
cd "$(dirname "$0")/../.."
STEM="$1"; PRE="$2"
/Applications/Blender.app/Contents/MacOS/Blender --background --python "tools/blender/$STEM.py" -- --preview "$PRE" 2>&1 \
  | grep -E "Error|REPORT|EXPORTED|DECAL_MISS|Traceback|File \"" | grep -v "^Read prefs" | head -40
/usr/bin/python3 tools/blender/sheet.py "${PRE}_sheet.png" "${PRE}_front34.png" "${PRE}_side.png" "${PRE}_rear34.png" "${PRE}_top.png"
