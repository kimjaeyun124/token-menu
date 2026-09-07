# Runtime verification — September 7, 2026

Environment: Apple Silicon, macOS 26.6.2, Codex CLI 0.153.4.

| Check | Result and evidence |
| --- | --- |
| Release build | PASS. Main app and login helper built and passed strict nested signature verification. |
| Tests | PASS. 21 tests, including the live Codex app-server test. |
| Runtime type / Dock | PASS. `lsappinfo` reported `ApplicationType=UIElement`; lifecycle state reported accessory policy and hidden Dock. |
| Menu bar label | PASS. The running native status item changed from its neutral startup value to `5H 82%`, then `5H 81%` after Refresh. |
| Status-item action | PASS. Runtime activation invoked the native status button action and displayed its popover. |
| Compact popover | PASS. Two-limit runtime layout measured 330 × 270 points; it used 18-point percentages, thin bars, no cards, and no large status labels. |
| Manual refresh | PASS. The live popover changed from 82% to 81% five-hour remaining and updated its timestamp; the menu label changed with it. |
| Dynamic weekly-only layout | PASS. A debug-only runtime fixture produced `Weekly 84%`, omitted 5H completely, and used the 330 × 205-point one-limit popover. The fixture is excluded from release builds. |
| Automatic/fallback states | PASS. Tests cover both windows, weekly-only, five-hour-only, no windows, explicit unavailable-selection fallback, and lowest ignoring missing data. |
| Settings | PASS. Automatic, 5-Hour, Weekly, and Lowest choices appeared and persisted; diagnostics were removed from the main popover. |
| Launch at Login | PASS. The packaged helper launched one UI-element process with `--background-login`; the menu label updated to `5H 75%`. Login-item registration had previously been registered and read back through Settings. |
| Quit | PASS. Quit was clicked in the menu bar popover and the process exited. |
| Scheduled refresh | PASS. A prior hidden-process runtime run completed consecutive one-minute refreshes. |

The release app always uses the live `account/rateLimits/read` provider. The weekly-only provider exists only inside `#if DEBUG` to inspect a one-limit runtime state unavailable on the current account.

The bundle is ad-hoc signed and is not notarized for public distribution. A real logout/login cycle and macOS 13 runtime were not exercised. The native status-button action was exercised through the app’s launch-again handler because the automation surface cannot directly address macOS 26’s separately hosted status-item scene.

The implementation is independent. No source code from the unlicensed reference repository was copied.
