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
TAP_CLONE_DIR="${RUNNER_TEMP_DIR}/homebrew-tap"
CASK_RELATIVE_PATH="Casks/g/${CASK_TOKEN}.rb"
CASK_ABSOLUTE_PATH="${TAP_CLONE_DIR}/${CASK_RELATIVE_PATH}"

log() {
  printf '[update-homebrew-tap] %s\n' "$*"
}

configure_authenticated_push_remote() {
  git -C "$TAP_CLONE_DIR" remote set-url --push origin \
    "https://x-access-token:${GH_TOKEN}@github.com/${HOMEBREW_TAP_REPOSITORY}.git"
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

rm -rf "$TAP_CLONE_DIR"
mkdir -p "$RUNNER_TEMP_DIR"

ensure_release_artifacts

log "Cloning ${HOMEBREW_TAP_REPOSITORY}"
gh repo clone "$HOMEBREW_TAP_REPOSITORY" "$TAP_CLONE_DIR"
configure_authenticated_push_remote

SHA256="$(extract_sha256 "$SHA256_PATH")"
log "Updating ${CASK_RELATIVE_PATH} to version ${VERSION}"
write_cask_file "$VERSION" "$SHA256"

ruby -c "$CASK_ABSOLUTE_PATH"

git -C "$TAP_CLONE_DIR" config user.name "github-actions[bot]"
git -C "$TAP_CLONE_DIR" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$TAP_CLONE_DIR" add "$CASK_RELATIVE_PATH"

if git -C "$TAP_CLONE_DIR" diff --cached --quiet; then
  log "Homebrew tap is already up to date."
  exit 0
fi

git -C "$TAP_CLONE_DIR" commit -m "Update ${CASK_TOKEN} to ${VERSION}"
git -C "$TAP_CLONE_DIR" push origin main

log "Updated ${HOMEBREW_TAP_REPOSITORY} to ${VERSION}"
