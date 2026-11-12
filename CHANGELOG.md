# Changelog

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
