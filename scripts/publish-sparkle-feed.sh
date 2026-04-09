#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="${APP_NAME:-Clipaste}"
RELEASE_TAG="${RELEASE_TAG:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GH_TOKEN="${GH_TOKEN:-}"
SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.1}"
DIST_DIR="${DIST_DIR:-$PROJECT_ROOT/build/release}"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build}"
FEED_BRANCH="${FEED_BRANCH:-update-feed}"
FEED_DIR="${FEED_DIR:-$BUILD_ROOT/update-feed}"
SPARKLE_TOOLS_DIR="${SPARKLE_TOOLS_DIR:-$BUILD_ROOT/sparkle-tools}"
SPARKLE_ARCHIVE_PATH="${SPARKLE_ARCHIVE_PATH:-$BUILD_ROOT/Sparkle-${SPARKLE_VERSION}.tar.xz}"
RELEASE_NOTES_MARKDOWN="${RELEASE_NOTES_MARKDOWN:-}"

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

if [[ -z "$SPARKLE_PRIVATE_KEY" ]]; then
  echo "SPARKLE_PRIVATE_KEY is required." >&2
  exit 1
fi

ZIP_PATH="${ZIP_PATH:-$DIST_DIR/${APP_NAME}-${RELEASE_TAG}.zip}"
if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Unable to locate ZIP update archive at $ZIP_PATH." >&2
  exit 1
fi

ARTIFACT_BASENAME="$(basename "$ZIP_PATH" .zip)"
DOWNLOAD_URL_PREFIX="https://github.com/${GITHUB_REPOSITORY}/releases/download/${RELEASE_TAG}/"
FULL_RELEASE_NOTES_URL="https://github.com/${GITHUB_REPOSITORY}/releases/tag/${RELEASE_TAG}"
APP_LINK="https://github.com/${GITHUB_REPOSITORY}"

cleanup() {
  if [[ -d "$FEED_DIR" ]]; then
    git worktree remove --force "$FEED_DIR" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

log() {
  printf '[publish-sparkle-feed] %s\n' "$*"
}

prepare_feed_checkout() {
  rm -rf "$FEED_DIR"
  git worktree prune >/dev/null 2>&1 || true

  log "Preparing worktree for branch $FEED_BRANCH"

  if git fetch --depth 1 origin "$FEED_BRANCH" >/dev/null 2>&1; then
    git worktree add -B "$FEED_BRANCH" "$FEED_DIR" FETCH_HEAD >/dev/null
  else
    git worktree add --detach "$FEED_DIR" HEAD >/dev/null
    git -C "$FEED_DIR" checkout --orphan "$FEED_BRANCH" >/dev/null
    find "$FEED_DIR" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  fi
}

ensure_sparkle_tools() {
  if [[ -x "$SPARKLE_TOOLS_DIR/bin/generate_appcast" ]]; then
    return
  fi

  log "Downloading Sparkle ${SPARKLE_VERSION} distribution"
  rm -rf "$SPARKLE_TOOLS_DIR"
  mkdir -p "$SPARKLE_TOOLS_DIR"

  gh release download \
    -R sparkle-project/Sparkle \
    --pattern "Sparkle-${SPARKLE_VERSION}.tar.xz" \
    --dir "$BUILD_ROOT" \
    --clobber

  tar -xJf "$SPARKLE_ARCHIVE_PATH" -C "$SPARKLE_TOOLS_DIR" ./bin
  chmod +x "$SPARKLE_TOOLS_DIR/bin/generate_appcast"
}

rewrite_appcast_download_urls() {
  local appcast_path="$FEED_DIR/appcast.xml"

  if [[ ! -f "$appcast_path" ]]; then
    echo "Expected appcast.xml at $appcast_path." >&2
    exit 1
  fi

  shopt -s nullglob
  for archive_path in "$FEED_DIR"/*.zip; do
    local archive_name archive_tag asset_url
    archive_name="$(basename "$archive_path")"
    archive_tag="${archive_name#${APP_NAME}-}"
    archive_tag="${archive_tag%.zip}"
    asset_url="https://github.com/${GITHUB_REPOSITORY}/releases/download/${archive_tag}/${archive_name}"

    ARCHIVE_NAME="$archive_name" ASSET_URL="$asset_url" \
      perl -0pi -e 's{url="[^"]*/\Q$ENV{ARCHIVE_NAME}\E"}{url="$ENV{ASSET_URL}"}g' \
      "$appcast_path"
  done
  shopt -u nullglob
}

log "Publishing Sparkle feed for $RELEASE_TAG"
prepare_feed_checkout
ensure_sparkle_tools

log "Copying release assets into feed worktree"
cp "$ZIP_PATH" "$FEED_DIR/"
printf '%s\n' "${RELEASE_NOTES_MARKDOWN:-$RELEASE_TAG}" > "$FEED_DIR/${ARTIFACT_BASENAME}.md"
touch "$FEED_DIR/.nojekyll"

log "Generating appcast.xml"
printf '%s' "$SPARKLE_PRIVATE_KEY" | \
  "$SPARKLE_TOOLS_DIR/bin/generate_appcast" \
    --ed-key-file - \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    --embed-release-notes \
    --full-release-notes-url "$FULL_RELEASE_NOTES_URL" \
    --link "$APP_LINK" \
    --maximum-deltas 0 \
    --maximum-versions 3 \
    "$FEED_DIR"

log "Rewriting appcast download URLs"
rewrite_appcast_download_urls

rm -rf "$FEED_DIR/old_updates"

log "Committing feed updates"
git -C "$FEED_DIR" config user.name "github-actions[bot]"
git -C "$FEED_DIR" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$FEED_DIR" add -A

if git -C "$FEED_DIR" diff --cached --quiet; then
  echo "Sparkle feed is already up to date."
  exit 0
fi

git -C "$FEED_DIR" commit -m "Update Sparkle feed for $RELEASE_TAG"
log "Pushing branch $FEED_BRANCH"
git -C "$FEED_DIR" push origin "$FEED_BRANCH"
