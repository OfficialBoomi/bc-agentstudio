# boomi-agentstudio

Notes for developers working on this skill.

## Layout

- `SKILL.md` — agent entry point and navigation hub: scope, terminology, credential contract, scripts inventory, and the create/update body shape.
- `scripts/agentstudio-common.sh` — sourced helper library: env loading, the Design / Execute URL builders, and the `agentstudio_api` wrapper.
- `scripts/agentstudio-*.sh` — per-noun CLI tools (agent, tool, source, deployment, session, env-check).

## API surfaces

Agent Garden has two surfaces on separate region-specific hosts: the Design API (`/design/api/v1`, host in `AGENTSTUDIO_DESIGN_URL`) for building and reading agents/tools/sources/packages/deployments/environments, and the Execute API (`/execute/api/v1`, host in `AGENTSTUDIO_EXECUTE_URL`) for `POST /session`. Both authenticate with the same Platform API key via HTTP Basic (`BOOMI_TOKEN.<username>`).

Writes cover agent create/update, tool create/update plus the install/uninstall lifecycle (Prompt, OpenAPI, Integration, Hub), the package/deploy lifecycle (`package-create`, `deploy`), MCP-server source create/update (plus `discover`), and session invoke; there is no delete path. Everything else is read-only — packages, deployments, environments, MCP-type and Application tools (created via their source / Boomi-managed), and the non-MCP source types (`Application`, `acp_source`). Package/deploy and install/uninstall bodies are ID-only (no sensitive data), so those subcommands take IDs as flags and build the request inline rather than requiring a `--body` file like agent/tool create/update.
