#!/usr/bin/env bash
###############################################################################
# common.sh — shared helpers sourced by every hook.
# No side effects on source: only defines functions + reads config.
###############################################################################

# ----- config (override via environment or .claude/hooks/config.env) ---------
# common.sh lives at <repo>/.claude/hooks/lib/common.sh
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"         # .claude/hooks
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$HOOK_DIR/../.." && pwd)}"    # repo root
STATE_DIR="${ALZ_STATE_DIR:-$HOME/.claude/alz}"  # per-user runtime state
mkdir -p "$STATE_DIR" 2>/dev/null || true

# Optional local config (never committed — see .gitignore)
[ -f "$HOOK_DIR/config.env" ] && . "$HOOK_DIR/config.env"

AUDIT_LOG="${ALZ_AUDIT_LOG:-$STATE_DIR/audit.log}"

# ----- json input helpers ----------------------------------------------------
# Hooks receive a JSON event on stdin. Read it once, expose via HOOK_JSON.
read_event() { HOOK_JSON="$(cat)"; export HOOK_JSON; }

# jq accessor with a default; safe when key missing/null.
j() { printf '%s' "$HOOK_JSON" | jq -r "$1 // empty" 2>/dev/null; }

# ----- audit -----------------------------------------------------------------
audit() {
  # audit <event> <verdict> <detail>
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\t%s\t%s\t%s\n' "$ts" "${1:-?}" "${2:-?}" "${3:-}" >>"$AUDIT_LOG" 2>/dev/null || true
}

# ----- decision emitters (Claude Code hook protocol) -------------------------
# PreToolUse: deny/ask/allow with a reason shown to Claude + user.
pre_decision() { # pre_decision <allow|deny|ask> <reason>
  jq -cn --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
}

# UserPromptSubmit / SessionStart: inject extra context for Claude.
add_context() { # add_context <event> <text>
  jq -cn --arg e "$1" --arg c "$2" \
    '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}'
}

# Block with feedback (exit 2 => stderr is returned to Claude).
block() { echo "$1" >&2; exit 2; }
