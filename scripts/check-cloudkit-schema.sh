#!/bin/bash
# 发布前检查：CloudKit schema 是否已包含当前 SwiftData 模型的全部字段。
# Production 不允许客户端建字段，漏部署会让带新字段的记录全部上传失败。
#
# 需要 CloudKit 管理 token（只需配置一次）：
#   xcrun cktool save-token --type management
# 或设置 CLOUDKIT_MANAGEMENT_TOKEN 环境变量。
#
# 用法：scripts/check-cloudkit-schema.sh [production|development]
set -euo pipefail
cd "$(dirname "$0")/.."

environment="${1:-production}"
container_id="iCloud.com.gangz1o.clipaste"
team_id="${APPLE_TEAM_ID:-$(grep -m1 'DEVELOPMENT_TEAM = ' clipaste.xcodeproj/project.pbxproj | sed 's/.*= //;s/;//')}"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

xcrun cktool export-schema \
  --team-id "$team_id" \
  --container-id "$container_id" \
  --environment "$environment" \
  --output-file "$test_dir/schema.ckdb"

swiftc clipaste/Utilities/ImageProcessor.swift \
  clipaste/Models/ClipboardRecord.swift \
  clipaste/Models/ClipboardGroupModel.swift \
  clipaste/Models/SyncAnchor.swift \
  clipaste/Models/ClipboardSourceMetadata.swift \
  scripts/CloudKitSchemaFieldCheck.swift -o "$test_dir/check"
"$test_dir/check" "$test_dir/schema.ckdb"
