#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

# 录入时分类在主线程同步执行，超大剪贴板文本不能让耗时随全文长度增长。
xcrun swiftc -O clipaste/Services/ClipboardContentClassifier.swift \
  clipaste/Utils/ColorParser.swift \
  scripts/ClipboardContentClassifierTests.swift -o "$test_dir/classifier"
"$test_dir/classifier"
