#!/usr/bin/env bash
###############################################################################
# Stop — Hook 19 (Definition-of-Done Gate).
# Blocks "I'm done" when Terraform under the repo is left unformatted, since
# unformatted/invalid config is the cheapest possible thing to have verified.
# Uses a stamp file to avoid re-blocking in a loop after Claude fixes it.
###############################################################################
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
read_event

# Avoid infinite loop: if this hook already blocked once this turn, let it stop.
if [ "$(j '.stop_hook_active')" = "true" ]; then exit 0; fi

unformatted="$(cd "$REPO_ROOT" && terraform fmt -check -recursive 2>/dev/null)"
if [ -n "$unformatted" ]; then
  audit Stop BLOCK "unformatted: $(printf '%s' "$unformatted" | tr '\n' ' ')"
  block "Definition-of-Done Gate: these Terraform files are not formatted:
$unformatted
Run 'terraform fmt -recursive' (or fix them) before finishing."
fi

audit Stop DONE "fmt clean"
exit 0
