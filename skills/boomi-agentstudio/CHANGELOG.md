# Changelog

## 0.1.42

- Feed credentials to curl on stdin instead of the command line (CWE-214)
- Stop exporting `.env` values to child processes (CWE-526)
- Keep credential values out of shell traces


## 0.1.41

- Pin the API User-Agent against install-directory and `.env` overrides


## 0.1.40

- Ship `CHANGELOG.md` inside the skill directory


## 0.1.39

- Add tool-type selection guidance on authoring tools.
- Document the Integration tool's return: execution metadata, no document content, `outboundDocumentCount: 0`.
- Document the read/write tool split for Integration processes.


## 0.1.38

- Add `AGENTSTUDIO_SESSION_TIMEOUT` (default `120`) for the session per-turn deadline.
- Report the enforced deadline in the timeout error instead of `AGENTSTUDIO_TIMEOUT`.
- Document both timeout settings in the plugin and skill READMEs.


## 0.1.37

- Document `AGENTSTUDIO_ENVIRONMENT_ID`, `AGENTSTUDIO_TIMEOUT`, and `BOOMI_COMPANION_LOG_ACTIVITY` in the skill README.
- Document the ANZ/JP Execute hosts and the ANZ/JP Design host fallback in the plugin README.
- Add the ANZ/JP hosts to the 401/403 region hint.


## 0.1.36

- Add `AGENTSTUDIO_ENVIRONMENT_ID` to `.env`; the deploy environment is no longer a CLI argument.
- `deploy` drops `--environment`; `package-create` replaces `--deploy-to <id>` with a `--deploy` flag.
- `deployments` drops `--environment`; always scoped to `AGENTSTUDIO_ENVIRONMENT_ID`.
- `env-check` reports and validates `AGENTSTUDIO_ENVIRONMENT_ID`.


## 0.1.35

- Document that MCP `available`/`available_tools[]` populate only in create/update/discover responses, not plain reads; re-`discover` to find un-imported tools.
- Document that MCP tools import as `ACTIVE` with no separate install step.
- Correct MCP-server `create`: it enforces no `url`/`name` uniqueness.


## 0.1.34

- Document that `word_filter` allows one policy per guardrail; `denied_topic` and `regex_pattern` allow multiples.
- Correct `regex_pattern` anchors: `^…$` restricts matches to the whole message.
- Clarify prompt-injection screening is an always-on baseline, not added by authored policies.


## 0.1.33

- Inject deployment_id/session_id from --deployment/--session into session invoke/continue --body requests


## 0.1.32

- Document conversational personality_traits


## 0.1.31

- Remove MCP-source request/error status-code note


## 0.1.30

- Enforce session file-upload limits locally (max 5 files, 10MB total).
- Escape control characters in session message text.
- Reject `--page 0` on list commands.
- Add opt-in local activity logging via `BOOMI_COMPANION_LOG_ACTIVITY=1`.
- Add overridable request timeout via `AGENTSTUDIO_TIMEOUT`.
- Accept `--body` and `<id>` in any order for agent and source create/update.


## 0.1.29

- Strip `input_schema_id`, `output_schema_id`, and `is_favorite` when mirroring an agent


## 0.1.28

- Document MCP-server source `title` and `headers` fields
- `description` is required on create


## 0.1.27

- Normalize environments filter enums (--classification, --status, --source) case-insensitively


## 0.1.26

- Document authentication types for MCP sources and API tools
- Default credentialed sources and tools to console


## 0.1.25

- Add server-side list filters: agent `--has-active-deployments`; tool `--status`/`--source-id`/`--application-name`; environments `--source`
- Fix: URL-encode agent and tool `list --search` values


## 0.1.24

- Map console Standard/Fast/Extended Thinking to processing_mode/rationale
- Note always-on default guardrails and denied-topic/sample-phrase caps
- Document session-scoped conversation memory
- Clarify that editing a tool or agent needs no disable step and doesn't affect a live deployment


## 0.1.23

- Document Hub tool `filter_fields` operators, per-operator `values` cardinality, and that `static_value` must be a stringified JSON value


## 0.1.22

- Document STALE and NOT_AVAILABLE status for MCP sources and imported MCP tools


## 0.1.21

- Correct MCP-server source `tools` import behavior


## 0.1.20

- Add shared paging/sort flags to list subcommands

## 0.1.19

- Add server-side filters to deployment script


## 0.1.18

- Add file upload support 

## 0.1.17

- Trim redundant tasks/guardrails from the structured-agent example; reference the conversational example instead


## 0.1.16

- Document that agents deploy and run only in a `PRODUCTION` environment; add `--classification` / `--status` filters to deployment `environments`


## 0.1.15

- Document the agent profile_picture (Agent Photo) fields: role, colour, and image_id


## 0.1.14

- Add tool authoring to boomi-agentstudio: create, update, install, and uninstall Prompt, OpenAPI, Integration, and Hub tools


## 0.1.13

- Document agent task and tool limits

## 0.1.12

- Document Platform console field-length limits for agent authoring

## 0.1.11

- Add conversational and structured agent-definition examples to `SKILL.md`


## 0.1.10

- MCP-server source support


## 0.1.9

- Document authoring and invoking `structured` agents


## 0.1.8

- agentstudio scripts: targeted curl-failure diagnostics


## 0.1.7

- `agentstudio-source.sh list` elides base64 icons by default.


## 0.1.6

- Document attaching tools to an agent task 


## 0.1.5

- Document agent `guardrails`


## 0.1.4

- Added package and deploy scripts


## 0.1.3

- Agent `list --status` and tool `list/get --type` now accept any casing

## 0.1.2

- Document Agent Garden regional hosts as a Design/Execute pairing table in `SKILL.md` and the README setup table.
- `agentstudio-env-check.sh` now lists Execute hosts by region and notes that ANZ/JP share the US Design host.


## 0.1.1

- Initial bc-agentstudio plugin scaffold

