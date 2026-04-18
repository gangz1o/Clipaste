#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="${APP_NAME:-Clipaste}"
RELEASE_TAG="${RELEASE_TAG:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GH_TOKEN="${GH_TOKEN:-}"
HOMEBREW_TAP_REPOSITORY="${HOMEBREW_TAP_REPOSITORY:-}"
DIST_DIR="${DIST_DIR:-$PROJECT_ROOT/build/release}"
RUNNER_TEMP_DIR="${RUNNER_TEMP:-$PROJECT_ROOT/build/tmp}"
CASK_TOKEN="${CASK_TOKEN:-gangz1o-clipaste}"
MINIMUM_MACOS="${MINIMUM_MACOS:-:sonoma}"
HOMEBREW_TAP_BRANCH="${HOMEBREW_TAP_BRANCH:-main}"

if [[ -z "$RELEASE_TAG" ]]; then
  echo "RELEASE_TAG is required." >&2
  exit 1
fi

if [[ -z "$GITHUB_REPOSITORY" ]]; then
  echo "GITHUB_REPOSITORY is required." >&2
  exit 1
fi

if [[ -z "$GH_TOKEN" ]]; then
  echo "GH_TOKEN is required." >&2
  exit 1
fi

if [[ -z "$HOMEBREW_TAP_REPOSITORY" ]]; then
  echo "HOMEBREW_TAP_REPOSITORY is required." >&2
  exit 1
fi

VERSION="${RELEASE_TAG#v}"
ARTIFACT_BASENAME="${APP_NAME}-${RELEASE_TAG}"
DMG_PATH="${DIST_DIR}/${ARTIFACT_BASENAME}.dmg"
SHA256_PATH="${DIST_DIR}/${ARTIFACT_BASENAME}.dmg.sha256"
CASK_WORK_DIR="${RUNNER_TEMP_DIR}/homebrew-tap"
CASK_RELATIVE_PATH="Casks/g/${CASK_TOKEN}.rb"
CASK_ABSOLUTE_PATH="${CASK_WORK_DIR}/${CASK_RELATIVE_PATH}"
EXISTING_CASK_JSON_PATH="${RUNNER_TEMP_DIR}/existing-cask.json"
EXISTING_CASK_PATH="${RUNNER_TEMP_DIR}/existing-cask.rb"

log() {
  printf '[update-homebrew-tap] %s\n' "$*"
}

ensure_release_artifacts() {
  mkdir -p "$DIST_DIR"

  if [[ -f "$DMG_PATH" ]]; then
    return
  fi

  log "Downloading release assets for ${RELEASE_TAG}"
  gh release download "$RELEASE_TAG" \
    -R "$GITHUB_REPOSITORY" \
    --pattern "${ARTIFACT_BASENAME}.dmg" \
    --pattern "${ARTIFACT_BASENAME}.dmg.sha256" \
    --dir "$DIST_DIR" \
    --clobber
}

extract_sha256() {
  local sha_file="$1"

  if [[ -f "$sha_file" ]]; then
    awk '{ print $1 }' "$sha_file"
    return
  fi

  shasum -a 256 "$DMG_PATH" | awk '{ print $1 }'
}

write_cask_file() {
  local version="$1"
  local sha256="$2"

  mkdir -p "$(dirname "$CASK_ABSOLUTE_PATH")"

  cat > "$CASK_ABSOLUTE_PATH" <<EOF
cask "${CASK_TOKEN}" do
  version "${version}"
  sha256 "${sha256}"

  url "https://github.com/${GITHUB_REPOSITORY}/releases/download/v#{version}/${APP_NAME}-v#{version}.dmg"
  name "${APP_NAME}"
  desc "Native clipboard manager"
  homepage "https://github.com/${GITHUB_REPOSITORY}"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= ${MINIMUM_MACOS}"

  app "${APP_NAME}.app"

  zap trash: [
    "~/Library/Application Support/com.gangz1o.clipaste",
    "~/Library/Caches/com.gangz1o.clipaste",
    "~/Library/Preferences/com.gangz1o.clipaste.plist",
    "~/Library/Saved Application State/com.gangz1o.clipaste.savedState",
  ]
end
EOF
}

fetch_existing_cask() {
  local output_path="$1"

  if ! gh api \
    "repos/${HOMEBREW_TAP_REPOSITORY}/contents/${CASK_RELATIVE_PATH}" \
    -f ref="$HOMEBREW_TAP_BRANCH" > "$EXISTING_CASK_JSON_PATH" 2>/dev/null; then
    EXISTING_CASK_SHA=""
    return 1
  fi

  EXISTING_CASK_SHA="$(
    python3 - <<'PY' "$EXISTING_CASK_JSON_PATH"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    payload = json.load(fh)

print(payload["sha"])
PY
  )"

  python3 - <<'PY' "$EXISTING_CASK_JSON_PATH" "$output_path"
import base64
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    payload = json.load(fh)

with open(sys.argv[2], "wb") as fh:
    fh.write(base64.b64decode(payload["content"]))
PY
}

encode_file_as_base64() {
  local input_path="$1"

  python3 - <<'PY' "$input_path"
import base64
import pathlib
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
print(base64.b64encode(data).decode("ascii"), end="")
PY
}

update_cask_via_api() {
  local content_b64="$1"
  local message="Update ${CASK_TOKEN} to ${VERSION}"

  if [[ -n "${EXISTING_CASK_SHA:-}" ]]; then
    gh api \
      --method PUT \
      "repos/${HOMEBREW_TAP_REPOSITORY}/contents/${CASK_RELATIVE_PATH}" \
      -f message="$message" \
      -f content="$content_b64" \
      -f branch="$HOMEBREW_TAP_BRANCH" \
      -f sha="$EXISTING_CASK_SHA" >/dev/null
    return
  fi

  gh api \
    --method PUT \
    "repos/${HOMEBREW_TAP_REPOSITORY}/contents/${CASK_RELATIVE_PATH}" \
    -f message="$message" \
    -f content="$content_b64" \
    -f branch="$HOMEBREW_TAP_BRANCH" >/dev/null
}

rm -rf "$CASK_WORK_DIR"
mkdir -p "$RUNNER_TEMP_DIR"

ensure_release_artifacts

SHA256="$(extract_sha256 "$SHA256_PATH")"
log "Updating ${CASK_RELATIVE_PATH} to version ${VERSION}"
write_cask_file "$VERSION" "$SHA256"

ruby -c "$CASK_ABSOLUTE_PATH"

if fetch_existing_cask "$EXISTING_CASK_PATH"; then
  if cmp -s "$CASK_ABSOLUTE_PATH" "$EXISTING_CASK_PATH"; then
    log "Homebrew tap is already up to date."
    exit 0
  fi
else
  log "Cask file does not exist yet; creating a new one."
fi

CONTENT_B64="$(encode_file_as_base64 "$CASK_ABSOLUTE_PATH")"
update_cask_via_api "$CONTENT_B64"

log "Updated ${HOMEBREW_TAP_REPOSITORY} to ${VERSION}"
