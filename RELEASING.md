# Releasing

This repository can attach a notarized `.dmg` to a GitHub Release automatically.

## Trigger

1. Push a version tag.
2. Create and publish a GitHub Release for that tag.
3. The `Release DMG` workflow runs automatically and uploads:
   - `Clipaste-<tag>.dmg`
   - `Clipaste-<tag>.dmg.sha256`

You can also run the workflow manually with `workflow_dispatch` and provide an existing tag.

## Required GitHub Secrets

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

Optional:

- `BUILD_PROVISION_PROFILE_BASE64`
  Base64-encoded provisioning profile. Use this only if automatic signing cannot fetch the required profile for CloudKit/iCloud entitlements.

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
- The project currently ships with iCloud entitlements in [clipaste.entitlements](/Users/gangz1o/macos-app/clipaste/clipaste/clipaste.entitlements). If automatic provisioning fails on CI, provide `BUILD_PROVISION_PROFILE_BASE64`.
- For public releases, confirm your release signing setup uses the correct production entitlements and Apple team configuration.
