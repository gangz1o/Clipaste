# Releasing

This repository can attach a notarized `.dmg` to a GitHub Release automatically.
It also publishes a Sparkle appcast feed so the macOS app can check, download, and install updates in-app.

## Trigger

1. Push a version tag.
2. Create and publish a GitHub Release for that tag.
3. The `Release DMG` workflow runs automatically and uploads:
   - `Clipaste-<tag>.dmg`
   - `Clipaste-<tag>.zip`
   - `Clipaste-<tag>.dmg.sha256`
4. The workflow updates the `update-feed` branch and refreshes `appcast.xml`.
5. If `HOMEBREW_TAP_GITHUB_TOKEN` is configured, the workflow also updates the Homebrew tap cask in `gangz1o/homebrew-clipaste`.

You can also run the workflow manually with `workflow_dispatch` and provide an existing tag.

If the tag matches `vX.Y` or `vX.Y.Z`, the release build writes that value into `CFBundleShortVersionString`.

## Required GitHub Secrets

- `APPLE_TEAM_ID`
  Your Apple Developer Team ID.
- `BUILD_CERTIFICATE_BASE64`
  Base64-encoded `.p12` export of your `Developer ID Application` certificate.
- `P12_PASSWORD`
  Password used when exporting the `.p12`.
- `KEYCHAIN_PASSWORD`
  Temporary keychain password for the GitHub Actions runner.
- `SIGNING_IDENTITY`
  Example: `Developer ID Application: Your Name (TEAMID)`.
- `APPLE_API_KEY_ID`
  App Store Connect API key ID.
- `APPLE_API_ISSUER_ID`
  App Store Connect issuer ID.
- `APPLE_API_KEY_BASE64`
  Base64-encoded contents of `AuthKey_<KEYID>.p8`.
- `SPARKLE_PRIVATE_KEY`
  The private Ed25519 key exported from Sparkle `generate_keys -x`. The app ships with the matching public key in `clipaste-Info.plist`.

Optional:

- `BUILD_PROVISION_PROFILE_BASE64`
  Base64-encoded provisioning profile. Use this only if automatic signing cannot fetch the required profile for CloudKit/iCloud entitlements.
- `HOMEBREW_TAP_GITHUB_TOKEN`
  Personal access token with `repo` scope for pushing updates to `gangz1o/homebrew-clipaste`.

## Exporting the Certificate

1. Open Keychain Access.
2. Export your `Developer ID Application` certificate as `.p12`.
3. Protect it with a password.
4. Convert it to base64:

```bash
base64 -i clipaste-developer-id.p12 | pbcopy
```

Paste the result into `BUILD_CERTIFICATE_BASE64`.

## Exporting the App Store Connect Key

Convert the `.p8` key to base64:

```bash
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

Paste the result into `APPLE_API_KEY_BASE64`.

## Notes

- The workflow builds using `developer-id` export and notarizes the generated `.dmg`.
- The release script also creates a signed `.zip` update archive for Sparkle and notarizes the exported `.app` before zipping it.
- Sparkle feed artifacts are published to the `update-feed` branch and served from `https://raw.githubusercontent.com/gangz1o/Clipaste/update-feed/appcast.xml`.
- Homebrew tap updates are pushed to `https://github.com/gangz1o/homebrew-clipaste`.
- The project currently ships with iCloud entitlements in `clipaste/clipaste.entitlements` and `clipaste/clipaste-release.entitlements`.
- If automatic provisioning fails on CI, provide `BUILD_PROVISION_PROFILE_BASE64`.
- This document is maintainer-focused. Open-source contributors do not need release secrets to build the app locally.
