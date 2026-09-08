# Distribution

The product is **Token Menu**; the GitHub repository and download filenames use `token-menu`.

## Build a DMG

```sh
swift test
./scripts/build-dmg.sh
VERSION=1.0.1
hdiutil verify "dist/token-menu-${VERSION}-macOS-universal.dmg"
cd dist
shasum -a 256 -c "token-menu-${VERSION}-macOS-universal.dmg.sha256"
```

The default build contains arm64 and x86_64 slices in both the app and login helper. The DMG contains Token Menu.app, an Applications shortcut, and bilingual installation instructions. Build output and previous local ZIPs are excluded from Git.

The generated icon is compiled at 16 through 1024 pixels into an ICNS. The application uses `CFBundleIconFile` so Finder and the installer show the same icon. Provider icons remain separate and are documented in [NOTICE.md](../NOTICE.md).

The bundle identifiers and Swift target names retain their existing values for preference and login-item compatibility. The login helper finds its containing app by bundle hierarchy, not a hard-coded product name.

## Signing

The build script produces an ad-hoc-signed app. This verifies local bundle integrity but is not a Developer ID signature and does not constitute Apple notarization.

For a notarized public build, the maintainer must sign the helper and app with their own Developer ID Application certificate and hardened-runtime entitlements suitable for the app, submit the signed distribution with `xcrun notarytool`, staple the accepted ticket, then recreate and verify the DMG. No Developer ID certificate or notarization credentials are supplied by this project.

## Publish

Commit the reviewed source and documentation to the repository before tagging the same commit. Upload the DMG and its checksum to a release, not to the source tree.

```sh
git tag v1.0.1
git push origin main
git push origin v1.0.1
gh release create v1.0.1 \
  dist/token-menu-1.0.1-macOS-universal.dmg \
  dist/token-menu-1.0.1-macOS-universal.dmg.sha256 \
  --repo kimjaeyun124/token-menu --verify-tag \
  --title "Token Menu 1.0.1" --notes-file docs/releases/v1.0.1.md
```

A private repository's releases can only be downloaded by authorized users. Publishing a release does not change repository visibility.

## Verification

Run the deterministic suite separately from the opt-in live Codex service test. A live query timeout must be reported as a service timeout.

Check both executable architectures, nested signatures, the DMG checksum and mount contents. Launch the app after copying it out of the image and verify the menu-bar item, live query, app icon, sidebar click area, and Settings minimum size. Intel and macOS 13 runtime support must not be claimed as tested without running there.

Historical implementation checks are in [runtime-verification.md](runtime-verification.md); they are not a substitute for verifying a new distribution.
