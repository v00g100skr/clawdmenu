# ClawdMenu

A tiny macOS menu bar app that shows your Claude Code usage: the 5-hour session, the weekly limit, and time until reset. It is a menu bar take on [Clawdmeter](https://github.com/HermannBjorgvin/Clawdmeter), using the same data source and no hardware.

The menu bar shows the Clawd icon plus e.g. `42% · 2h13m` (session usage · time until reset). Click it for the details.

## Features

- Session (5h) and weekly (7d) usage with progress bars and reset countdowns
- Limit status; Enterprise accounts get a single spending-limit (overage) bar
- Notifications at 80% and 95% of the session, and when the session resets
- Configurable refresh interval (30 s, 1 min, 2 min, 5 min)
- Launch at login toggle
- Menu bar only: no Dock icon

## Requirements

- macOS 13 or later
- Swift toolchain (Xcode or Command Line Tools)
- Claude Code installed and signed in (the app reads its OAuth token)

## Build and run

```bash
./build.sh
open ClawdMenu.app
```

`build.sh` runs `swift build -c release`, assembles `ClawdMenu.app` (Info.plist, icon, menu bar sprite) and ad-hoc signs it.

## How it works

Every refresh the app:

1. Reads the Claude Code OAuth token from the macOS Keychain (service `Claude Code-credentials`) via `/usr/bin/security`.
2. Sends a minimal 1-token request to `https://api.anthropic.com/v1/messages`.
3. Reads the `anthropic-ratelimit-unified-*` response headers (`5h-utilization`, `5h-reset`, `7d-utilization`, `7d-reset`, status) and renders them.

The token never leaves your machine except in that request to Anthropic. Each poll uses a tiny amount of quota (one 1-token Haiku call).

This logic is ported from the Clawdmeter daemon (`daemon/claude_usage_daemon.py`).

## Notes

- **Keychain prompt:** on first run macOS asks for Keychain access. Choose *Always Allow*.
- **Launch at login:** uses `SMAppService`. With the ad-hoc signature it may fail to register; if so, add `ClawdMenu.app` manually in System Settings → General → Login Items.
- **Errors:** if the menu bar shows `!`, open the popover to see the message (token missing, HTTP error, etc.).
- **Notifications** are requested lazily, on the first alert.

## Project layout

```
Package.swift                     SwiftPM manifest
Sources/ClawdMenu/ClawdMenuApp.swift   the whole app (model, API, UI)
build.sh                          builds and bundles ClawdMenu.app
make-icon.swift                   generates AppIcon.iconset from clawd.png
AppIcon.icns, clawd.png           app icon and menu bar sprite
```

To regenerate the icon:

```bash
swift make-icon.swift clawd.png AppIcon.iconset && iconutil -c icns AppIcon.iconset -o AppIcon.icns
```

## Credits

- [Clawdmeter](https://github.com/HermannBjorgvin/Clawdmeter) for the original device and the rate-limit polling approach.
- Pixel-art Clawd sprite from [claudepix](https://claudepix.vercel.app) by [@amaanbuilds](https://x.com/amaanbuilds).
