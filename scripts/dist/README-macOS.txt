SendIt - night highway traffic racer
====================================

1. Drag SendIt.app into your Applications folder (or anywhere you like).
2. Open it. macOS will say it can't verify the app, because SendIt is not
   notarized by Apple. Click Done, then open
   System Settings > Privacy & Security, scroll down, click "Open Anyway"
   next to SendIt, and confirm. You only do this once.

   Prefer Terminal? This does the same thing:
       xattr -dr com.apple.quarantine /Applications/SendIt.app

Controls: W/S throttle and brake, A/D steer, C camera, R restart,
          F11 fullscreen, Esc pause and settings. Gamepads work too.

Needs macOS 12 or later (Apple Silicon or Intel).
Project page: https://github.com/jedbrnth-eng/sendit
Licence: GPL-3.0 (see LICENSE). Third-party credits: CREDITS.md
