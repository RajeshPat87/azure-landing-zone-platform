#!/usr/bin/env bash
###############################################################################
# SessionEnd — Hook 20 (Session Audit + Cleanup).
# Summarizes what the guardrails saw this session and removes transient files.
###############################################################################
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
read_event

if [ -f "$AUDIT_LOG" ]; then
  denies="$(grep -c $'\tDENY\t' "$AUDIT_LOG" 2>/dev/null || echo 0)"
  asks="$(grep -c $'\tASK\t' "$AUDIT_LOG" 2>/dev/null || echo 0)"
  audit SessionEnd SUMMARY "denies=$denies asks=$asks reason=$(j '.reason')"
fi

# Cleanup: stray plan files that should never linger on disk.
find "$REPO_ROOT" -maxdepth 3 -name 'tfplan' -o -name '*.tfplan' 2>/dev/null \
  | while read -r f; do rm -f "$f" 2>/dev/null && audit SessionEnd CLEANUP "removed $f"; done

exit 0
