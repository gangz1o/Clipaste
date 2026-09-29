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

swiftc clipaste/Models/ClipboardSourceMetadata.swift \
  clipaste/Models/ClipboardGroupModel.swift \
  clipaste/Managers/ClipboardStoreActor+GroupMaintenance.swift \
  scripts/ClipboardGroupRepairTestSupport.swift scripts/ClipboardGroupRepairTests.swift \
  -o "$test_dir/group-repair"
"$test_dir/group-repair"

swiftc clipaste/Utilities/ImageProcessor.swift \
  clipaste/Models/ClipboardRecord.swift \
  clipaste/Managers/ClipboardStoreActor+ContentMaintenance.swift \
  clipaste/Managers/ClipboardStoreActor+Batching.swift \
  scripts/ClipboardContentMaintenanceTestSupport.swift scripts/ClipboardContentMaintenanceTests.swift \
  -o "$test_dir/content-maintenance"
"$test_dir/content-maintenance"

swiftc clipaste/Utilities/ImageProcessor.swift \
  clipaste/Models/ClipboardRecord.swift \
  clipaste/Models/ClipboardGroupModel.swift \
  clipaste/Models/ClipboardSourceMetadata.swift \
  clipaste/Models/SyncAnchor.swift \
  clipaste/Managers/ClipboardStorageModels.swift \
  clipaste/Managers/ClipboardStoreTransferModels.swift \
  clipaste/Managers/ClipboardTextSyncPolicy.swift \
  clipaste/Managers/ClipboardStoreActor+Transfer.swift \
  clipaste/Managers/ClipboardStoreActor+Helpers.swift \
  clipaste/Managers/ClipboardStoreActor+Batching.swift \
  clipaste/Managers/ClipboardStoreActor+DuplicateMaintenance.swift \
  clipaste/Managers/ClipboardStoreActor+GroupMaintenance.swift \
  clipaste/Managers/ClipboardRecordExportCursor.swift \
  scripts/ClipboardRecordTransferTestSupport.swift scripts/ClipboardRecordTransferTests.swift \
  -o "$test_dir/record-transfer"
"$test_dir/record-transfer"

swiftc clipaste/Managers/ClipboardSnapshotSignature.swift \
  scripts/ClipboardSnapshotSignatureTests.swift \
  -parse-as-library -o "$test_dir/snapshot-signature"
"$test_dir/snapshot-signature"
