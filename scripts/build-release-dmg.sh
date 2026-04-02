#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="${APP_NAME:-Clipaste}"
SCHEME="${SCHEME:-Clipaste}"
PROJECT_PATH="${PROJECT_PATH:-$PROJECT_ROOT/clipaste.xcodeproj}"
INFO_PLIST_PATH="${INFO_PLIST_PATH:-$PROJECT_ROOT/clipaste-Info.plist}"
CONFIGURATION="${CONFIGURATION:-Release}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-6YXB9ASQXU}"
RELEASE_TAG="${RELEASE_TAG:-}"

BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build}"
DIST_DIR="${DIST_DIR:-$BUILD_ROOT/release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_ROOT/DerivedData-Release}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_ROOT/${APP_NAME}.xcarchive}"
EXPORT_DIR="${EXPORT_DIR:-$BUILD_ROOT/export}"
DMG_STAGING_DIR="${DMG_STAGING_DIR:-$BUILD_ROOT/dmg-staging}"
TEMP_ROOT="${RUNNER_TEMP:-$BUILD_ROOT/tmp}"

KEYCHAIN_PATH="$TEMP_ROOT/build-signing.keychain-db"
CERT_PATH="$TEMP_ROOT/signing-cert.p12"
APPSTORE_CONNECT_KEY_PATH="$TEMP_ROOT/AuthKey.p8"
PROVISIONING_PROFILE_PATH="$HOME/Library/MobileDevice/Provisioning Profiles/ci-release.provisionprofile"
EXPORT_OPTIONS_PLIST="$TEMP_ROOT/ExportOptions.plist"

mkdir -p "$DIST_DIR" "$TEMP_ROOT"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$DMG_STAGING_DIR"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST_PATH")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST_PATH")"
ARTIFACT_VERSION="${RELEASE_TAG:-v${VERSION}}"
ARTIFACT_BASENAME="${APP_NAME}-${ARTIFACT_VERSION}"
DMG_PATH="$DIST_DIR/${ARTIFACT_BASENAME}.dmg"
SHA256_PATH="$DIST_DIR/${ARTIFACT_BASENAME}.dmg.sha256"

required_env=(
  BUILD_CERTIFICATE_BASE64
  P12_PASSWORD
  KEYCHAIN_PASSWORD
  SIGNING_IDENTITY
  APPLE_API_KEY_ID
  APPLE_API_ISSUER_ID
  APPLE_API_KEY_BASE64
)

missing_env=()
for name in "${required_env[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    missing_env+=("$name")
  fi
done

if (( ${#missing_env[@]} > 0 )); then
  printf 'Missing required environment variables:\n' >&2
  printf '  - %s\n' "${missing_env[@]}" >&2
  exit 1
fi

cleanup() {
  security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
  rm -f "$CERT_PATH" "$APPSTORE_CONNECT_KEY_PATH" "$EXPORT_OPTIONS_PLIST"
}
trap cleanup EXIT

printf '%s' "$BUILD_CERTIFICATE_BASE64" | base64 --decode > "$CERT_PATH"
printf '%s' "$APPLE_API_KEY_BASE64" | base64 --decode > "$APPSTORE_CONNECT_KEY_PATH"

if [[ -n "${BUILD_PROVISION_PROFILE_BASE64:-}" ]]; then
  mkdir -p "$(dirname "$PROVISIONING_PROFILE_PATH")"
  printf '%s' "$BUILD_PROVISION_PROFILE_BASE64" | base64 --decode > "$PROVISIONING_PROFILE_PATH"
fi

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db
security default-keychain -d user -s "$KEYCHAIN_PATH"

security import "$CERT_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -T /usr/bin/productbuild

security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH"

security find-identity -v -p codesigning "$KEYCHAIN_PATH"

cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingCertificate</key>
  <string>${SIGNING_IDENTITY}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>${APPLE_TEAM_ID}</string>
</dict>
</plist>
EOF

xcode_auth_args=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$APPSTORE_CONNECT_KEY_PATH"
  -authenticationKeyID "$APPLE_API_KEY_ID"
  -authenticationKeyIssuerID "$APPLE_API_ISSUER_ID"
)

archive_args=(
  xcodebuild
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=macOS"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -archivePath "$ARCHIVE_PATH"
  CODE_SIGN_STYLE=Automatic
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID"
  OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH"
)
archive_args+=("${xcode_auth_args[@]}")
archive_args+=(archive)

"${archive_args[@]}"

export_args=(
  xcodebuild
  -exportArchive
  -archivePath "$ARCHIVE_PATH"
  -exportPath "$EXPORT_DIR"
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
  OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH"
)
export_args+=("${xcode_auth_args[@]}")

"${export_args[@]}"

APP_PATH="$(find "$EXPORT_DIR" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "Failed to locate exported .app bundle." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl -a -t exec -vv "$APP_PATH"

mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_PATH" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

xcrun notarytool submit "$DMG_PATH" \
  --key "$APPSTORE_CONNECT_KEY_PATH" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --wait

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

shasum -a 256 "$DMG_PATH" > "$SHA256_PATH"

cat <<EOF
Built release artifacts:
  App: $APP_PATH
  DMG: $DMG_PATH
  SHA256: $SHA256_PATH
  Version: $VERSION ($BUILD_NUMBER)
EOF
