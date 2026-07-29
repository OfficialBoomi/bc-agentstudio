# boomi-agentstudio

A Boomi Companion skill for Boomi Agentstudio (the Agent Garden APIs).

> **Important:** Boomi Companion is a publicly available developer offering, not an officially supported Boomi product. It is provided as-is and is not covered by Boomi support agreements or SLAs. Boomi curates and maintains this tool on a best-effort basis — treat it as a self-service resource. Boomi reserves the right to modify or discontinue it at any time without notice.

This project is licensed under the [BSD-2-Clause License](LICENSE). If you fork or modify this code, you should not use the name "Boomi" for your version.

## Feedback & Issues

Found a bug or have a feature idea? Email developer-offerings@boomi.com with a clear description, steps to reproduce, and any relevant error messages.

## Setup

`bc-agentstudio` plugin and `boomi-agentstudio` skill read credentials from the workspace `.env`. If `bc-integration` plugin or `boomi-integration` skill is already setup, some of those Platform details are re-used by this skill/plugin.

| Key | Used by | Notes |
|---|---|---|
| `BOOMI_USERNAME` | Design + Execute | Your Boomi platform username (email) |
| `BOOMI_API_TOKEN` | Design + Execute | Settings → My User Settings → Platform API Tokens |
| `BOOMI_ACCOUNT_ID` | Design + Execute | Settings → Account Information |
| `AGENTSTUDIO_DESIGN_URL` | Design API | Agent Garden Design host for your region — US `https://ai-agent-garden.datalake-prod.boomi.com`, UK `https://ai-agent-garden.datalake-uk-prod.boomi.com`. ANZ/JP have no dedicated Design host; default to the US host. |
| `AGENTSTUDIO_ENVIRONMENT_ID` | Deploy/package/deployment ops | The single environment agents are deployed and tested against — the `ag_environment_id` of an ATTACHED `PRODUCTION` Agent Garden environment. The deploy target is fixed here, never passed on the command line. Find it with `bash <skill-path>/scripts/agentstudio-deployment.sh environments --classification PRODUCTION --source AGENT_GARDEN`; `agentstudio-env-check.sh` confirms the value. |
| `AGENTSTUDIO_EXECUTE_URL` | Execute API | Agent Garden Execute host for your region — US `https://c01-usa-east.ai-agent-garden.boomi.com`, UK `https://c01-gbr.ai-agent-garden.boomi.com`, ANZ `https://c01-aus.ai-agent-garden.boomi.com`, JP `https://c01-jp.ai-agent-garden.boomi.com`. Needed only for `session`; omit the line until you know it — `agentstudio-env-check.sh` suggests the value to add. |

Run `bash <skill-path>/scripts/agentstudio-env-check.sh` from a workspace with `.env` to verify credentials and the Design host.

### Optional settings

| Key | Default | Notes |
|---|---|---|
| `AGENTSTUDIO_TIMEOUT` | `60` | Per-request curl timeout in seconds for Design API calls. |
| `AGENTSTUDIO_SESSION_TIMEOUT` | `120` | Per-turn curl timeout in seconds for `agentstudio-session.sh`. Raise it for agents that make several sequential tool calls — a turn that overruns is aborted and its output discarded. |
| `BOOMI_COMPANION_LOG_ACTIVITY` | off | Set to `1` to append a local JSONL record of each write operation to `.activity-log/activity.jsonl`. Requires `jq`; nothing is sent off-machine. |

Allowlist the skill and its scripts in the workspace's `.claude/settings.json` under `permissions.allow`:

- `Skill(bc-agentstudio:boomi-agentstudio)`
- `Bash(bash */skills/boomi-agentstudio/scripts/*)`
