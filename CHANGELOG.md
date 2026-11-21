# Changelog

## 1.0.1 (unreleased)

- Fixed: Blackout made a new Touch Bar brightness client for every switch and status check. macOS never frees these, and each keeps its own CoreBrightness connection: after 4.5 days, 2,529 were alive. Blackout now keeps one.
- ⌥⌘0 (Touch Bar On) while the bar is already on now does a **Force Restore**: it switches the panel off and back on. Use it if the bar is on but shows nothing.
- After Touch Bar On, Blackout reads the panel at 0.3 s and 1.5 s. If the panel is still dark, or lit but giving out no light, Blackout does one Force Restore by itself.
- Fixed: after Touch Bar On or Peek, the Touch Bar came back at its lowest brightness (about 12 nits) and stayed there, which looks dark in a lit room. Blackout now puts back the brightness it had when it was switched off.
- New **Repair Touch Bar** (⌃⌥⌘0, or in the menu) for a bar that's on but blank while touch still works. It sleeps the display and wakes it 3 s later, which clears that state without a restart. If your Mac asks for a password after sleep, you'll unlock.
- Event log at `~/Library/Logs/Blackout/Blackout.log` (also in the system log, subsystem `io.github.LeshawnG.Blackout`), and `Blackout diag` for a one-line panel reading.

## 1.0.0 (2026-11-11)

First release.

- Switches the Touch Bar panel fully off (power, not just a black screen), with a black backup bar underneath.
- Turns the panel off again within milliseconds when macOS lights it (key presses, wake, unlock).
- Keyboard shortcuts from any app: ⌥⌘0 Touch Bar On, ⌥⌘- Touch Bar Off, ⌥⌘+ (or ⌥⌘=) Touch Bar Peek: auto-off in 5 s, or 3 s after your last brightness, volume or mute change, whichever is later.
- Menu bar icon: click to switch, right-click for the menu. The status line shows the Touch Bar's brightness.
- Start at Login, which repairs itself if the app is moved, and a "Move to Applications" prompt on first launch.
- Quitting always turns the Touch Bar back on.
- Command line: `on`, `off`, `status`, `key on|off|peek`, `login on|off`, `touchtest`, `version`.
- Tested on a 13-inch M1 MacBook Pro (MacBookPro17,1) with macOS 15.4.1.
