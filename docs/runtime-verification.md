# Runtime verification — September 8, 2026

Environment: Apple Silicon, macOS 26.6.2, Codex CLI 0.153.4, Claude Code 2.1.195.

| Check | Result and evidence |
| --- | --- |
| Release build | PASS. The release app, localization catalog, and bundled login helper built successfully. Strict nested signature verification passed. |
| Deterministic tests | PASS. 40 deterministic tests passed; the separate optional live-service test was skipped, for 41 discovered tests total and no deterministic failures. Coverage includes menu-bar presentation, two-AI composition, persistence, icon-color tinting, exact interval limits, stale data, retry behavior, localization, day/hour/minute reset formatting, provider PNG resource loading, and accessory activation policy. |
| Optional live Codex test | PASS separately. One initial live attempt hit the 20-second Codex app-server timeout; it was treated as a service/network event, not a deterministic failure. Three subsequent isolated runs completed in 1.28, 1.12, and 1.07 seconds. |
| Runtime type / Dock | PASS. Direct and login-helper launches reported `ApplicationType=UIElement`; lifecycle logs reported `Accessory — Dock hidden`. No Dock app was created. |
| Native menu-bar item | PASS. The macOS status-item scene was registered and the final Release logged live labels such as `5H | 86% / AI | --%` with `provider icons: 2`. |
| Status-item action | PASS. Invoking the running app's reopen path calls the native status button's action. Runtime logs recorded `Menu bar item activated` followed by `Usage popover shown`, and the actual usage window became visible. This path was used because macOS 26 hosts the status item in a separate Control Center scene that the inspection surface cannot directly address. |
| Live percentage | PASS. Codex values came from `account/rateLimits/read`; the Release menu bar refreshed from 85% to 84% during inspection and the usage popover used the same live value. Missing values never became 0%. |
| Two AI services | PASS. Codex and Claude Code remained independently configurable. Both-AI menu-bar output used `5H | …% / AI | --%`; the status item applied both native icons. |
| Claude Code | SAFE UNAVAILABLE. The installed CLI exposes `/usage` interactively and rate-limit fields to an active configured status-line process, but no supported standalone background usage command. The app showed a concise localized unavailable state without reading credentials or changing Claude settings. |
| Reset and duration UI | PASS. Relative reset text now includes days when needed (`2일 3시간 4분 후 초기화`) and retains hour/minute and minute-only forms. Duration fields use an unlabeled numeric editor with an accessibility label, so the redundant visible `값`/`Value` placeholder is gone. |
| Provider assets | PASS. The supplied `chatGPT.png` and `claude.png` bytes are bundled as `codex-provider.png` and `claude-provider.png`; resource tests load both, and the Release menu-bar log reports two successfully loaded icons. Icons default to high-contrast white and can be changed to black, accent, or secondary in Display settings; tinting is shared by the menu bar and usage window. |
| Korean usage window | PASS. The actual window showed AI 사용량, Codex, Claude Code, 5H, 주간, natural reset-time text, 마지막 확인, 다시 확인, 설정, and 종료 without clipping or overlap. Footer actions occupy equal-width centered areas. |
| Settings window and layout | PASS. The settings action opens a dedicated native window on the active desktop, activates it, and applies `.moveToActiveSpace`. The live Release window measured 780×592 points (780×560 content minimum); the native `NSWindow` minimum prevents the layout from collapsing. The sidebar is a fixed 252-point, centered row list instead of an expanding split column. Korean and English strings are catalog-backed and deterministic language-switch tests pass at this minimum layout. |
| Language switching / persistence | PASS. System Default, 한국어, and English switched without restarting. Unit tests covered both language directions and persisted storage. 한국어 remained selected after the final login-helper relaunch, and the reopened usage window was Korean. |
| Refresh controls | PASS. Duration models support seconds, minutes, and hours; values are clamped to 30 seconds through 24 hours. Global and per-AI exact intervals, open/launch/wake/network triggers, stale threshold, and retry settings are covered by tests. |
| Manual refresh | PASS. The actual 다시 확인 button triggered fresh Codex and Claude requests and updated the displayed live percentage and last-checked time. |
| Launch at Login | PASS. The setting was enabled. The bundled `SMAppService` helper relaunched the final app with `login launch: true`, no visible window, UIElement policy, live menu-bar data, provider icons, and persisted Korean UI. |
| Notifications | PASS (logic). Per-AI switches, remaining-threshold crossing, and reset re-arming are implemented without exposing secrets. Notification authorization was not changed during inspection. |
| Quit | PASS. Quit is available in the usage window and terminates the exact app process; the app can then be relaunched normally or through its login helper. |
| Sensitive logging | PASS. Runtime logs contain lifecycle state, AI names, compact percentages, and icon counts only. Raw responses, authentication material, cookies, and credentials are not logged. |

The release app always uses the live Codex provider. A weekly-only provider exists only inside `#if DEBUG` for inspecting a one-limit state.

The bundle is ad-hoc signed and is not notarized for public distribution. A physical logout/login cycle and macOS 13 runtime were not exercised; the bundled login helper itself was exercised directly on macOS 26.6.2.

The implementation is independent. No source code from the unlicensed reference repository was copied.
