# Codex Usage Monitor

A lightweight native macOS menu bar utility that shows remaining Codex capacity for the available 5-hour and weekly rate-limit windows.

## Behavior

- The menu bar shows a compact labeled value such as `5H 83%` or `Weekly 84%`.
- Automatic mode prefers a valid 5-hour window and falls back to weekly when 5-hour data is absent.
- Clicking the menu bar item opens a compact popover with only the limits returned by Codex.
- The Dock icon stays hidden through macOS UI-element/accessory behavior.
- Refresh runs at launch, manually, and every 1, 5, 10, or 30 minutes.
- Launch at Login uses a bundled `SMAppService` helper.
- Control–Option–C remains an optional secondary way to open the popover.

Missing limits are omitted and never interpreted as zero. If no supported window is available, the menu bar displays `Codex --%` and the popover displays “Usage unavailable.” The app never estimates token counts.

## Data source and privacy

The app launches the installed Codex CLI's structured app-server protocol and calls `account/rateLimits/read`. Codex labels each window as `usedPercent`; after validating a finite value in `0...100`, the app displays `100 - usedPercent` as remaining.

The app does not read, copy, store, print, or upload authentication files. Authentication and the request remain inside the installed Codex process. Raw responses and credentials are never logged.

Supported Codex locations include `~/.local/bin/codex`, Homebrew paths, and executables bundled with the ChatGPT or Codex desktop apps.

## Reference review

The public behavior of [burakereno/codex-monitor](https://github.com/burakereno/codex-monitor) was reviewed. At review time the repository had no `LICENSE` or `COPYING` file and GitHub declared no license. This project is an independent implementation; no reference source code was copied.

## Build and test

Requirements: macOS 13 or later, Swift 5.9 or later, and an installed authenticated Codex CLI or desktop app.

```sh
swift test
CODEX_LIVE_TEST=1 swift test
./scripts/build-app.sh
open "dist/Codex Usage.app"
```

The build script creates an ad-hoc-signed app at `dist/Codex Usage.app`, including its login helper. Install the packaged app in Applications for normal Launch at Login use.

## Architecture

```text
Sources/CodexUsageMonitor/
├── App/          Lifecycle and accessory visibility
├── MenuBar/      Native NSStatusItem and dynamic popover sizing
├── Models/       Remaining percentages, visible limits, and display selection
├── Services/     Codex detection, app-server parsing, refresh, notifications
├── Shortcuts/    Optional Control–Option–C shortcut
├── UI/           Compact usage popover and settings
└── Utilities/    Process execution
```

`Sources/CodexUsageLauncher/` contains the bundled login-item helper. See [runtime verification](docs/runtime-verification.md) for the tested states and limitations.
