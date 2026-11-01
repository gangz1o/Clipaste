#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc clipaste/Services/PasteKeystrokeSender.swift \
  scripts/PasteKeystrokeSenderTests.swift -o "$test_dir/paste"
"$test_dir/paste"
