#!/usr/bin/env bash
# Capture a TUI frame: text buffer + optional screenshot, diff, and summary.
# Usage:
#   capture_frame.sh <session-name> <output-dir> [--name <frame-name>] [--screenshot] [--ansi]
#                    [--history] [--diff-with <baseline-name>] [--summary]
#
# Outputs:
#   <output-dir>/<frame-name>.txt        Plain text buffer
#   <output-dir>/<frame-name>.ansi       Text with ANSI codes (if --ansi)
#   <output-dir>/<frame-name>.png        Screenshot (if --screenshot)
#   <output-dir>/<frame-name>.diff       Unified diff (if --diff-with)

set -euo pipefail

SESSION="${1:?Session name required}"
OUTPUT_DIR="${2:?Output directory required}"
shift 2

FRAME_NAME="frame_$(date +%s)"
DO_SCREENSHOT=false
DO_ANSI=false
DO_HISTORY=false
DIFF_BASELINE=""
DO_SUMMARY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)       FRAME_NAME="$2"; shift 2 ;;
    --screenshot) DO_SCREENSHOT=true; shift ;;
    --ansi)       DO_ANSI=true; shift ;;
    --history)    DO_HISTORY=true; shift ;;
    --diff-with)  DIFF_BASELINE="$2"; shift 2 ;;
    --summary)    DO_SUMMARY=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$OUTPUT_DIR"

TXT_FILE="${OUTPUT_DIR}/${FRAME_NAME}.txt"
ANSI_FILE="${OUTPUT_DIR}/${FRAME_NAME}.ansi"

CAPTURE_ARGS=(-t "$SESSION" -p)
if $DO_HISTORY; then
  CAPTURE_ARGS+=(-S -)
fi

# Capture plain text
tmux capture-pane "${CAPTURE_ARGS[@]}" > "$TXT_FILE"
echo "Captured text: $TXT_FILE"

# Capture with ANSI escape codes
if $DO_ANSI; then
  tmux capture-pane "${CAPTURE_ARGS[@]}" -e > "$ANSI_FILE"
  echo "Captured ANSI: $ANSI_FILE"
fi

if [[ -n "$DIFF_BASELINE" ]]; then
  BASELINE_FILE="${OUTPUT_DIR}/${DIFF_BASELINE}.txt"
  DIFF_FILE="${OUTPUT_DIR}/${FRAME_NAME}.diff"

  if [[ -f "$BASELINE_FILE" ]]; then
    diff -u --label "$DIFF_BASELINE" --label "$FRAME_NAME" \
      "$BASELINE_FILE" "$TXT_FILE" > "$DIFF_FILE" 2>/dev/null || true

    if [[ -s "$DIFF_FILE" ]]; then
      ADDED="$(grep -c '^+[^+]' "$DIFF_FILE" 2>/dev/null || true)"
      REMOVED="$(grep -c '^-[^-]' "$DIFF_FILE" 2>/dev/null || true)"
      echo "Diff: $DIFF_FILE (+${ADDED:-0}/-${REMOVED:-0} lines vs $DIFF_BASELINE)"
      echo "--- Key changes ---"
      grep '^[+-][^+-]' "$DIFF_FILE" | sed -n '1,15p' || true
      TOTAL_CHANGES=$(( ${ADDED:-0} + ${REMOVED:-0} ))
      if [[ $TOTAL_CHANGES -gt 15 ]]; then
        echo "... ($((TOTAL_CHANGES - 15)) more changes)"
      fi
    else
      echo "Diff: no differences from $DIFF_BASELINE"
      rm -f "$DIFF_FILE"
    fi

    if $DO_ANSI; then
      BASELINE_ANSI="${OUTPUT_DIR}/${DIFF_BASELINE}.ansi"
      ANSI_DIFF_FILE="${OUTPUT_DIR}/${FRAME_NAME}_ansi.diff"
      if [[ -f "$BASELINE_ANSI" ]]; then
        diff -u --label "${DIFF_BASELINE}.ansi" --label "${FRAME_NAME}.ansi" \
          "$BASELINE_ANSI" "$ANSI_FILE" > "$ANSI_DIFF_FILE" 2>/dev/null || true
        if [[ -s "$ANSI_DIFF_FILE" ]]; then
          ANSI_CHANGES="$(grep -c '^[+-][^+-]' "$ANSI_DIFF_FILE" 2>/dev/null || true)"
          echo "ANSI diff: $ANSI_DIFF_FILE (${ANSI_CHANGES:-0} styling changes)"
        else
          echo "ANSI diff: no styling differences"
          rm -f "$ANSI_DIFF_FILE"
        fi
      else
        echo "WARN: ANSI baseline not found: $BASELINE_ANSI" >&2
      fi
    fi
  else
    echo "WARN: Baseline not found: $BASELINE_FILE (skipping diff)" >&2
  fi
fi

if $DO_SUMMARY; then
  echo "--- Summary ---"
  LINE_COUNT="$(wc -l < "$TXT_FILE" | tr -d ' ')"
  NON_EMPTY="$(grep -c '.' "$TXT_FILE" 2>/dev/null || true)"
  echo "Lines: $LINE_COUNT total, ${NON_EMPTY:-0} non-empty"

  FOOTER="$(grep -E '↑|↓|%/' "$TXT_FILE" 2>/dev/null | tail -1 || true)"
  if [[ -n "$FOOTER" ]]; then
    echo "Footer: $FOOTER"
  fi

  SEPARATOR_COUNT="$(grep -c '────' "$TXT_FILE" 2>/dev/null || true)"
  echo "Separators: ${SEPARATOR_COUNT:-0}"
  grep -q 'Working\.\.\.' "$TXT_FILE" 2>/dev/null && echo "State: streaming (spinner visible)" || true
  grep -q 'Operation aborted' "$TXT_FILE" 2>/dev/null && echo "State: aborted" || true
  grep -q '✓' "$TXT_FILE" 2>/dev/null && echo "State: success indicator present" || true
fi

# Screenshot via macOS screencapture
if $DO_SCREENSHOT; then
  OS="$(uname -s)"
  case "$OS" in
    Darwin)
      # Find the Terminal/iTerm2/tmux window and capture it
      # Try to get the tmux client terminal PID's window
      WINDOW_ID=""

      # Method 1: Use osascript to find Terminal.app window
      WINDOW_ID=$(osascript -e '
        tell application "System Events"
          set frontApp to name of first application process whose frontmost is true
        end tell
        if frontApp is "Terminal" then
          tell application "Terminal"
            return id of front window
          end tell
        else if frontApp is "iTerm2" then
          tell application "iTerm2"
            return id of current window
          end tell
        end if
        return ""
      ' 2>/dev/null || echo "")

      if [[ -n "$WINDOW_ID" ]]; then
        screencapture -l "$WINDOW_ID" "${OUTPUT_DIR}/${FRAME_NAME}.png"
      else
        # Fallback: capture the entire screen
        screencapture -x "${OUTPUT_DIR}/${FRAME_NAME}.png"
      fi
      echo "Captured screenshot: ${OUTPUT_DIR}/${FRAME_NAME}.png"
      ;;
    Linux)
      if command -v import &>/dev/null; then
        import -window root "${OUTPUT_DIR}/${FRAME_NAME}.png"
      elif command -v scrot &>/dev/null; then
        scrot "${OUTPUT_DIR}/${FRAME_NAME}.png"
      else
        echo "WARN: No screenshot tool found (install imagemagick or scrot)" >&2
      fi
      ;;
    *)
      echo "WARN: Screenshot not supported on $OS" >&2
      ;;
  esac
fi
