# Local Credentials — Feed a JSON File, Automation Does the Rest

How local Azure auth works for Claude-assisted / CLI work in this repo, and what
to do when the lab rotates the service principal every ~1 hour.

> CI/CD does **not** use this — pipelines authenticate with OIDC federated
> credentials (see the main [README](../README.md#5-wire-up-cicd-step-7)). This
> page is only for **local** work where a rotating lab SP is the auth source.

## The one thing you maintain: a single JSON file

The entire local-auth flow reads credentials from **one file**. You keep that file
current; the automation handles login, freshness, and token propagation.

```
[lab: showcreds]  ──copy──▶  azure-lab-creds.json  ──▶  azure-lab-creds.sh  ──▶  az login  ──▶  Terraform
 (fresh SP hourly)            (the file you feed)        (freshness + login)      (CLI cache)   (azurerm)
```

### Where the file goes

Put it at any one of these paths — `azure-lab-creds.sh` probes them in order and
uses the first that exists:

| Priority | Path |
|----------|------|
| 1 | `$ALZ_AZURE_CREDS_FILE` (explicit — set in `.claude/hooks/config.env`) |
| 2 | `~/.azure-lab/creds.json` or `~/.azure-lab/creds.env` |
| 3 | `~/azure-lab-creds.json` / `~/azure-lab-creds.env` / `~/azure-creds.json` |
| 4 | `/mnt/c/Users/sound/azure-lab-creds.json` *(current default in use)* |
| 5 | `/mnt/c/Users/sound/Downloads/azure-lab-creds.json` |

All credential files (`*azure-lab-creds*.json/.env`, `*creds.env`,
`.claude/hooks/config.env`) are **gitignored** — they never get committed.

### The JSON format

Minimal (what maps from the lab `showcreds` output):

```json
{
  "appId": "<Azure Application Client ID>",
  "password": "<Azure Client Secret>",
  "tenant": "azurefreekmlprod.onmicrosoft.com"
}
```

- `tenant` is constant across rotations — the `…onmicrosoft.com` domain works as
  the tenant; a tenant GUID works too.
- `subscription` is **optional** — omit it and the automation auto-detects it from
  `az account show` after login. Add `"subscription": "<guid>"` to pin a target.
- Each hourly rotation only changes **`appId` + `password`**.

The parser also accepts other common key names, so you can feed a file verbatim
without renaming keys:

| Field | Accepted JSON keys | Accepted `.env` keys |
|-------|--------------------|----------------------|
| Client ID | `appId`, `clientId`, `client_id`, `ARM_CLIENT_ID` | `ARM_CLIENT_ID`, `AZURE_CLIENT_ID`, `clientId` |
| Client Secret | `password`, `clientSecret`, `client_secret`, `ARM_CLIENT_SECRET` | `ARM_CLIENT_SECRET`, `AZURE_CLIENT_SECRET`, `clientSecret` |
| Tenant | `tenant`, `tenantId`, `tenant_id`, `ARM_TENANT_ID` | `ARM_TENANT_ID`, `AZURE_TENANT_ID`, `tenantId` |
| Subscription | `subscription`, `subscriptionId`, `subscription_id`, `ARM_SUBSCRIPTION_ID` | `ARM_SUBSCRIPTION_ID`, `AZURE_SUBSCRIPTION_ID`, `subscriptionId` |

(An `az ad sp create-for-rbac` JSON blob, or a `KEY=VALUE` `.env`, work as-is.)

## What the automation does when you feed the file

Once the JSON is in place, this runs without further input from you:

1. **Locate** — `find_creds_file()` picks the first existing probe path above.
2. **Parse** — `parse_creds()` reads `appId` / `password` / `tenant` / `subscription`
   out of JSON **or** `.env`, without executing the file. Missing client-id, secret,
   or tenant → the script errors instead of a half-login.
3. **Freshness check** — `is_fresh()` returns "still good" only if
   `az account show` succeeds **and** the last login was < 50 min ago
   (`ALZ_CREDS_MAX_AGE`, default 3000s). Otherwise a refresh is triggered.
4. **Login** — `do_login()` runs `az login --service-principal` (+ `az account set`
   if a subscription is given), warming the **Azure CLI token cache**.
5. **Propagate** — it writes `~/.claude/alz/azure.env` (mode 600) with `ARM_*` /
   `AZURE_*` exports for anything that wants to `source` them, and stamps the login
   time in `~/.claude/alz/.azure-lastlogin`.
6. **Terraform just works** — the `azurerm` provider falls back to Azure CLI auth
   automatically, so **no `ARM_*` secret is ever exported into Claude's shell or the
   transcript.**

### When each step fires (you rarely call it by hand)

| Trigger | What happens |
|---------|--------------|
| `SessionStart` hook | Warms the login at the start of a Claude session. |
| `PreToolUse` hook | Before **every** `terraform`/`az` command, re-checks freshness (`--check`) and re-logs in if stale. **This is what makes rotation self-heal.** |
| Manual | `.claude/scripts/azure-lab-creds.sh --force` — re-login now. |
| Manual (source) | `source .claude/scripts/azure-lab-creds.sh --export` — refresh **and** load `ARM_*` into your current shell. |

## Hourly rotation — the update loop

Because login re-checks freshness on its own, **you only refresh the JSON file**:

1. In your lab, run `showcreds` (or however the lab surfaces the new SP).
2. Overwrite `appId` + `password` in the JSON file (keep `tenant`). Two fields.
3. Do nothing else. The next `terraform`/`az` call detects the >50-min age and
   re-logs in with the new secret. To pick it up immediately instead of waiting for
   the next command, run `azure-lab-creds.sh --force`.

### Command reference

```bash
# Refresh only if stale (>50 min) or logged out — safe to run anytime
.claude/scripts/azure-lab-creds.sh

# Force a re-login right now (use right after pasting new creds)
.claude/scripts/azure-lab-creds.sh --force

# Just ask "do I need to refresh?" — exit 0 = fresh, 1 = needs refresh
.claude/scripts/azure-lab-creds.sh --check

# Refresh AND export ARM_* into the current shell
source .claude/scripts/azure-lab-creds.sh --export
```

## Tunables (`.claude/hooks/config.env`, gitignored)

Copy `config.env.example` → `config.env` to override defaults:

```bash
export ALZ_AZURE_CREDS_FILE="/mnt/c/Users/sound/azure-lab-creds.json"  # explicit path
export ALZ_CREDS_MAX_AGE=3000        # re-login when older than this (seconds)
export ALZ_STATE_DIR="$HOME/.claude/alz"   # where azure.env + timestamp live
```

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `no credentials file found` | File isn't at a probed path — set `ALZ_AZURE_CREDS_FILE` or move it. |
| `could not parse client_id/secret/tenant` | Missing/misnamed key — check it has client id, secret, and tenant. |
| `az login failed — creds may be expired` | The lab rotated; the JSON still has the old SP. Re-feed the current `showcreds` values. |
| Terraform prompts for auth | `az account show` is empty — run `azure-lab-creds.sh --force`. |
