#!/usr/bin/env bash
###############################################################################
# PreToolUse — the guardrail layer. Adapts the cheat-sheet hooks 04-11 to a
# Terraform/Azure landing-zone repo:
#   04 Config Tamper Guard      -> ask before editing hooks/settings/CI
#   05 Wrong-Subscription Guard -> active az sub must match target env
#   06 Destructive Blocker      -> deny state rm, force destroy, group/purge delete
#   07 Credential Exposure Block -> deny reads/echoes of tfstate, tfvars, secrets
#   08 Protected File Guard     -> ask before editing providers/backend/policy/identity
#   09/11 Apply Gate            -> ask before terraform apply/destroy, az delete
# Also: refresh hourly-rotated lab creds before any terraform/az command.
#
# Verdicts: deny (hard stop), ask (human confirms), allow (fall through, exit 0).
###############################################################################
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
read_event

TOOL="$(j '.tool_name')"
CMD="$(j '.tool_input.command')"
FILE="$(j '.tool_input.file_path')"

deny() { audit PreToolUse DENY "$2"; pre_decision deny "$1"; exit 0; }
ask()  { audit PreToolUse ASK  "$2"; pre_decision ask  "$1"; exit 0; }

# ---------------------------------------------------------------------------
# File-editing tools (Edit / Write / MultiEdit) — hooks 04 + 08.
# ---------------------------------------------------------------------------
if [ -n "$FILE" ]; then
  rel="${FILE#$REPO_ROOT/}"
  case "$rel" in
    .claude/settings.json|.claude/hooks/*|.claude/scripts/azure-lab-creds.sh)
      ask "Config Tamper Guard: '$rel' controls Claude's own guardrails. Confirm this change is intended." "tamper:$rel" ;;
    */providers.tf|*/backend.hcl|*/versions.tf)
      ask "Protected File Guard: '$rel' defines the backend/provider/auth. A mistake here can point state or auth at the wrong place. Confirm." "protected:$rel" ;;
    modules/governance/*|modules/identity/*|modules/management-groups/*)
      ask "Protected File Guard: '$rel' is governance/identity/MG code — tenant-wide blast radius. Confirm." "protected:$rel" ;;
    .github/workflows/*|pipelines/*)
      ask "Protected File Guard: '$rel' is CI/CD that runs with cloud credentials. Confirm this pipeline change." "protected:$rel" ;;
  esac
  exit 0
fi

# ---------------------------------------------------------------------------
# Bash tool — the rest applies to shell commands only.
# ---------------------------------------------------------------------------
[ "$TOOL" = "Bash" ] || exit 0
[ -z "$CMD" ] && exit 0
lc="$(printf '%s' "$CMD" | tr '[:upper:]' '[:lower:]')"

# --- Hook 07: Credential Exposure Blocker (check first — highest severity) ----
case "$lc" in
  *keyvault*secret*show*|*keyvault*secret*download*|*az\ keyvault\ secret*)
    deny "Credential Exposure Blocker: reading Key Vault secret values is not allowed from here. Reference secrets by URI in Terraform instead." "cred:keyvault" ;;
  *arm_client_secret*|*client_secret*|*sp_password*)
    case "$lc" in *echo*|*printenv*|*cat*|*print*|*env*|*set\ \|*)
      deny "Credential Exposure Blocker: refusing to print service-principal secrets." "cred:secret-echo" ;;
    esac ;;
esac
case "$lc" in
  *.tfstate*|*terraform.tfvars|*.tfvars*|*azure.env*|*.azure/*)
    case "$lc" in *cat\ *|*less\ *|*head\ *|*tail\ *|*nano\ *|*vi\ *|*vim\ *|*strings\ *|*xxd\ *)
      deny "Credential Exposure Blocker: tfstate/tfvars/az token files can contain secrets — don't dump them. Use 'terraform output' or 'terraform state list' for structure." "cred:state-dump" ;;
    esac ;;
esac

# --- Hook 06: Destructive Blocker ---------------------------------------------
case "$lc" in
  *rm\ -rf\ /*|*rm\ -rf\ ~*|*rm\ -rf\ \$home*|*rm\ -rf\ .*)
    deny "Destructive Blocker: broad 'rm -rf' refused. Delete specific paths only." "destructive:rmrf" ;;
  *terraform\ state\ rm*|*terraform\ force-unlock*|*tofu\ state\ rm*)
    deny "Destructive Blocker: mutating Terraform state directly (state rm/force-unlock) is refused — this desyncs state from cloud. Fix via config + plan." "destructive:state" ;;
  *az\ group\ delete*|*az\ account\ management-group\ delete*)
    deny "Destructive Blocker: deleting a resource group / management group by CLI bypasses Terraform and policy. Remove the resource from config and apply instead." "destructive:az-delete" ;;
  *--purge*|*keyvault\ purge*|*purge-protection*false*)
    deny "Destructive Blocker: purge / disabling purge-protection is refused (irreversible)." "destructive:purge" ;;
esac

# --- Hourly-lab credential freshness before any terraform/az ------------------
case "$lc" in
  terraform\ *|tofu\ *|az\ *)
    if ! "$REPO_ROOT/.claude/scripts/azure-lab-creds.sh" --check >/dev/null 2>&1; then
      "$REPO_ROOT/.claude/scripts/azure-lab-creds.sh" auto >/dev/null 2>&1 || true
      audit PreToolUse REFRESH "lab creds refreshed before: ${CMD:0:60}"
    fi ;;
esac

# --- Hook 05: Wrong-Subscription Guard ----------------------------------------
# When running terraform inside an environments/<env> dir, the active az sub must
# look consistent with that env. Prod is the one we most want to protect.
case "$lc" in
  terraform\ apply*|terraform\ destroy*|terraform\ plan*|tofu\ apply*|tofu\ destroy*)
    active_sub="$(az account show --query name -o tsv 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    pwd_lc="$(printf '%s' "$PWD" | tr '[:upper:]' '[:lower:]')"
    case "$pwd_lc" in
      *landingzone-prod*|*environments/mgmt*)
        case "$active_sub" in
          *dev*|*sandbox*|*lab*|*test*)
            ask "Wrong-Subscription Guard: you're in a PROD/mgmt environment dir but the active Azure subscription is '$active_sub'. Confirm this is the intended target before continuing." "wrongsub:$active_sub" ;;
        esac ;;
    esac ;;
esac

# --- Hook 09/11: Terraform / Azure Apply Gate (release approval) --------------
case "$lc" in
  terraform\ destroy*|tofu\ destroy*)
    ask "Apply Gate (DESTROY): this tears down infrastructure. Confirm a reviewed plan and the correct target env/subscription before proceeding." "gate:destroy" ;;
  terraform\ apply*|tofu\ apply*)
    case "$lc" in
      *-auto-approve*)
        ask "Apply Gate: 'terraform apply -auto-approve' skips the interactive confirm. In this repo, applies must be reviewed. Confirm you want an unattended apply." "gate:apply-auto" ;;
      *)
        ask "Apply Gate: 'terraform apply' will change cloud infrastructure. Confirm the plan was reviewed and the target env/subscription is correct." "gate:apply" ;;
    esac ;;
  *az\ *\ delete*|*az\ *\ purge*|*az\ role\ assignment\ create*|*az\ role\ assignment\ delete*)
    ask "Apply Gate: this az command mutates live resources/IAM outside Terraform. Prefer changing Terraform config; if intentional, confirm." "gate:az-mutate" ;;
esac

exit 0
