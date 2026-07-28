#!/bin/zsh

set -eu

header_file="clipaste/Views/ClipboardHeaderView.swift"
horizontal_file="clipaste/Views/ClipboardHorizontalView.swift"
failed=0

if rg -U -n 'private func select(AllGroup|CustomGroup|SmartFilter|BuiltInGroup)[^\{]*\{\n[[:space:]]*withAnimation' "$header_file"; then
    echo "FAIL: group scope changes must not inherit a broad animation transaction"
    failed=1
fi

if rg -U -n 'private func scrollToItem[^\{]*\{\n[[:space:]]*DispatchQueue\.main\.async' "$horizontal_file"; then
    echo "FAIL: listScrollRequest must not be deferred to a later main-loop turn"
    failed=1
fi

exit "$failed"
