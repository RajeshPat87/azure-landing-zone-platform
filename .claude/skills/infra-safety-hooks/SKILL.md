---
name: infra-safety-hooks
description: >
  The 20-hook lifecycle map that stops AI from breaking production infrastructure,
  adapted for Terraform + Azure landing-zone repos. Use when installing, auditing,
  or extending Claude Code guardrails (SessionStart / UserPromptSubmit / PreToolUse /
  PostToolUse / Stop / SessionEnd) for an IaC repo, or when a hook denied/asked and
  you need to understand why. Covers credential handling for rotating lab creds.
metadata:
  type: reference
---

# Infra Safety Hooks — 20 guardrails across the Claude Code lifecycle

A practical lifecycle map for context, blocking, approvals, validation, auditing, and
safe completion on infrastructure-as-code repos. Based on the "20 Claude Code Hooks That
Stop AI From Breaking Production" cheat sheet, re-targeted from Kubernetes/Helm to
**Terraform + Azure**. All hooks live in `.claude/hooks/` and are wired in
`.claude/settings.json`.

## Lifecycle

```
SessionStart → UserPromptSubmit → PreToolUse → PermissionRequest → PostToolUse → Stop → SessionEnd
```

Each hook returns one of: **CONTEXT** (inject info), **AUDIT** (record), **WARN**,
**DENY** (hard block), **ASK** (human confirms), **FORMAT/VALIDATE** (fix + check),
**DIAGNOSE**, or **BLOCK** (stop completion).

## The map (cheat-sheet number → this repo)

### 01 · Context + Configuration — *load trustworthy context before acting*
| # | Cheat sheet | Here | Script |
|---|-------------|------|--------|
| 01 | Cluster Context Snapshot | **Cloud Context Snapshot** — active subscription/tenant, git branch, environments, loaded instruction files, as read-only context | `session-start.sh` |
| 02 | Instruction Load Audit | Records which `CLAUDE.md`/rule files were loaded | `session-start.sh` |
| 03 | Production Intent Detector | Scans the prompt for prod / delete / rollback / IAM / secret / scaling intent and warns | `user-prompt-submit.sh` |
| 04 | Configuration Tamper Guard | **ASK** before editing `.claude/settings.json`, hooks, or the creds script | `pre-tool-use.sh` |

### 02 · Before Tool Use — *stop dangerous commands before they execute*
| # | Cheat sheet | Here | Verdict |
|---|-------------|------|---------|
| 05 | Wrong-Cluster Guard | **Wrong-Subscription Guard** — active `az` subscription must match the target env dir (prod/mgmt protected) | ASK |
| 06 | Destructive K8s Blocker | **Destructive Blocker** — `terraform state rm`, `force-unlock`, `az group/mg delete`, `--purge`, broad `rm -rf` | DENY |
| 07 | Credential Exposure Blocker | Blocks reading/echoing `*.tfstate`, `*.tfvars`, `az` tokens, Key Vault secret values, `ARM_CLIENT_SECRET` | DENY |
| 08 | Protected File Guard | ASK before editing `providers.tf`, `backend.hcl`, `versions.tf`, governance/identity/MG modules, CI/CD workflows | ASK |

### 03 · Release Approval — *require explicit approval before privileged changes*
| # | Cheat sheet | Here | Verdict |
|---|-------------|------|---------|
| 09 | Production kubectl Write Gate | Folded into the apply gate (all state-changing `az` mutations) | ASK |
| 10 | Helm Release Gate | *n/a (no Helm)* — reserved for AKS landing zones | — |
| 11 | Terraform / OpenTofu Apply Gate | **ASK** before `terraform apply` / `destroy` (and flags `-auto-approve`) | ASK |
| 12 | Privileged Approval Bridge | The host permission prompt is the bridge; ASK verdicts route through it | ALLOW/DENY |

### 04 · After-Change Validation — *validate edits immediately*
| # | Cheat sheet | Here | Script |
|---|-------------|------|--------|
| 13 | File Formatter | `terraform fmt` on every edited `.tf`/`.tfvars` | `post-tool-use.sh` |
| 14 | Helm Render + Lint | *n/a* — reserved for AKS landing zones | — |
| 15 | K8s Schema + Policy Check | **TFLint** on the edited file's dir (non-blocking findings) | `post-tool-use.sh` |
| 16 | Infrastructure Validation | `terraform init -backend=false && validate` — **BLOCK** on error | `post-tool-use.sh` |

### 05 · Failure + Completion — *explain failures, prevent incomplete "done"*
| # | Cheat sheet | Here | Script |
|---|-------------|------|--------|
| 17 | Tool Failure Explainer | Validation failures are returned to Claude with the exact error to fix | `post-tool-use.sh` |
| 18 | Parallel Change Aggregator | The session audit log aggregates all guardrail decisions | `lib/common.sh` audit |
| 19 | Definition-of-Done Gate | **BLOCK** Stop while any tracked `.tf` is unformatted | `stop.sh` |
| 20 | Session Audit + Cleanup | Summarizes denies/asks, removes stray `tfplan` files | `session-end.sh` |

## Credential handling (rotating lab creds)

Azure lab credentials rotate ~hourly. `.claude/scripts/azure-lab-creds.sh`:

- Reads the shared creds file (`ALZ_AZURE_CREDS_FILE`, or a default path), supporting
  both `az ad sp create-for-rbac` JSON and `KEY=VALUE` `.env` formats.
- Runs `az login --service-principal` so Terraform's azurerm provider uses Azure CLI
  auth automatically — no `ARM_*` env propagation into Claude's shell needed.
- `SessionStart` warms creds; `PreToolUse` re-checks freshness (>50 min ⇒ re-login)
  before every `terraform`/`az` command, so a mid-session rotation self-heals.

Configure once:
```bash
export ALZ_AZURE_CREDS_FILE=/path/to/lab-creds.json   # or .env
```

## Verdict reference

- **DENY** — hook returns `permissionDecision:deny`; the command never runs.
- **ASK** — `permissionDecision:ask`; the host asks the human to confirm.
- **BLOCK** — hook exits `2`; stderr is returned to Claude to fix and retry.
- **CONTEXT/WARN** — extra text injected via `additionalContext`; non-blocking.

## Extending

- New protected paths → add a `case` in `pre-tool-use.sh` (file-editing section).
- New destructive patterns → add to the Hook 06 `case` (deny) block.
- Add Helm/AKS gates (10, 14) when a `modules/aks-platform` lands.
- Reuse everywhere: this whole `.claude/` tree is the portable template described in
  the repo `README.md` (§8 Claude Code automation & guardrails) — landing zone → IDP → any repo.

## Testing a hook

Feed it a sample event on stdin:
```bash
echo '{"tool_name":"Bash","tool_input":{"command":"terraform destroy"}}' \
  | .claude/hooks/pre-tool-use.sh
```
