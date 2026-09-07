# Codex Usage Monitor

A lightweight, native macOS utility window that shows the percentage of Codex capacity remaining in the current 5-hour and weekly windows.

## What it shows

- Main window: 5-hour and weekly remaining percentages, reset times, status labels, and refresh
- Dock badge: 5-hour, weekly, lowest remaining percentage, or off
- Optional hidden-Dock background mode
- Control–Option–C global shortcut for reopening the window
- Optional notification when a limit crosses 50%, 20%, or 10% remaining
- Optional launch at login

The app never estimates a token allowance. All primary quota displays are percentages.
It intentionally creates no `MenuBarExtra`, `NSStatusItem`, menu-bar icon, or menu-bar percentage.

## Reference review

The public behavior of [burakereno/codex-monitor](https://github.com/burakereno/codex-monitor) was reviewed as requested, including its Dock badge, manual refresh, and Codex app-server data flow. At the time of review the reference repository did not contain a `LICENSE` or `COPYING` file and GitHub did not declare a license. This project therefore uses only those public behavioral ideas and contains an independent implementation; no reference source code was copied.

## Data source and privacy

The app launches the installed Codex CLI's structured app-server protocol and calls the official `account/rateLimits/read` method. Codex labels each window as `usedPercent`; this app validates that the value is finite and between 0 and 100, then displays `100 - usedPercent` as remaining.

The app does not read, copy, store, print, or upload authentication files. Authentication and the network request remain inside the installed Codex process. Invalid and malformed values are omitted, and logs never include the raw response.

Supported Codex locations include `~/.local/bin/codex`, Homebrew paths, and the executables bundled with the ChatGPT or Codex desktop apps.

## Requirements

- macOS 13 or later
- Apple Silicon recommended
- Xcode / Swift 5.9 or later
- An installed, authenticated Codex CLI or desktop app with `account/rateLimits/read` support

## Build and test

```sh
swift test
./scripts/build-app.sh
open "dist/Codex Usage.app"
```

The build script creates an ad-hoc-signed application at `dist/Codex Usage.app`, including a bundled login helper. Launch at Login works from the packaged app installed in Applications, not from `swift run`.

## Window and Dock behavior

The app starts as a regular Dock application. Turning off **Show in Dock** switches to AppKit's accessory activation policy and removes the Dock badge without stopping refreshes. Closing the window keeps the process alive by default. Reopen it with Control–Option–C, Spotlight, Applications, or by launching the app again; macOS routes that reopen event to the existing process.

When Launch at Login, hidden Dock, and keep-running mode are all enabled, the bundled `SMAppService` login helper opens the main app with a background flag so no window appears at login. The global shortcut and normal macOS reopen event remain available.

If another application owns Control–Option–C, Settings reports that the shortcut is unavailable; launching the app again remains the recovery path. The shortcut can be disabled in Settings.

## Verification

See [runtime verification](docs/runtime-verification.md) for tested behavior and remaining manual checks. Lifecycle logs contain only visibility, shortcut registration, and refresh-completion events, with no account data or raw protocol responses.

## Architecture

```text
Sources/CodexUsageMonitor/
├── App/          App delegate, application visibility, and SwiftUI entry point
├── Dock/         Native Dock badge updates
├── Models/       Explicit remaining-percentage models and settings
├── Services/     Codex detection, protocol client, parsing, refresh, notifications
├── Shortcuts/    Global Control–Option–C shortcut
├── UI/           Main usage window and settings
└── Utilities/    Process execution
```

`Sources/CodexUsageLauncher/` contains the small bundled login-item helper.

## Failure behavior

Unavailable or invalid values display as `--%` or `Unavailable`. The app does not guess when Codex is missing, unauthenticated, offline, returns an unsupported window, or reports an invalid percentage.
