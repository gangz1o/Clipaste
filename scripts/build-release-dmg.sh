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
PROFILE_INSTALL_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
PROVISIONING_PROFILE_PATH="$PROFILE_INSTALL_DIR/ci-release.provisionprofile"
PROFILE_METADATA_PLIST="$TEMP_ROOT/provisioning-profile.plist"
EXPORT_OPTIONS_PLIST="$TEMP_ROOT/ExportOptions.plist"

PROFILE_UUID=""
PROFILE_NAME=""

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
  BUILD_PROVISION_PROFILE_BASE64
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
  rm -f "$CERT_PATH" "$APPSTORE_CONNECT_KEY_PATH" "$EXPORT_OPTIONS_PLIST" "$PROFILE_METADATA_PLIST"
}
trap cleanup EXIT

load_profile_metadata() {
  local profile_path="$1"

  security cms -D -i "$profile_path" > "$PROFILE_METADATA_PLIST"
  PROFILE_UUID="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$PROFILE_METADATA_PLIST")"
  PROFILE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$PROFILE_METADATA_PLIST")"
}

validate_release_profile() {
  if [[ "$PROFILE_NAME" == Mac\ Team\ Provisioning\ Profile:* ]]; then
    cat >&2 <<EOF
BUILD_PROVISION_PROFILE_BASE64 must be a manually created Developer ID provisioning profile.
The provided profile is Xcode-managed and cannot be used for Developer ID export:
  Name: $PROFILE_NAME
  UUID: $PROFILE_UUID
EOF
    exit 1
  fi
}

install_profile() {
  local source_path="$1"

  mkdir -p "$PROFILE_INSTALL_DIR"
  load_profile_metadata "$source_path"
  validate_release_profile
  PROVISIONING_PROFILE_PATH="$PROFILE_INSTALL_DIR/${PROFILE_UUID}.provisionprofile"
  cp "$source_path" "$PROVISIONING_PROFILE_PATH"
}

printf '%s' "$BUILD_CERTIFICATE_BASE64" | base64 --decode > "$CERT_PATH"
printf '%s' "$APPLE_API_KEY_BASE64" | base64 --decode > "$APPSTORE_CONNECT_KEY_PATH"

mkdir -p "$PROFILE_INSTALL_DIR"
printf '%s' "$BUILD_PROVISION_PROFILE_BASE64" | base64 --decode > "$PROVISIONING_PROFILE_PATH"
install_profile "$PROVISIONING_PROFILE_PATH"

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
printf 'Using provisioning profile for export: %s (%s)\n' "$PROFILE_NAME" "$PROFILE_UUID"

archive_args=(
  xcodebuild
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=macOS"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -archivePath "$ARCHIVE_PATH"
  CODE_SIGN_STYLE=Manual
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID"
  OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH"
)
archive_args+=(archive)

"${archive_args[@]}"

ARCHIVED_APP_PATH="$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"
if [[ ! -d "$ARCHIVED_APP_PATH" ]]; then
  echo "Failed to locate archived app bundle at $ARCHIVED_APP_PATH." >&2
  exit 1
fi

APP_BUNDLE_IDENTIFIER="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "$ARCHIVED_APP_PATH/Contents/Info.plist"
)"

cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>${APP_BUNDLE_IDENTIFIER}</key>
    <string>${PROFILE_UUID}</string>
  </dict>
  <key>signingCertificate</key>
  <string>${SIGNING_IDENTITY}</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>${APPLE_TEAM_ID}</string>
</dict>
</plist>
EOF

export_args=(
  xcodebuild
  -exportArchive
  -archivePath "$ARCHIVE_PATH"
  -exportPath "$EXPORT_DIR"
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
  OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH"
)

"${export_args[@]}"

APP_PATH="$(find "$EXPORT_DIR" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "Failed to locate exported .app bundle." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_PATH" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

codesign --force \
  --sign "$SIGNING_IDENTITY" \
  --keychain "$KEYCHAIN_PATH" \
  "$DMG_PATH"

codesign --verify --verbose=2 "$DMG_PATH"

xcrun notarytool submit "$DMG_PATH" \
  --key "$APPSTORE_CONNECT_KEY_PATH" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --wait

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"

shasum -a 256 "$DMG_PATH" > "$SHA256_PATH"

cat <<EOF
Built release artifacts:
  App: $APP_PATH
  DMG: $DMG_PATH
  SHA256: $SHA256_PATH
  Version: $VERSION ($BUILD_NUMBER)
EOF
