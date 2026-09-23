#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

image_sources=(
  clipaste/Utilities/ImageProcessor.swift
  clipaste/Utilities/ClipboardFileReference.swift
  clipaste/Services/ClipboardImageResourcePolicy.swift
)
swiftc "${image_sources[@]}" \
  clipaste/Services/ClipboardPasteboardImageReader.swift \
  clipaste/Managers/ClipboardImageSource.swift \
  scripts/ClipboardPasteboardImageReaderTests.swift \
  -o "$test_dir/capture"
"$test_dir/capture"

swiftc "${image_sources[@]}" scripts/ClipboardImageResourcePolicyTests.swift \
  -o "$test_dir/image-budgets"
"$test_dir/image-budgets"

swiftc clipaste/Utilities/ImageProcessor.swift \
  clipaste/Models/ClipboardRecord.swift \
  clipaste/Managers/ClipboardStorageModels.swift \
  clipaste/Managers/ClipboardStoreActor+Retention.swift \
  scripts/ClipboardRetentionTestSupport.swift scripts/ClipboardRetentionTests.swift \
  -o "$test_dir/retention"
"$test_dir/retention"
