# boomi-agentstudio

Notes for developers working on this skill.

## Layout

- `SKILL.md` — agent entry point and navigation hub: scope, terminology, credential contract, scripts inventory, and the create/update body shape.
- `scripts/agentstudio-common.sh` — sourced helper library: env loading, the Design / Execute URL builders, and the `agentstudio_api` wrapper. `agentstudio_api` feeds auth to curl on stdin (`-K -`) to keep credentials out of process arguments, so stdin is reserved — never `@-`, `-T -`, or piping into the wrapper. Inline `-d` and `--data-binary @file` are both fine.
- `scripts/agentstudio-*.sh` — per-noun CLI tools (agent, tool, source, deployment, session, env-check).

## Credential handling invariants

Three rules hold across `scripts/`. Each is mechanically checkable, so treat a change that breaks one as not mergeable.

- **Never in argv.** Auth reaches curl through `curl_cfg` on stdin (`-K -`). This is why stdin is reserved — see the `agentstudio_api` note above.
- **Never exported.** `load_env` sources `.env` without `set -a`, so values stay in the loading shell. Nothing needs them exported: `agentstudio_api` expands them in the same shell, no script invokes another as a child, and `jq` receives values via `--arg`.
- **Never in a shell trace.** xtrace prints commands *after* expansion, so any command expanding a credential prints its value — and Claude Code captures stderr into the transcript. Three sites expand one: `load_env`'s source, the `userpass` assignment in `agentstudio_api`, and `env_is_set`. Each carries its own fence, and `env_is_set` is the single by-name (`${!var}`) expansion site — add no others. `log_activity`'s `2>/dev/null` fences its block by the same mechanism, since xtrace writes to stderr.

A fence covers one function in one shell. `set -x` is not inherited across a process boundary on its own, but an exported `SHELLOPTS` (or a `BASH_ENV` startup file that sets `-x`) re-enables tracing in a child regardless of what the parent set — so if a script ever invokes another as a child, the callee needs its own guard. Comment every fence with the site it protects, so a later reader does not delete it as redundant.

Scripts outside the library need no fence of their own today: they pass credential *names* to `require_env`, and the values they print (`BOOMI_USERNAME` in `agentstudio-env-check.sh`) already go to stdout by design, so xtrace exposes nothing new.

## API surfaces

Agent Garden has two surfaces on separate region-specific hosts: the Design API (`/design/api/v1`, host in `AGENTSTUDIO_DESIGN_URL`) for building and reading agents/tools/sources/packages/deployments/environments, and the Execute API (`/execute/api/v1`, host in `AGENTSTUDIO_EXECUTE_URL`) for `POST /session`. Both authenticate with the same Platform API key via HTTP Basic (`BOOMI_TOKEN.<username>`).

Writes cover agent create/update, tool create/update plus the install/uninstall lifecycle (Prompt, OpenAPI, Integration, Hub), the package/deploy lifecycle (`package-create`, `deploy`), MCP-server source create/update (plus `discover`), and session invoke; there is no delete path. Everything else is read-only — packages, deployments, environments, MCP-type and Application tools (created via their source / Boomi-managed), and the non-MCP source types (`Application`, `acp_source`). Package/deploy and install/uninstall bodies are ID-only (no sensitive data), so those subcommands take IDs as flags and build the request inline rather than requiring a `--body` file like agent/tool create/update.
