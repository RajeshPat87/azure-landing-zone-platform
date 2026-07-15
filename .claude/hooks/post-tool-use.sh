#!/usr/bin/env bash
###############################################################################
# PostToolUse — Hooks 13 (File Formatter) + 15/16 (Infra Validation) + 17
# (Tool Failure Explainer). Runs right after an edit so Claude gets immediate,
# actionable feedback instead of discovering breakage at apply time.
###############################################################################
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
read_event

TOOL="$(j '.tool_name')"
FILE="$(j '.tool_input.file_path')"

# Only react to edits of Terraform files.
case "$FILE" in
  *.tf|*.tfvars)
    dir="$(dirname "$FILE")"

    # Hook 13: format the edited file with the approved formatter.
    terraform fmt "$FILE" >/dev/null 2>&1 || true

    # Hook 16: validate the composition (no backend/network needed).
    out="$(cd "$dir" && terraform init -backend=false -input=false >/dev/null 2>&1 \
            && terraform validate -no-color 2>&1)"
    if [ $? -ne 0 ] && printf '%s' "$out" | grep -qi error; then
      audit PostToolUse VALIDATE "invalid: $FILE"
      block "Infrastructure Validation failed for $FILE:
$out
Fix the Terraform above before continuing."
    fi

    # Hook 15: lint (best-effort; skip silently if tflint absent).
    if command -v tflint >/dev/null 2>&1; then
      lint="$(cd "$dir" && tflint --no-color 2>&1)"
      if [ -n "$lint" ]; then
        audit PostToolUse LINT "warnings: $FILE"
        echo "TFLint findings for $FILE:
$lint" >&2   # informational, exit 0 (non-blocking)
      fi
    fi
    audit PostToolUse VALIDATE "ok: $FILE"
    ;;
esac
exit 0
