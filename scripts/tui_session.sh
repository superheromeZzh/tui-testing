#!/usr/bin/env bash
# Manage a tmux-based TUI testing session.
# Usage:
#   tui_session.sh start <session-name> <command> [--wait-for <pattern>] [--timeout <seconds>]
#   tui_session.sh stop <session-name>
#   tui_session.sh status <session-name>
#   tui_session.sh cleanup [<output-dir>] [--session-prefix <prefix>]
#
# Examples:
#   tui_session.sh start pi-test "java -jar pi-agent.jar -m mock --mode interactive" --wait-for ">"
#   tui_session.sh stop pi-test
#   tui_session.sh cleanup /tmp/tui-frames --session-prefix tui-test-

set -euo pipefail

ACTION="${1:?Usage: tui_session.sh <start|stop|status|cleanup> ...}"
shift

resolve_cleanup_dir() {
  local requested="$1"
  local temp_root
  local system_temp_root
  local resolved

  temp_root="${TMPDIR:-/tmp}"
  temp_root="$(cd "$temp_root" && pwd -P)"
  system_temp_root="$(cd /tmp && pwd -P)"

  if [[ -d "$requested" ]]; then
    resolved="$(cd "$requested" && pwd -P)"
  else
    local parent
    local base
    parent="$(dirname "$requested")"
    base="$(basename "$requested")"
    resolved="$(cd "$parent" && pwd -P)/$base"
  fi

  case "$resolved" in
    "$temp_root"/tui-*|"$system_temp_root"/tui-*) printf '%s\n' "$resolved" ;;
    *)
      echo "ERROR: cleanup directory must be a tui-* directory under the system temp directory: $requested" >&2
      return 1
      ;;
  esac
}

cleanup_frames() {
  local requested="$1"
  local resolved
  resolved="$(resolve_cleanup_dir "$requested")"

  if [[ -d "$resolved" ]]; then
    local file_count
    file_count="$(find "$resolved" -type f 2>/dev/null | wc -l | tr -d ' ')"
    rm -rf -- "$resolved"
    echo "Removed $resolved ($file_count files)"
  else
    echo "No frames directory: $resolved"
  fi
}

case "$ACTION" in
  cleanup)
    OUTPUT_DIR="/tmp/tui-frames"
    SESSION_PREFIX="tui-test-"

    if [[ $# -gt 0 && "$1" != --* ]]; then
      OUTPUT_DIR="$1"
      shift
    fi
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --session-prefix) SESSION_PREFIX="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done
    if [[ -z "$SESSION_PREFIX" ]]; then
      echo "ERROR: session prefix must not be empty" >&2
      exit 1
    fi

    while IFS= read -r candidate; do
      if [[ -n "$candidate" && "$candidate" == "$SESSION_PREFIX"* ]]; then
        tmux kill-session -t "$candidate"
        echo "Stopped session: $candidate"
      fi
    done <<EOF
$(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)
EOF

    cleanup_frames "$OUTPUT_DIR"
    echo "Cleanup complete"
    ;;

  start)
    SESSION="${1:?Session name required}"
    shift
    COMMAND="${1:?Command required}"
    shift
    WAIT_FOR=""
    TIMEOUT=30
    TERM_WIDTH=120
    TERM_HEIGHT=40

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --wait-for) WAIT_FOR="$2"; shift 2 ;;
        --timeout)  TIMEOUT="$2"; shift 2 ;;
        --width)    TERM_WIDTH="$2"; shift 2 ;;
        --height)   TERM_HEIGHT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    # Kill existing session if any
    tmux kill-session -t "$SESSION" 2>/dev/null || true

    # Create session with specified dimensions
    tmux new-session -d -s "$SESSION" -x "$TERM_WIDTH" -y "$TERM_HEIGHT" "$COMMAND"

    echo "Session '$SESSION' started (${TERM_WIDTH}x${TERM_HEIGHT})"

    if [[ -n "$WAIT_FOR" ]]; then
      echo "Waiting for pattern: $WAIT_FOR (timeout: ${TIMEOUT}s)"
      START_TIME=$SECONDS
      while (( SECONDS - START_TIME < TIMEOUT )); do
        ELAPSED=$((SECONDS - START_TIME))
        CONTENT=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null || echo "")
        if echo "$CONTENT" | grep -q "$WAIT_FOR"; then
          echo "Ready! Pattern found after ${ELAPSED}s"
          exit 0
        fi
        sleep 0.5
      done
      echo "ERROR: Timeout after ${TIMEOUT}s waiting for '$WAIT_FOR'" >&2
      tmux capture-pane -t "$SESSION" -p >&2
      exit 1
    fi
    ;;

  stop)
    SESSION="${1:?Session name required}"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      tmux kill-session -t "$SESSION"
      echo "Session '$SESSION' stopped"
    else
      echo "Session '$SESSION' not found"
    fi
    ;;

  status)
    SESSION="${1:?Session name required}"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "Session '$SESSION' is running"
      echo "---"
      tmux capture-pane -t "$SESSION" -p
    else
      echo "Session '$SESSION' is not running"
      exit 1
    fi
    ;;

  *)
    echo "Unknown action: $ACTION" >&2
    echo "Usage: tui_session.sh <start|stop|status|cleanup> ..." >&2
    exit 1
    ;;
esac
