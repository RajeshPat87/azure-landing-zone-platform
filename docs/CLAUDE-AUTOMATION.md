# Claude Automation Strategy (org-wide)

How we run Claude Code safely across **every kind of repo**. One portable `.claude/`
template, a shared baseline of guardrails, and thin per-repo-type overrides. This repo
(Azure Landing Zone) is the reference implementation; the IDP repo is the second adopter.

## Principles

1. **Guardrails as code, in the repo.** Every repo carries its own `.claude/` so the
   rules travel with the code and are reviewed like code — no reliance on individual
   local settings.
2. **Deny the irreversible, ask for the privileged, validate every edit.** The 20-hook
   lifecycle (`.claude/skills/infra-safety-hooks/SKILL.md`) is the spine.
3. **Auth is injected, never stored.** CI uses OIDC; local dev uses short-lived creds
   pulled from a rotating source. Claude never sees a long-lived secret.
4. **Same shape everywhere.** The lifecycle hooks and file layout are identical across
   repo types; only the *matchers and validators* differ.

## The portable template

```
.claude/
├── settings.json                 # wires the 6 lifecycle hooks
├── hooks/
│   ├── lib/common.sh             # shared: json parsing, audit, decision emitters
│   ├── session-start.sh          # 01 context snapshot + 02 instruction audit + creds warm-up
│   ├── user-prompt-submit.sh     # 03 production-intent detector
│   ├── pre-tool-use.sh           # 04 tamper · 05 wrong-target · 06 destructive · 07 creds · 08 protected · 09/11 apply gate
│   ├── post-tool-use.sh          # 13 format · 15 lint · 16 validate · 17 failure explainer
│   ├── stop.sh                   # 19 definition-of-done gate
│   ├── session-end.sh            # 20 audit + cleanup
│   └── config.env.example        # per-repo tunables (copy to config.env, gitignored)
├── scripts/
│   └── <cloud>-creds.sh          # rotating-credential refresh (this repo: azure-lab-creds.sh)
└── skills/
    └── infra-safety-hooks/SKILL.md
```

Adopting = copy `.claude/`, then swap the per-type layer below.

## Per-repo-type profiles

Everything in **Baseline** ships unchanged. Each profile overrides only the marked hooks.

### Baseline (all repos)
- 01/02 context snapshot + instruction audit · 03 intent detector · 04 config-tamper guard
- 06 destructive blocker (`rm -rf /`, force-push to protected branches, secret deletion)
- 07 credential-exposure blocker (`.env`, `*.pem`, `id_rsa`, cloud tokens, secret managers)
- 08 protected-file guard (CI workflows, `.claude/`, lockfiles for privileged deps)
- 13 formatter · 17 failure explainer · 19 done-gate · 20 audit+cleanup

### Profile A — IaC / Landing Zone (this repo)  ·  Terraform + Azure
| Hook | Override |
|------|----------|
| 05 | **Wrong-Subscription Guard** — active `az` sub must match target `environments/<env>` |
| 06 | `terraform state rm`/`force-unlock`, `az group/mg delete`, `--purge` → DENY |
| 07 | `*.tfstate`, `*.tfvars`, `az keyvault secret show`, `ARM_CLIENT_SECRET` → DENY |
| 08 | `providers.tf`, `backend.hcl`, governance/identity/MG modules, workflows → ASK |
| 11 | `terraform apply`/`destroy` (+ `-auto-approve`) → ASK |
| 13/15/16 | `terraform fmt` · `tflint` · `init -backend=false && validate` |
| creds | `azure-lab-creds.sh` — hourly SP rotation from a shared file |

### Profile B — IDP / Internal Developer Platform  ·  Backstage + K8s/Helm + Crossplane
| Hook | Override |
|------|----------|
| 05 | **Wrong-Cluster Guard** — `kubectl config current-context` must match the intended cluster; block prod context for non-prod tasks |
| 06 | `kubectl delete ns`, `--force --grace-period=0`, `helm uninstall`, CRD/finalizer removal → DENY |
| 07 | `kubectl get secret -o yaml`, `.kube/config`, sealed-secrets keys, service-account tokens → DENY |
| 08 | Backstage `catalog-info.yaml` templates, `app-config.yaml`, RBAC policy, golden-path scaffolder templates, Argo `Application` manifests → ASK |
| 09/10/11 | Prod `kubectl apply`, `helm upgrade`, `argocd app sync`, Crossplane `Composition` apply → ASK |
| 13/15/16 | `helm template`+lint · `kubeconform`/OPA-conftest schema+policy · manifest render check |
| creds | `k8s-creds.sh` — refresh kubeconfig/short-lived tokens (same rotating-file pattern) |

Backstage is the IDP surface; the guardrails protect the platform *behind* the golden
paths (clusters, GitOps, scaffolder templates) — exactly where an AI edit does the most
damage across many teams at once.

### Profile C — Application / service repos  ·  app code + tests
| Hook | Override |
|------|----------|
| 05 | Target-environment guard on deploy scripts (`.env` target vs branch) |
| 06 | Block force-push to `main`/release branches, `DROP TABLE`, `prisma migrate reset`, mass file deletion |
| 08 | Migrations, auth/session code, payment/billing modules, CI deploy workflows → ASK |
| 13/15/16 | language formatter · linter · **test suite must pass** (16 = build/test green) |
| 19 | done-gate blocks on failing tests / uncommitted formatter changes |

### Profile D — Generic / unknown
Baseline only. Detect language on first use and graft the nearest profile's 13/15/16
validators. Safe by default: unknown destructive patterns get ASK, not ALLOW.

## Credential strategy (rotating labs & short-lived tokens)

The same pattern regardless of cloud:

1. A **source file** is refreshed out-of-band (hourly lab rotation, `aws sso`, `gcloud`,
   Vault lease). Point Claude at it: `export ALZ_AZURE_CREDS_FILE=…` (Azure), or the
   equivalent for the profile.
2. `scripts/<cloud>-creds.sh` parses it, performs the CLI login, and stamps a timestamp.
3. `SessionStart` warms it; `PreToolUse` re-checks freshness before every cloud command
   (>50 min ⇒ re-login). A mid-session rotation self-heals — no manual re-auth.
4. The tool CLI's own token cache carries auth into `terraform`/`kubectl`/etc., so no
   long-lived secret ever enters Claude's environment or the transcript.

## Rollout

| Wave | Repos | Profile |
|------|-------|---------|
| 1 (now) | azure-landing-zone-platform | A (reference) |
| 2 | internal developer platform | B |
| 3 | high-traffic service repos | C |
| 4 | long tail | D → refine into A/B/C |

Per repo: copy `.claude/`, set the profile overrides, add the creds source path to the
team's onboarding doc, and open a PR. The guardrails are reviewed and versioned like any
other code. Tune locally via `.claude/hooks/config.env` (gitignored) without forking the
committed hooks.
