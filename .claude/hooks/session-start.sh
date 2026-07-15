#!/usr/bin/env bash
###############################################################################
# SessionStart — Hooks 01 (Context Snapshot) + 02 (Instruction Load Audit).
# Warms Azure lab credentials and hands Claude a read-only environment snapshot.
###############################################################################
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
read_event

# Hook 01: refresh lab creds up front so the first terraform/az call just works.
"$REPO_ROOT/.claude/scripts/azure-lab-creds.sh" auto >/dev/null 2>&1 || true

# Read-only context snapshot: cloud identity, repo, active TF workspace.
sub="$(az account show --query '{name:name,id:id,tenant:tenantId}' -o json 2>/dev/null || echo '{}')"
sub_name="$(printf '%s' "$sub" | jq -r '.name // "NOT LOGGED IN"')"
sub_id="$(printf '%s' "$sub" | jq -r '.id // "-"')"
branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
envs="$(ls -1 "$REPO_ROOT/environments" 2>/dev/null | tr '\n' ' ')"

# Hook 02: record which instruction/rule files were loaded.
loaded="$(ls "$REPO_ROOT"/CLAUDE.md "$REPO_ROOT"/.claude/CLAUDE.md 2>/dev/null | tr '\n' ' ')"
audit SessionStart CONTEXT "sub=$sub_name branch=$branch loaded=$loaded"

ctx="$(cat <<EOF
[ALZ context snapshot — read-only]
Azure subscription : $sub_name ($sub_id)
Git branch         : $branch
Environments       : ${envs:-none}
Instruction files  : ${loaded:-none}

Safety posture for this repo (enforced by hooks, see .claude/skills/infra-safety-hooks):
- terraform apply/destroy and az delete/purge require explicit approval.
- Never print or read Key Vault secrets, tfstate, or *.tfvars values.
- Verify the active subscription matches the target environment before applying.
EOF
)"
add_context SessionStart "$ctx"
exit 0
