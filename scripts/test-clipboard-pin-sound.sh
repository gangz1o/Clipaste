#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc clipaste/Utilities/ImageProcessor.swift \
  clipaste/Models/ClipboardRecord.swift \
  clipaste/Models/ClipboardItem+TopPin.swift \
  clipaste/Managers/ClipboardStorageModels.swift \
  clipaste/Managers/ClipboardStoreNotifications.swift \
  clipaste/Managers/ClipboardStoreActor+TopPin.swift \
  clipaste/Managers/ClipboardSearcher.swift \
  scripts/ClipboardTopPinTests.swift -o "$test_dir/pins"
swiftc clipaste/Utilities/ImageProcessor.swift \
  clipaste/Models/ClipboardRecord.swift \
  clipaste/Managers/ClipboardStorageModels.swift \
  clipaste/Managers/ClipboardStoreNotifications.swift \
  clipaste/Managers/ClipboardSearcher.swift \
  scripts/ClipboardScopedFetchTests.swift -o "$test_dir/scoped"
"$test_dir/scoped"
"$test_dir/pins"
swiftc clipaste/Services/ClipboardSoundFeedback.swift \
  scripts/ClipboardSoundFeedbackTests.swift -o "$test_dir/sound"
"$test_dir/sound"
