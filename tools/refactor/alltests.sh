#!/bin/bash
# 全テスト（CI と同じ確かめ方）。落ちた物だけ出す
cd "$(cd "$(dirname "$0")/../.." && pwd)"
timeout 300 "${GODOT:-/home/claude/godot/godot}" --headless --path . --import >/dev/null 2>&1
for f in tests/test_*.gd; do n=$(basename $f); out="$(timeout 600 "${GODOT:-/home/claude/godot/godot}" --headless --path . --script res://tests/$n 2>&1)"; code=$?
if [ $code -ne 0 ] || ! grep -q '^失敗: \?0$' <<< "$out" || grep -q '^FAIL' <<< "$out"; then echo "FAIL $n"; grep -E "^FAIL|SCRIPT ERROR|Parse Error|Invalid|Cannot" <<< "$out" | sort | uniq | head -6; fi; done
echo "ALL $(ls tests/test_*.gd | wc -l)"
node --test tests/js/*.test.mjs 2>&1 | grep -E "^# (pass|fail)"
