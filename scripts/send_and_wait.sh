#!/usr/bin/env bash
# Send keys to a tmux session, wait for output to stabilize, then capture.
# Usage:
#   send_and_wait.sh <session-name> <keys> [--output-dir <dir>] [--name <frame-name>]
#                    [--screenshot] [--ansi] [--history] [--timeout <seconds>]
#                    [--delay <seconds>] [--stable-count <n>]
#                    [--diff-with <baseline-name>] [--summary]
#
# <keys> uses tmux send-keys syntax: literal text, or special keys like Enter, C-c, Down, etc.
#
# Examples:
#   send_and_wait.sh pi-test "hello world" --output-dir /tmp/frames --name after_input
#   send_and_wait.sh pi-test Enter --output-dir /tmp/frames --name after_submit --screenshot
#   send_and_wait.sh pi-test C-c --output-dir /tmp/frames --name after_cancel

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SESSION="${1:?Session name required}"
if [[ $# -lt 2 ]]; then
  echo "Keys argument required; pass an empty string to capture without sending keys" >&2
  exit 1
fi
KEYS="$2"
shift 2

OUTPUT_DIR="/tmp/tui-test-frames"
FRAME_NAME="frame_$(date +%s)"
DO_SCREENSHOT=false
DO_ANSI=false
DO_HISTORY=false
TIMEOUT=30
DELAY=0.2
STABLE_COUNT=3
DIFF_BASELINE=""
DO_SUMMARY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
    --name)        FRAME_NAME="$2"; shift 2 ;;
    --screenshot)  DO_SCREENSHOT=true; shift ;;
    --ansi)        DO_ANSI=true; shift ;;
    --history)     DO_HISTORY=true; shift ;;
    --timeout)     TIMEOUT="$2"; shift 2 ;;
    --delay)       DELAY="$2"; shift 2 ;;
    --stable-count) STABLE_COUNT="$2"; shift 2 ;;
    --diff-with)   DIFF_BASELINE="$2"; shift 2 ;;
    --summary)     DO_SUMMARY=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Send keys
# Use -l (literal) for multi-character text to preserve spaces.
# Single special keys (Enter, C-c, Up, etc.) are sent without -l.
if [[ -z "$KEYS" ]]; then
  :
elif [[ ${#KEYS} -gt 1 && "$KEYS" != C-* && "$KEYS" != M-* && "$KEYS" != DC \
   && "$KEYS" != BSpace && "$KEYS" != Enter && "$KEYS" != Escape \
   && "$KEYS" != Tab && "$KEYS" != Up && "$KEYS" != Down \
   && "$KEYS" != Left && "$KEYS" != Right \
   && "$KEYS" != PageUp && "$KEYS" != PageDown \
   && "$KEYS" != Home && "$KEYS" != End ]]; then
  tmux send-keys -t "$SESSION" -l "$KEYS"
else
  tmux send-keys -t "$SESSION" "$KEYS"
fi

# Brief delay to let the TUI start processing
sleep "$DELAY"

# Wait for stable output
"$SCRIPT_DIR/wait_stable.sh" "$SESSION" --timeout "$TIMEOUT" \
  --stable-count "$STABLE_COUNT" > /dev/null

# Capture frame
CAPTURE_ARGS=("$SESSION" "$OUTPUT_DIR" --name "$FRAME_NAME")
if $DO_SCREENSHOT; then CAPTURE_ARGS+=(--screenshot); fi
if $DO_ANSI; then CAPTURE_ARGS+=(--ansi); fi
if $DO_HISTORY; then CAPTURE_ARGS+=(--history); fi
if [[ -n "$DIFF_BASELINE" ]]; then CAPTURE_ARGS+=(--diff-with "$DIFF_BASELINE"); fi
if $DO_SUMMARY; then CAPTURE_ARGS+=(--summary); fi

"$SCRIPT_DIR/capture_frame.sh" "${CAPTURE_ARGS[@]}"
