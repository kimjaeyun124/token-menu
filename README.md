# Codex Usage Monitor

A lightweight, native macOS menu-bar app that shows the percentage of Codex capacity remaining in the current 5-hour and weekly windows.

## What it shows

- Menu bar: 5-hour, weekly, or lowest remaining percentage
- Dock badge: 5-hour, weekly, lowest remaining percentage, or off
- Popover: both remaining percentages, reset times, status labels, last update, and refresh
- Optional notification when a limit crosses 50%, 20%, or 10% remaining
- Optional launch at login

The app never estimates a token allowance. All primary quota displays are percentages.

## Reference review

The public behavior of [burakereno/codex-monitor](https://github.com/burakereno/codex-monitor) was reviewed as requested: native menu-bar presentation, popover interaction, Dock badge behavior, manual refresh, and its Codex app-server data flow. At the time of review the reference repository did not contain a `LICENSE` or `COPYING` file and GitHub did not declare a license. This project therefore uses only those public behavioral ideas and contains an independent implementation; no reference source code was copied.

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

The build script creates an ad-hoc-signed application at `dist/Codex Usage.app`. Launch at Login works from the packaged app, not from `swift run`.

## Architecture

```text
Sources/CodexUsageMonitor/
├── App/          SwiftUI application entry point
├── Dock/         Native Dock badge updates
├── Models/       Explicit remaining-percentage models and settings
├── Services/     Codex detection, protocol client, parsing, refresh, notifications
├── UI/           Menu-bar popover and settings
└── Utilities/    Process execution
```

## Failure behavior

Unavailable or invalid values display as `--%` or `Unavailable`. The app does not guess when Codex is missing, unauthenticated, offline, returns an unsupported window, or reports an invalid percentage.
