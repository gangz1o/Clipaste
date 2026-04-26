#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="${APP_NAME:-Clipaste}"
SCHEME="${SCHEME:-Clipaste}"
PROJECT_PATH="${PROJECT_PATH:-$PROJECT_ROOT/clipaste.xcodeproj}"
INFO_PLIST_PATH="${INFO_PLIST_PATH:-$PROJECT_ROOT/clipaste-Info.plist}"
CONFIGURATION="${CONFIGURATION:-Release}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
RELEASE_TAG="${RELEASE_TAG:-}"
XCODE_VERSION="${XCODE_VERSION:-}"
XCODE_BUILD_VERSION="${XCODE_BUILD_VERSION:-}"
EXPECTED_APP_SDK_VERSION="${EXPECTED_APP_SDK_VERSION:-}"

BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build}"
DIST_DIR="${DIST_DIR:-$BUILD_ROOT/release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_ROOT/DerivedData-Release}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_ROOT/${APP_NAME}.xcarchive}"
EXPORT_DIR="${EXPORT_DIR:-$BUILD_ROOT/export}"
DMG_STAGING_DIR="${DMG_STAGING_DIR:-$BUILD_ROOT/dmg-staging}"
DMG_RW_PATH="${DMG_RW_PATH:-$BUILD_ROOT/${ARTIFACT_BASENAME:-$APP_NAME}-rw.dmg}"
DMG_MOUNT_DIR="${DMG_MOUNT_DIR:-$BUILD_ROOT/dmg-mount}"
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

require_exact_match() {
  local name="$1"
  local actual="$2"
  local expected="$3"

  if [[ -n "$expected" && "$actual" != "$expected" ]]; then
    cat >&2 <<EOF
Unexpected $name.
Expected: $expected
Actual:   $actual
EOF
    exit 1
  fi
}

current_xcode_version() {
  xcodebuild -version | awk 'NR == 1 { print $2 }'
}

current_xcode_build_version() {
  xcodebuild -version | awk 'NR == 2 { print $3 }'
}

current_developer_dir() {
  xcode-select -p
}

resolve_app_sdk_version() {
  local app_path="$1"
  local binary_path="$app_path/Contents/MacOS/$APP_NAME"

  otool -l "$binary_path" |
    awk '
      /LC_BUILD_VERSION/ { in_build_version = 1; next }
      in_build_version && /sdk / { print $2; exit }
    '
}

resolve_build_setting() {
  local key="$1"

  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null |
    awk -v key="$key" '$1 == key && $2 == "=" { print $3; exit }'
}

derive_release_build_number() {
  local fallback="$1"

  if [[ -n "${RELEASE_BUILD_NUMBER:-}" ]]; then
    printf '%s\n' "$RELEASE_BUILD_NUMBER"
    return
  fi

  if [[ "$RELEASE_TAG" =~ ^v?([0-9]+)\.([0-9]+)(\.([0-9]+))?$ ]]; then
    local major="${BASH_REMATCH[1]}"
    local minor="${BASH_REMATCH[2]}"
    local patch="${BASH_REMATCH[4]:-0}"
    printf '%s\n' "$(( major * 10000 + minor * 100 + patch ))"
    return
  fi

  printf '%s\n' "$fallback"
}

mkdir -p "$DIST_DIR" "$TEMP_ROOT"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$DMG_STAGING_DIR"

VERSION="$(resolve_build_setting MARKETING_VERSION)"
if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST_PATH")"
fi

BUILD_NUMBER="$(resolve_build_setting CURRENT_PROJECT_VERSION)"
if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST_PATH")"
fi

RELEASE_VERSION="$VERSION"
if [[ "$RELEASE_TAG" =~ ^v?([0-9]+(\.[0-9]+){1,2})$ ]]; then
  RELEASE_VERSION="${BASH_REMATCH[1]}"
fi

RELEASE_BUILD_NUMBER="$(derive_release_build_number "$BUILD_NUMBER")"
if ! [[ "$RELEASE_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  cat >&2 <<EOF
Unable to determine a numeric CURRENT_PROJECT_VERSION for the release build.
Resolved value: $RELEASE_BUILD_NUMBER
Provide RELEASE_BUILD_NUMBER explicitly or update the project build number.
EOF
  exit 1
fi

ARTIFACT_VERSION="${RELEASE_TAG:-v${RELEASE_VERSION}}"
ARTIFACT_BASENAME="${APP_NAME}-${ARTIFACT_VERSION}"
ZIP_PATH="$DIST_DIR/${ARTIFACT_BASENAME}.zip"
DMG_PATH="$DIST_DIR/${ARTIFACT_BASENAME}.dmg"
SHA256_PATH="$DIST_DIR/${ARTIFACT_BASENAME}.dmg.sha256"
ZIP_NOTARIZATION_PATH="$TEMP_ROOT/${ARTIFACT_BASENAME}-notarization.zip"

required_env=(
  APPLE_TEAM_ID
  BUILD_CERTIFICATE_BASE64
  BUILD_PROVISION_PROFILE_BASE64
  P12_PASSWORD
  KEYCHAIN_PASSWORD
  SIGNING_IDENTITY
  APPLE_API_KEY_ID
  APPLE_API_ISSUER_ID
  APPLE_API_KEY_BASE64
)

ACTUAL_XCODE_VERSION="$(current_xcode_version)"
ACTUAL_XCODE_BUILD_VERSION="$(current_xcode_build_version)"
ACTUAL_DEVELOPER_DIR="$(current_developer_dir)"

if [[ -z "$EXPECTED_APP_SDK_VERSION" ]]; then
  EXPECTED_APP_SDK_VERSION="$ACTUAL_XCODE_VERSION"
fi

printf 'Using developer dir: %s\n' "$ACTUAL_DEVELOPER_DIR"
printf 'Using Xcode %s (%s)\n' "$ACTUAL_XCODE_VERSION" "$ACTUAL_XCODE_BUILD_VERSION"
printf 'Expected app SDK version: %s\n' "$EXPECTED_APP_SDK_VERSION"
require_exact_match "Xcode version" "$ACTUAL_XCODE_VERSION" "$XCODE_VERSION"
require_exact_match "Xcode build version" "$ACTUAL_XCODE_BUILD_VERSION" "$XCODE_BUILD_VERSION"

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
  detach_dmg_if_mounted
  security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
  rm -f "$CERT_PATH" "$APPSTORE_CONNECT_KEY_PATH" "$EXPORT_OPTIONS_PLIST" "$PROFILE_METADATA_PLIST" "$ZIP_NOTARIZATION_PATH" "$DMG_RW_PATH"
  rm -rf "$DMG_MOUNT_DIR"
}
trap cleanup EXIT

load_profile_metadata() {
  local profile_path="$1"

  security cms -D -i "$profile_path" > "$PROFILE_METADATA_PLIST"
  PROFILE_UUID="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$PROFILE_METADATA_PLIST")"
  PROFILE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$PROFILE_METADATA_PLIST")"
}

detach_dmg_if_mounted() {
  if [[ -d "$DMG_MOUNT_DIR" ]] && mount | grep -q "on $DMG_MOUNT_DIR "; then
    hdiutil detach "$DMG_MOUNT_DIR" -quiet || hdiutil detach "$DMG_MOUNT_DIR" -force -quiet || true
  fi
}

create_styled_dmg() {
  local app_path="$1"
  local dmg_path="$2"
  local icon_source="$PROJECT_ROOT/clipaste/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png"
  local background_dir="$DMG_STAGING_DIR/.background"
  local background_name="background.png"
  local background_path="$background_dir/$background_name"

  rm -rf "$DMG_STAGING_DIR" "$DMG_MOUNT_DIR" "$DMG_RW_PATH" "$dmg_path"
  mkdir -p "$background_dir" "$DMG_MOUNT_DIR"
  cp -R "$app_path" "$DMG_STAGING_DIR/"
  ln -s /Applications "$DMG_STAGING_DIR/Applications"

  xcrun swift \
    "$PROJECT_ROOT/scripts/generate-dmg-background.swift" \
    "$background_path" \
    "$icon_source" \
    "$APP_NAME"

  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDRW \
    "$DMG_RW_PATH"

  hdiutil attach "$DMG_RW_PATH" \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "$DMG_MOUNT_DIR"

  chflags hidden "$DMG_MOUNT_DIR/.background" || true

  osascript <<EOF
set mountFolder to POSIX file "$DMG_MOUNT_DIR" as alias
tell application "Finder"
  open mountFolder
  set current view of container window of mountFolder to icon view
  set toolbar visible of container window of mountFolder to false
  set statusbar visible of container window of mountFolder to false
  set bounds of container window of mountFolder to {120, 120, 880, 600}
  set theViewOptions to icon view options of container window of mountFolder
  set arrangement of theViewOptions to not arranged
  set icon size of theViewOptions to 108
  set background picture of theViewOptions to file ".background:$background_name" of mountFolder
  set position of item "$APP_NAME.app" of mountFolder to {230, 250}
  set position of item "Applications" of mountFolder to {530, 250}
  update mountFolder without registering applications
  delay 1
  close container window of mountFolder
end tell
EOF

  sync
  hdiutil detach "$DMG_MOUNT_DIR" -quiet
  hdiutil convert "$DMG_RW_PATH" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$dmg_path"
  rm -f "$DMG_RW_PATH"
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
  MARKETING_VERSION="$RELEASE_VERSION"
  CURRENT_PROJECT_VERSION="$RELEASE_BUILD_NUMBER"
  CODE_SIGN_STYLE=Manual
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
  CLIPASTE_RELEASE_PROFILE_SPECIFIER="$PROFILE_NAME"
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID"
  OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH"
)
archive_args+=("${xcode_auth_args[@]}")
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
export_args+=("${xcode_auth_args[@]}")

"${export_args[@]}"

APP_PATH="$(find "$EXPORT_DIR" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "Failed to locate exported .app bundle." >&2
  exit 1
fi

ACTUAL_APP_SDK_VERSION="$(resolve_app_sdk_version "$APP_PATH")"
printf 'Exported app SDK version: %s\n' "$ACTUAL_APP_SDK_VERSION"
require_exact_match "app SDK version" "$ACTUAL_APP_SDK_VERSION" "$EXPECTED_APP_SDK_VERSION"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$ZIP_NOTARIZATION_PATH"

xcrun notarytool submit "$ZIP_NOTARIZATION_PATH" \
  --key "$APPSTORE_CONNECT_KEY_PATH" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --wait

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl -a -vv "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

create_styled_dmg "$APP_PATH" "$DMG_PATH"

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
  ZIP: $ZIP_PATH
  DMG: $DMG_PATH
  SHA256: $SHA256_PATH
  Version: $RELEASE_VERSION ($RELEASE_BUILD_NUMBER)
EOF
