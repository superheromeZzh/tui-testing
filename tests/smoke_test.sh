#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT_DIR/scripts"
SESSION="tui-test-smoke-$$"
OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tui-testing-smoke.XXXXXX")"

cleanup() {
  "$SCRIPTS/tui_session.sh" stop "$SESSION" >/dev/null 2>&1 || true
  rm -rf "$OUTPUT_DIR"
}
trap cleanup EXIT

"$SCRIPTS/tui_session.sh" start "$SESSION" \
  "env PS1='TUI_TEST> ' bash --noprofile --norc" \
  --wait-for "TUI_TEST>" --timeout 10 --width 80 --height 24

"$SCRIPTS/capture_frame.sh" "$SESSION" "$OUTPUT_DIR" \
  --name baseline --ansi --history

"$SCRIPTS/send_and_wait.sh" "$SESSION" "printf 'READY\\n'" \
  --output-dir "$OUTPUT_DIR" --name typed --timeout 5
"$SCRIPTS/send_and_wait.sh" "$SESSION" Enter \
  --output-dir "$OUTPUT_DIR" --name response --ansi --history --timeout 5 \
  --diff-with baseline --summary | tee "$OUTPUT_DIR/capture.log"
grep -q "READY" "$OUTPUT_DIR/response.txt"
test -s "$OUTPUT_DIR/response.ansi"
test -s "$OUTPUT_DIR/response.diff"
grep -q '^--- Summary ---$' "$OUTPUT_DIR/capture.log"

"$SCRIPTS/send_and_wait.sh" "$SESSION" "" \
  --output-dir "$OUTPUT_DIR" --name snapshot --history --timeout 5
grep -q "READY" "$OUTPUT_DIR/snapshot.txt"

"$SCRIPTS/tui_session.sh" cleanup "$OUTPUT_DIR" --session-prefix "$SESSION"
test ! -e "$OUTPUT_DIR"
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "ERROR: cleanup did not stop $SESSION" >&2
  exit 1
fi

echo "Smoke test passed"
