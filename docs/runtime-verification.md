# Runtime verification — September 7, 2026

Environment: Apple Silicon, macOS 26.6.2, installed Codex CLI 0.153.4.

## Results

| Check | Result and evidence |
| --- | --- |
| Release build | PASS. Both app and login helper built and ad-hoc signed. Strict nested signature verification passed. |
| Tests | PASS. 19 tests, zero failures, including the opt-in live Codex app-server test. |
| Usage retrieval | PASS. `account/rateLimits/read`; validated `100 - usedPercent`. At 12:25 KST, both the utility and Codex account readout showed 23% five-hour and 88% weekly remaining. |
| Reset dates | Five-hour: September 7 at 17:11 KST. Weekly: September 14 at 12:11 KST. |
| Window and Settings | PASS. Native window renders both remaining percentages. Settings button opens the native settings scene. |
| Manual refresh | PASS. Main window values and last-updated time changed after pressing Refresh. |
| Dock policies | PASS. Settings toggles switched the running app between regular and accessory policies; restoring regular reopened the main window. |
| Dock badge | AppKit tests verified percentage labels, selection, and clearing. Runtime settings verified the four choices and disabled badge controls when Dock visibility was off. Dock rendering itself was not independently captured. |
| No menu-bar usage item | PASS. No MenuBarExtra or NSStatusItem implementation remains. The normal macOS application menus are retained. |
| Close and keep running | PASS. Lifecycle log recorded last-window close with termination false; the process remained alive. |
| Launch again | PASS. Reopen event reached the existing process and showed the window. No duplicate process was created. |
| Close and quit | PASS. Disabling keep-running caused last-window close to terminate the app; process listing confirmed exit. |
| Hidden login helper | PASS. Direct execution of the packaged helper launched one app process with `--background-login`, accessory policy, and no main-window creation. |
| Hidden scheduled refresh | PASS. Process 18193 completed fetches at 12:21:46 and 12:22:46 while no window had been opened. |
| Login registration | PASS. Settings registered and unregistered the login item. Restored to Off afterward. A real logout/login cycle was not performed. |
| Shortcut registration | PASS. Carbon registration succeeded; disabling and reenabling through Settings worked. |
| Physical shortcut | PENDING. Automated application-targeted keypresses did not yield a Carbon shortcut event. A physical Control–Option–C check was requested; no result has been received. Do not treat registration alone as proof of key-triggered reopening. |
| Idle resources | One hidden-process sample measured 0.0% CPU and about 61 MiB RSS. This is a point-in-time sample, not a long-duration benchmark. |

## Scope and limitations

The implementation is independent. The reference repository had no declared license at review time, and no source code was copied. The app uses the locally authenticated Codex process, never browser scraping or copied credentials.

The bundle is locally ad-hoc signed, not notarized for public distribution. macOS 13 compatibility paths compile but were not exercised on a macOS 13 machine. Physical shortcut reopening, an actual login cycle, and independent visual confirmation of the Dock badge remain manual checks. The feature is not represented as fully runtime-verified until those checks are complete.
