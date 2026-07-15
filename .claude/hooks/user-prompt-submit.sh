#!/usr/bin/env bash
###############################################################################
# UserPromptSubmit — Hook 03 (Production Intent Detector).
# Flags production / deletion / IAM / secret intent so Claude proceeds carefully.
# Warns (adds context) but never blocks the prompt itself — blocking happens at
# the tool boundary (PreToolUse), not on what the user is allowed to ask.
###############################################################################
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
read_event

prompt="$(j '.prompt' | tr '[:upper:]' '[:lower:]')"
hits=""
case "$prompt" in
  *prod*|*production*|*landingzone-prod*) hits="$hits production" ;;
esac
case "$prompt" in *destroy*|*delete*|*purge*|*rm\ -rf*|*teardown*) hits="$hits destructive" ;; esac
case "$prompt" in *rollback*|*revert*|*state\ rm*|*taint*) hits="$hits rollback" ;; esac
case "$prompt" in *rbac*|*role\ assignment*|*owner*|*service\ principal*|*iam*) hits="$hits iam" ;; esac
case "$prompt" in *secret*|*key\ vault*|*keyvault*|*password*|*credential*) hits="$hits secret" ;; esac
case "$prompt" in *scale*|*sku*|*firewall\ rule*|*policy\ assignment*) hits="$hits blast-radius" ;; esac

[ -z "$hits" ] && exit 0

audit UserPromptSubmit WARN "intent:${hits# }"
add_context UserPromptSubmit "[Production intent detected:${hits} ]
Treat this as a high-impact change. Before any apply/delete: confirm the target
environment + subscription, produce a plan/diff, and get explicit approval. Do
not read or echo secret values while working on this."
exit 0
