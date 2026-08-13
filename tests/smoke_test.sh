#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT_DIR/scripts"
SESSION="tui-testing-smoke-$$"
OUTPUT_DIR="$(mktemp -d)"

cleanup() {
  "$SCRIPTS/tui_session.sh" stop "$SESSION" >/dev/null 2>&1 || true
  rm -rf "$OUTPUT_DIR"
}
trap cleanup EXIT

"$SCRIPTS/tui_session.sh" start "$SESSION" \
  "env PS1='TUI_TEST> ' bash --noprofile --norc" \
  --wait-for "TUI_TEST>" --timeout 10 --width 80 --height 24

"$SCRIPTS/send_and_wait.sh" "$SESSION" "printf 'READY\\n'" \
  --output-dir "$OUTPUT_DIR" --name typed --timeout 5
"$SCRIPTS/send_and_wait.sh" "$SESSION" Enter \
  --output-dir "$OUTPUT_DIR" --name response --ansi --timeout 5
grep -q "READY" "$OUTPUT_DIR/response.txt"
test -s "$OUTPUT_DIR/response.ansi"

"$SCRIPTS/send_and_wait.sh" "$SESSION" "" \
  --output-dir "$OUTPUT_DIR" --name snapshot --history --timeout 5
grep -q "READY" "$OUTPUT_DIR/snapshot.txt"

echo "Smoke test passed"
