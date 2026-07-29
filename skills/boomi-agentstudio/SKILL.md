---
name: boomi-agentstudio
description: Builds and runs Boomi Agentstudio AI agents (the Agent Garden APIs) — list and inspect agents, author and update agent definitions including guardrails, author and install tools (Prompt, OpenAPI, Integration, Hub), browse sources, packages, deployments, and environments, and invoke deployed agents in a conversation. Use when the user works with Boomi Agentstudio or Agent Garden agents, agent guardrails, agent tools, agent packages, or agent deployments.
---

# boomi-agentstudio

## Scope

In: read agents, tools, sources, packages, deployments, and environments; author agents (`create`, `update`); author tools (`create`, `update`, `install`, `uninstall` — Prompt, OpenAPI, Integration, Hub); author MCP-server sources (`discover`, `create`, `update`); package and deploy an agent (`package-create`, `deploy`); invoke a deployed agent and continue the conversation (`session`).

Out: deleting anything (no delete path exists in this skill); creating MCP or Application tools directly — MCP tools come from their source (see **Authoring an MCP-server source**) and Application tools are Boomi-managed and read-only. Application and `acp_source` sources are read-only — the Design API exposes source writes only for MCP servers. Building Boomi integration processes belongs to `boomi-integration` — an Integration-type tool merely references a process that already exists there.

## Terminology

- **Agentstudio** is the product name; **Agent Garden** is the API name — hosts and paths read `ai-agent-garden`, `/design/api/v1`, `/execute/api/v1`.
- A **package** is a versioned snapshot of an agent. A **deployment** binds a package to an environment. The Execute API invokes by **`deployment_id`**, not `agent_id`.
- An agent's **`agent_mode`** is `conversational` or `structured`. A conversational agent's `session` reply is a Server-Sent Events stream (`text/event-stream`); a structured agent returns one JSON object.
- A **source** is the application or MCP server that tools are discovered from — distinct from a **tool**.
- IDs are UUIDs, except a **`session_id`**, which is a ULID (e.g. `01KSFE6WT8G0SHSTCRWAC28WN8`).

## API surfaces

Agent Garden has two surfaces on separate, region-specific hosts. **Reach them only through the CLI tools below — never hand-roll curl, URLs, or auth.** The scripts build the URL, pick the right surface, and read credentials from `.env`.

- **Design API** (`AGENTSTUDIO_DESIGN_URL`) — agents, tools, sources, packages, deployments, environments.
- **Execute API** (`AGENTSTUDIO_EXECUTE_URL`) — `session` invocation only.

The two hosts are region-specific and must be paired — a host that doesn't match your console region authenticates as 401/403. Set the base host (no path) in `.env`; the scripts append `/design/api/v1` and `/execute/api/v1`.

| Region | `AGENTSTUDIO_DESIGN_URL` | `AGENTSTUDIO_EXECUTE_URL` |
|---|---|---|
| US | `https://ai-agent-garden.datalake-prod.boomi.com` | `https://c01-usa-east.ai-agent-garden.boomi.com` |
| UK | `https://ai-agent-garden.datalake-uk-prod.boomi.com` | `https://c01-gbr.ai-agent-garden.boomi.com` |
| ANZ | No dedicated Design endpoint. Default to: `https://ai-agent-garden.datalake-prod.boomi.com` | `https://c01-aus.ai-agent-garden.boomi.com` |
| JP | No dedicated Design endpoint. Default to: `https://ai-agent-garden.datalake-prod.boomi.com` | `https://c01-jp.ai-agent-garden.boomi.com` |

## Credentials

The skill reads credentials from the workspace `.env`; sensitive values are never accepted as command-line arguments.

| Surface | `.env` keys |
|---|---|
| Design API | `BOOMI_USERNAME`, `BOOMI_API_TOKEN`, `BOOMI_ACCOUNT_ID`, `AGENTSTUDIO_DESIGN_URL` |
| Deploy target | `AGENTSTUDIO_ENVIRONMENT_ID` (Design API — deploy/package/deployment operations) |
| Execute API | the same `BOOMI_*` keys plus `AGENTSTUDIO_EXECUTE_URL` |

`AGENTSTUDIO_ENVIRONMENT_ID` is the single environment this skill deploys and tests agents against — set it to the `ag_environment_id` of an ATTACHED `PRODUCTION` Agent Garden environment (see **Packaging and deploying an agent** for how to find one). The deploy target is **fixed in `.env` and never passed as an argument**: `deploy`, `package-create --deploy`, and the `deployments` listing all read it from there. It is required only for those operations.

`AGENTSTUDIO_EXECUTE_URL` is needed only for `session`. Leave the line out of `.env` until its value is known — `agentstudio-env-check.sh` suggests it once the Design host is reachable. Invoking requires the token to carry the `AGENT_INTERACT` privilege in addition to `AGENT_GARDEN_ACCESS` and `AGENT_VIEW`.

## Authoring an agent

`agent create`/`update` post a JSON file verbatim. To mirror an existing agent, `agent get` it, then keep only the writable fields — `objective` (required), `name`, `personality_traits`, `profile_picture`, `conversation_starters`, `tasks`, `guardrails` (see **Guardrails** below), `agent_mode`, the `input_schema*`/`output_schema*` fields (see **Structured agents** below), and `inference_configuration`. Strip server-assigned read-only fields: `id`, `created_on`, `last_updated_on`, `unique_name`, `installed_on`, `deployments`, `packages_count`, `input_schema_id`, `output_schema_id`, `is_favorite`. Reference tools, sources, and environments by IDs discovered with the read scripts. A stale `input_schema_id`/`output_schema_id` fails `update` with an opaque error, so drop both — the server assigns its own.

Only `objective` is required. The two `agent_mode`s differ in a few fields; both take `tasks`, `guardrails`, and `inference_configuration`.

**Conversational** — free-form chat; adds `personality_traits` and `conversation_starters`:

```json
{
  "objective": "Provide first-line IT support: triage issues, offer fixes, and create tickets for unresolved problems.",
  "name": "IT Support Assistant",
  "agent_mode": "conversational",
  "personality_traits": {
    "voice_tone": "Professional",
    "creativity": 40, "decisiveness": 70, "clarity": 80, "confidence": 70, "engagement": 60
  },
  "conversation_starters": ["How can I help with your IT issue today?"],
  "inference_configuration": {
    "performance_config": { "processing_mode": "standard", "rationale": true }
  },
  "tasks": [
    { "name": "Diagnose issue", "objective": "Identify the user's IT problem.",
      "instructions": ["Ask clarifying questions, then check for recent changes"],
      "tools": [ { "id": "11111111-1111-1111-1111-111111111111", "type": "Application", "requires_approval": true } ] }
  ],
  "guardrails": {
    "blocked_message": "I can't help with that request.",
    "system": false,
    "policies": [
      { "name": "Block SSNs", "type": "regex_pattern", "configuration": { "pattern": "\\d{3}-\\d{2}-\\d{4}" } }
    ]
  }
}
```

**Structured** — object in, object out; adds the required `*_schema`/`*_schema_type` fields, no `personality_traits`/`conversation_starters`. `tasks` and `guardrails` work the same as in the **Conversational** example:

```json
{
  "objective": "IT support assistant for Slack. Classify each request as okta, software request, hardware request, or other, then resolve it or raise a ticket.",
  "name": "ServiceDesk Bot",
  "agent_mode": "structured",
  "input_schema_type": "json",
  "input_schema": "{\"type\":\"object\",\"properties\":{\"email\":{\"type\":\"string\"},\"chat_id\":{\"type\":\"integer\"},\"messages\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"role\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"}},\"required\":[\"role\",\"content\"]}}},\"required\":[\"chat_id\",\"email\",\"messages\"]}",
  "output_schema_type": "json",
  "output_schema": "{\"type\":\"object\",\"properties\":{\"intent\":{\"type\":\"string\",\"enum\":[\"okta\",\"software request\",\"hardware request\",\"other\"]},\"response\":{\"type\":\"string\"},\"status\":{\"type\":\"string\",\"enum\":[\"in-progress\",\"completed\"]}},\"required\":[\"intent\",\"response\",\"status\"]}",
  "inference_configuration": {
    "performance_config": { "processing_mode": "standard", "rationale": true }
  }
}
```

- `personality_traits` (conversational agents only): all fields optional. `voice_tone` is `Professional` (default), `Friendly`, `Instructional`, or `Playful`; the five below are integers 0-100 (default 50; out-of-range, fractional, or non-numeric values are rejected 422, not clamped). Defaults fill per field only when the object is present; omit the whole object and it stores as `null`.

  | Trait | Governs |
  |---|---|
  | `creativity` | Novelty and imagination |
  | `decisiveness` | Willingness to give direct recommendations |
  | `clarity` | Precision and comprehensibility |
  | `confidence` | Certainty expressed in answers |
  | `engagement` | Interactive/conversational depth |
- `structured` agents also require the `input_schema`/`output_schema` and `*_schema_type` fields — see **Structured agents**.
- `inference_configuration.performance_config` sets the agent's **model configuration** — `processing_mode` (`standard` or `quick`) and `rationale` (boolean). The console's three named settings map onto these two fields (both agent modes):

  | Console setting | `processing_mode` | `rationale` |
  |---|---|---|
  | Standard | `standard` | `false` |
  | Standard + Extended Thinking *(default)* | `standard` | `true` |
  | Fast | `quick` | `false` |
  | Fast + Extended Thinking | `quick` | `true` |

  **Fast is `quick`** — the field value differs from the label. `rationale` is the **Extended Thinking** switch (step-by-step reasoning, higher latency and token use). The API defaults (`standard` / `rationale: true`) are the recommended default; when the user gives no preference, use them.
- `inference_configuration.file_inference_config` enables **file uploads** on the agent (off by default) — see **File uploads**. `allowed` (boolean, default `false`) is the switch; `types` is the accepted-format allow-list, a subset of `pdf, csv, txt, docx, xlsx, png, jpg, jpeg`. `types` must be empty/omitted when `allowed` is `false`, and every entry must be a valid format — either violation is HTTP 422 (values are **not** coerced, unlike `profile_picture`). Both agent modes.
- Optional cosmetic `profile_picture` (the console's **Agent Photo**), an object of three strings:
  - `role` — the **Avatar** selector: `Default` (default), `Support`, `Marketplace`, `Data`, `Automation`, `Test`, `Code`, `Security`, `Document`, `Analysis`, `Calendar`, `Company`, `Rocket`, `Chat`, `Explore`.
  - `colour` (British spelling): `Sunset` (default), `Lavender`, `Seabreeze`, `Midnight`.
  - `role` and `colour` are **coercing** — an unlisted value is silently stored as the default, with no error — so send an exact value from these lists and read it back to confirm.
  - `image_id` (the avatar's icon) is a free-form string the API neither derives from `role` nor validates: any value persists verbatim, `null` returns HTTP 422, and omitting it resets to `image_person`. The API cannot produce the canonical per-avatar `image_id`; to reproduce a specific console avatar, copy its `image_id` from an agent that already uses it.
- A task's `instructions` entries are stored as a single newline-joined string; `tasks[].tools` reference existing tools by `id` + `type` (see **Equipping a task with tools**). `guardrails` — see **Guardrails**.
- An agent may have **at most 10 tasks**, and **at most 25 unique tools** across all of its tasks — see **Equipping a task with tools**.

## Structured agents

`agent_mode: "structured"` — object in, object out. Four fields required together:

| Field | Value |
|---|---|
| `input_schema`, `output_schema` | JSON Schema as a **string**, not a nested object (nested — HTTP 422 `Input should be a valid string`). Round-trips unchanged on `get`; server assigns read-only `input_schema_id`/`output_schema_id` — strip both before re-posting (see **Authoring an agent**). |
| `input_schema_type`, `output_schema_type` | `"json"`; omitting either — HTTP 422 `No value was provided for the required field(s): (Input Schema Type, Output Schema Type)`. |

See the structured example under **Authoring an agent**.

Package/deploy is identical to conversational (same ">=1 task" precondition).

Invoke with `session invoke --body <file>` where `message` is an object satisfying `input_schema` (not `--message`, which sends a string). Reply is one `application/json` object `{ success, agent_id, session_id, data }`, result in `data` as an object. String `message` — `The input does not match the schema configured for this Agent`. Conversational agents stream SSE instead.

## Guardrails

An agent's `guardrails` is a single object (or `null`) that screens conversation turns:

```json
"guardrails": {
  "blocked_message": "I can't help with that request.",
  "system": false,
  "policies": [
    { "name": "No investment advice", "type": "denied_topic",
      "configuration": { "description": "Recommendations about investing or allocating funds.",
                         "sample_phrases": ["Should I invest in gold?"] } },
    { "name": "Block SSNs", "type": "regex_pattern",
      "configuration": { "pattern": "\\d{3}-\\d{2}-\\d{4}" } },
    { "name": "Prohibited terms", "type": "word_filter",
      "configuration": { "words": ["guarantee"] } }
  ]
}
```

- `blocked_message` — **required**; returned verbatim when a turn is blocked (length bounded — see **Field length limits**).
- `system` — **must be `false`** for authored guardrails.
- `policies[]` — each has an optional `name`, a `type`, and a required type-specific `configuration`. `denied_topic` and `regex_pattern` allow multiple policies per `type`; `word_filter` allows only **one per guardrail** (a second → HTTP 422) — put every banned word in its one `configuration.words[]`. Max **30 `denied_topic` policies**, each ≤ **5 `sample_phrases`**.

| `type` | Blocks an input turn when |
|---|---|
| `denied_topic` | it semantically matches the topic |
| `word_filter` | it contains a listed word |
| `regex_pattern` | the pattern matches anywhere in the message (**substring** match). Omit anchors to catch embedded values; `^…$` restricts to the whole message (so `^\d{3}-\d{2}-\d{4}$` misses an SSN mid-sentence). |

A blocked turn arrives in-band as a normal SSE `event: message` whose `content` is exactly `blocked_message` — no distinct event type or status — so detect a block by comparing `content` to the configured `blocked_message`.

Prompt-injection is screened by the always-on default guardrails (see below), not by authored policies: a strong override ("ignore all previous instructions…") is blocked; a mild terse imperative ("reply with only OK") may not be.

**Default guardrails always apply.** Independent of the `guardrails` object — even when it is `null` — every agent enforces backend guardrails that cannot be configured or turned off: profanity detection, prompt-attack prevention, and harmful-content categories (hate, violence, self-harm, sexual). Authored `policies[]` add to this baseline, so don't spend a policy re-implementing profanity or prompt-injection blocking, and don't describe an agent as unguarded just because `guardrails` is `null`.

## Field length limits

The Platform console enforces a maximum length on each of these authoring fields. Stay within them so an agent authored through the API stays editable in the console.

| Field | JSON path | Max characters |
|---|---|---|
| Agent name | `name` | 50 |
| Agent goal | `objective` | 2000 |
| Task name | `tasks[].name` | 50 |
| Task description | `tasks[].objective` | 500 |
| Task instruction | each string in `tasks[].instructions[]` | 40000 |
| Blocked message | `guardrails.blocked_message` | 500 (min 1) |
| Denied-topic name | `policies[].name` (type `denied_topic`) | 50 |
| Denied-topic description | `policies[].configuration.description` | 200 |
| Denied-topic sample phrase | each string in `policies[].configuration.sample_phrases[]` | 150 |
| Word-filter word | each string in `policies[].configuration.words[]` | 50 |
| Regex pattern | `policies[].configuration.pattern` (type `regex_pattern`) | 100 |

## Packaging and deploying an agent

Making an agent runnable is two steps on the Design API, both in `agentstudio-deployment.sh`:

1. `package-create <agent-id>` snapshots the agent's current definition as an immutable, versioned **package** and returns a `package_id`. The agent must have at least one task configured, or packaging is rejected. Every tool referenced by its tasks must also be installed (`ACTIVE`), or packaging fails: `"N tool(s) remain inactive."`
2. `deploy <agent-id> --package <package-id>` binds that package to the deploy-target environment (`AGENTSTUDIO_ENVIRONMENT_ID` from `.env`) and returns a `deployment_id`.

**The deploy target comes from `.env`, not an argument.** All deploy operations use `AGENTSTUDIO_ENVIRONMENT_ID` — you never pass an environment ID on the command line. To package and deploy in one call, pass `--deploy` (a flag, no value) to `package-create` — it creates the package and deploys it to that environment, returning the deployment. A deployment is keyed by agent + environment: deploying a different package to the same agent and environment updates that deployment in place — same `deployment_id`, new package version — rather than creating a second one.

**Editing is decoupled from deployment.** `agent update` (like tool `update`) runs at any time whether or not the agent has a live deployment — no disable step is required, and the edit does not touch the running deployment (it stays on its deployed package version). The editable definition always reports `agent_status: DRAFT`; an edit goes live only when you `package-create` a new version and `deploy` it.

**Deploy only to a Production environment.** Over the API an agent can only be deployed to — and run in — a `PRODUCTION`-classification environment; deploying a package to a `TEST` environment is rejected server-side with `Please select an Active Production environment` and no deployment is created.

**Configuring the deploy target.** The environment is set once in `.env` as `AGENTSTUDIO_ENVIRONMENT_ID`, not chosen per deploy. To find its value, list candidates with `agentstudio-deployment.sh environments --classification PRODUCTION --source AGENT_GARDEN`. Each returned environment carries `classification` (`PRODUCTION`|`TEST`), `status` (`ATTACHED` when a runtime is attached, `DETACHED` otherwise), `source`, and `is_default`. Pick an `ATTACHED` Agent Garden environment (`source: "AGENT_GARDEN"`) and set `AGENTSTUDIO_ENVIRONMENT_ID` to its `ag_environment_id` — that field is `null` for `source: "INTEGRATION"` environments, which are not Agent Garden deploy targets. `agentstudio-env-check.sh` confirms the configured value resolves to a valid target. If the user asks to deploy somewhere else, direct them to update `.env` rather than accepting an environment ID inline.

The returned `deployment_id` is what `session invoke` uses. Packaging requires the token's `AGENT_CREATE` privilege; deploying also requires `AGENT_INSTALL`.

### Equipping a task with tools

`tasks` is an array; each task is `{ "name", "objective", "instructions": [], "tools": [] }` (`name` and `objective` required). An agent **attaches an existing tool** to a task — it never creates one inline. Author the tool first (see **Authoring tools**, or for MCP see **Authoring an MCP-server source**), then attach it by `id` + `type`; an Integration tool's process belongs to `boomi-integration`. Each entry in a task's `tools[]` is a reference:

| Field | Required | Notes |
|---|---|---|
| `id` | yes | The tool's UUID, from `agentstudio-tool.sh list` (or `get`, which supports all types but `Application`). |
| `type` | yes | Bare tool type — `Integration`, `Hub`, `Prompt`, `MCP`, `OpenAPI`, `Application` — exactly as `tool list` reports it. Suffixed forms (e.g. `HubTool`) are rejected with `Invalid tool type`. |
| `requires_approval` | no | Defaults `false`. |
| `response_passthrough` | no | Defaults `false`. |

Attach by `id` + `type` for **every** type, including `Application`. Beyond those two fields:

- Don't send `name` — the server hydrates it from the catalog by `id` on read. A task tool has no `unique_name`, `application_name`, or `application_tool_name` (those are export-format fields only).
- A non-existent `id` is rejected with `Tool(s) not found`, and the whole write fails atomically.
- Attach tools inline at `create` — no separate update step. To clear a task's tools, set its `tools` to `[]`.
- **A single task must not list the same tool twice** — within one task's `tools[]`, each tool (by `id`) appears at most once.
- **An agent may attach at most 25 unique tools** across all of its tasks. A tool counts once toward that limit no matter how many tasks use it, so different tasks may freely share the same tool; only the count of *unique* tools is capped at 25.

```json
"tasks": [
  {
    "name": "Determine tool",
    "objective": "Pick the right tool for the request.",
    "instructions": ["Analyze the user's request"],
    "tools": [
      { "id": "11111111-1111-1111-1111-111111111111", "type": "Hub" },
      { "id": "22222222-2222-2222-2222-222222222222", "type": "Application", "requires_approval": true }
    ]
  }
]
```

## Authenticating sources and tools

An MCP-server source and an OpenAPI (API) tool can each carry an `authentication` object that reaches an external MCP server or REST API. This is a **downstream target** credential — distinct from the **platform caller** credential (`BOOMI_*` in `.env`, see **Credentials**) that authenticates the skill *to* Agent Garden. Both surfaces share one auth model and the same request shape: `authentication` is `null`/omitted, or `{ "type": <type>, "config": {…} }`.

**Never place a downstream secret in the conversation.** The scripts POST the body file verbatim, so a token or password written into a body would enter the context window. Handle credentialed auth by the type's row below.

| `type` | `config` | Secret | Use for |
|---|---|---|---|
| `None` | — | no | OpenAPI (API) tools only — an unauthenticated endpoint. |
| `platform_jwt` | none | no | A Boomi Platform API target — reuses the caller's Boomi identity (the `.env` `BOOMI_*` credential); no extra secret. |
| `token_auth` | `{ "key": "Authorization", "value": "Bearer <token>" }` | yes | A header-based token; `key` is the header name (default `Authorization`). For the `Authorization` header the runtime formats a Bearer token and normalizes to exactly one `Bearer ` prefix — a bare token and `Bearer <token>` both send `Authorization: Bearer <token>`. |
| `basic_auth` | `{ "username": …, "password": … }` | yes | HTTP Basic. |
| `oauth` | — (provision in the console) | yes | OAuth authorization-code — see below. |

**No-secret types — author directly.** `None` and `platform_jwt` carry nothing sensitive, so write these bodies with the **Write** tool as normal. Prefer `platform_jwt` whenever the target is a Boomi Platform API — it needs no credential of its own.

**Secret types (`token_auth`, `basic_auth`) — default to the console.** Provision the credentialed MCP source / OpenAPI (API) tool in the Boomi console, then reference it by `id` from the skill (`source mcp-servers` for MCP servers; `tool list --type OpenAPI` / `tool get` for OpenAPI (API) tools). The secret stays in the platform and never reaches the conversation.

**Updating a credentialed source/tool.** A `get` (or `source mcp-servers <id>`) never returns the secret — auth reads back as its bare `type` with `config` stripped (`oauth` returns only its non-secret fields) — so you cannot rebuild a credentialed body from a read. An `update` that omits `authentication` leaves the stored credential in effect, so you can safely edit other fields without re-supplying it; to set or change the credential itself, use the Boomi console.

**OAuth needs interactive consent.** Creating and installing an `oauth` tool works headlessly, but authorization-code OAuth needs an interactive sign-in that a headless `session invoke` cannot complete — at runtime the agent returns an `auth_required` consent prompt (a sign-in URL) instead of calling the tool. Set up and consent the OAuth connection in the Boomi console, then reference the tool by `id`.

## Authoring an MCP-server source

An MCP tool exists only after its **source** — the MCP server that exposes it — is created; author the server first, then attach its tools to an agent task.

- `source discover --body <file>` — connect to a server and return its tools **without saving**.
- `source create --body <file>` — save the server and import the listed tools; they then appear in `tool list --type MCP`. `create` enforces **no uniqueness** — re-posting an existing `url` or `name` is accepted with no error and creates a **separate** source with a new `id`. To avoid duplicates, check for an existing one first (`source list --type MCPServer --search <name>`). Read a saved server back with `source mcp-servers <id>` — its response includes the server's imported tools inline (`source get` reads Application sources only).
- `source update <id> --body <file>` — takes a **full** body (re-supply `name`/`url`/`transport_type`); only the changed fields apply.

Body: required `name`, `url`, `transport_type` (`SSE` or `HTTP`), and `description` (required on `create`, optional on `update`); optional `authentication`, `title`, and `headers`. `tools` lists which tools to import — each entry an object `{ "name": "<tool>" }`, not a bare string. On `create` it is required (omitting it or sending `[]` errors and creates nothing); to import a whole server, list all its tools — get the names with `discover`. On `update`, `tools` is additive: it imports the named tools (re-importing one already present errors) and omitting it leaves the imported set unchanged. When a server needs credentials, set `authentication` (`type` one of `token_auth`, `basic_auth`, `platform_jwt`, `oauth`) — see **Authenticating sources and tools** for the config shapes and how to supply the secret safely.

Two more optional fields:
- `title` — a display title, distinct from `name`; set it with `update` (a `create` does not persist it).
- `headers` — custom HTTP headers to send to the MCP server, for cases the `authentication` types don't cover (e.g. a custom `X-API-Key`): an array of `{ "name", "static_value" }` objects. Values are not masked on read-back, so keep secrets out of `headers` and use `authentication` for anything sensitive.

**Stale and Not Available status.** An MCP-server source and its imported MCP tools can report a `STALE` status (in the source's `status` and a tool's `tool_status`) — the imported copy has drifted from the upstream server's current tool definitions. A stale tool is not reliably usable by an agent. Do not silently work around a stale source or tool: alert the user that the MCP-server source needs its configuration refreshed and its affected tools re-imported to clear the stale status. An imported MCP tool can also report `NOT_AVAILABLE` — the tool no longer resolves on the upstream server; alert the user to check that the tool still exists on the MCP server.

**Finding un-imported tools.** A server's `available_tools[]` (with the `available` count, in the response's `tool_counts`) lists tools the server exposes but hasn't imported — but both populate **only** in a `create`, `update`, or `discover` response. A plain `source mcp-servers <id>` read always reports `available: 0`, so re-run `source discover` to see what a saved server still offers, then `source update` to import by name.

**MCP tools import as `ACTIVE`.** Imported tools come back `ACTIVE`, not `DRAFT` — there is no separate install step for MCP tools, so they satisfy the all-tools-`ACTIVE` packaging precondition immediately.

## Authoring tools

Four tool types are authored through `agentstudio-tool.sh`: **Prompt**, **OpenAPI** (the console's "API tool"), **Integration**, and **Hub** (the console's "DataHub Query tool"). MCP tools come from a source (see **Authoring an MCP-server source**); `Application` tools are Boomi-managed and read-only.

**Picking a type.** Prompt runs an LLM instruction; OpenAPI calls one REST/SOAP endpoint; Hub queries DataHub golden records; Integration triggers a deployed Boomi process. The distinction that constrains design: an Integration tool returns only execution metadata, never document content, so it fits side effects — write, record, dispatch, notify — rather than anything the agent needs to read back. If the agent must see what the call produced, reach for OpenAPI, Hub, or MCP.

**Lifecycle.** `create --type <type> --body <file>` posts a definition; the new tool is **`DRAFT`**. A DRAFT tool can be attached to a task, but an agent referencing any inactive tool **cannot be packaged** (`package-create` fails: `"N tool(s) remain inactive."`) — so `install --type <type> <id>` every referenced tool before packaging. `install` (the console's "Deploy Tool") sets `tool_status` → `ACTIVE`; `uninstall` → `DISABLED`. `update --type <type> <id> --body <file>` replaces the definition but cannot change `tool_status` (only `install`/`uninstall` do) — and needs no disable step first: a tool can be updated in any status (`DRAFT`, `ACTIVE`, or `DISABLED`) and the edit leaves `tool_status` unchanged. `create` needs `AGENT_CREATE`; `install`/`uninstall` need `AGENT_INSTALL`. Read `tool_status`, not `installed_on`, to check active state — `installed_on` is set only while `ACTIVE`.

To mirror an existing tool, `get` it and keep the writable fields; strip the read-only set (silently ignored if sent): `id`, `created_on`, `last_updated_on`, `created_by`, `last_updated_by`, `last_used_on`, `installed_on`, `pre_installed`, `provider_name`, `provider_id`, `unique_name`, `tool_status`, `type`.

**Fields shared by all four types:**

- `name` — **required**.
- `description` — the LLM uses it to decide when to call the tool.
- `input_parameters[]` — values the agent collects from the user at runtime; each `{ "name", "description", "required": <bool>, "type": <t> }`. `type` is one of `string`, `integer`, `float`, `boolean` (the JSON-Schema spelling `number` is rejected, 422).
- **Placeholder** — reference an input parameter elsewhere in the body as `{{<name>}}`, matching `input_parameters[].name` exactly (spaces allowed).

Several fields wire a value from either a static literal or an input parameter — OpenAPI query/path/header params, Integration dynamic process properties, Hub filter values. Each is an object `{ "static_value": <literal|null>, "input_parameter_name": <param|null> }`: set one, leave the other `null`.

**Prompt** — a few-shot prompt the agent runs for its task:

```json
{
  "name": "Sentiment classifier",
  "description": "Classify customer feedback as positive, neutral, or negative.",
  "input_parameters": [
    { "name": "Feedback", "description": "The customer's feedback text.", "required": true, "type": "string" }
  ],
  "prompt": "Classify the sentiment of the following feedback: {{Feedback}}",
  "examples": [
    { "input": "The service was slow and staff were rude.", "output": "negative" }
  ]
}
```

- `prompt` — **required**.
- `examples[]` — optional few-shot pairs, each `{ "input", "output" }`.

**OpenAPI** (console "API tool") — one REST/SOAP endpoint:

```json
{
  "name": "Get contact",
  "description": "Retrieve a CRM contact by ID.",
  "input_parameters": [
    { "name": "contact_id", "description": "The contact's ID.", "required": true, "type": "string" }
  ],
  "base_url": "https://api.example.com",
  "path": "/contacts/{{contact_id}}",
  "method": "GET",
  "query_parameters": [],
  "path_parameters": [],
  "headers": [],
  "authentication": null,
  "request_body": null,
  "source_id": null,
  "source_name": null
}
```

- `method` — `GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `OPTIONS`, or `HEAD`.
- `query_parameters`/`path_parameters`/`headers[]` — each `{ "name", "static_value", "input_parameter_name" }` (static-or-parameter object). Reference path parameters inline in `path` as `{{name}}`.
- `request_body` — `null`, or `{ "type": "<content-type>", "template": "<body, may embed {{params}}>" }`. Content types: `application/json`, `application/xml`, `application/x-www-form-urlencoded`, `multipart/form-data`, `text/plain`.
- `authentication` — `null`/`None` (unauthenticated), or `{ "type": ..., "config": {…} }` with `type` one of `token_auth`, `basic_auth`, `platform_jwt`, `oauth`. See **Authenticating sources and tools** for the config shapes, the console-first default for secret-bearing types, and OAuth (console-only).
- `source_id`/`source_name` — `null` unless the tool comes from an API Control Plane source.

**Integration** — trigger a deployed Boomi process:

```json
{
  "name": "Update opportunity",
  "description": "Run the Salesforce opportunity-update process.",
  "input_parameters": [
    { "name": "opportunity_id", "description": "Opportunity to update.", "required": true, "type": "string" }
  ],
  "environment_id": "<env-id>",  "environment_name": "Production",
  "atom_id": "<atom-id>",        "atom_name": "Prod Atom",
  "process_id": "<process-id>",  "process_name": "Update Opportunity",
  "dynamic_process_properties": {
    "dpp_opportunity_id": { "static_value": null, "input_parameter_name": "opportunity_id" }
  }
}
```

- `environment_id`/`atom_id`/`process_id` identify a deployed, **non-listener** process (discover via `boomi-integration` or the Platform); `*_name` are display labels. A name-only `create` succeeds (IDs default to `""`) but the tool is non-functional until `update`d with real IDs.
- `dynamic_process_properties` — a map keyed by the process's DPP name; each value is the static-or-parameter object.
- The agent receives one JSON object of execution metadata — status, execution id, timing, and document counts; `outboundDocumentCount` reads `0` even when the process added documents to its Return Documents store. A process that both reads and writes usually wants splitting: an OpenAPI or Hub tool for the read, this tool for the write, with the read value passed in as a DPP.

**Hub** (console "DataHub Query tool") — query golden records from one repository:

```json
{
  "name": "Product lookup",
  "description": "Query the product catalog by category.",
  "input_parameters": [],
  "repository_id": "<repo-id>",   "repository_name": "Product Catalog",
  "universe_id": "<universe-id>", "universe_name": "product",
  "cloud_host": "https://<hub-host>.hub.boomi.com",
  "fields": [
    { "unique_id": "PRODUCT_NAME", "pretty_name": "product_name", "path": "/product/product_name", "data_type": "STRING", "repeatable": false }
  ],
  "limit": 200,
  "filter_operator": "",
  "filter_fields": [
    { "field_id": "CATEGORY", "operator": "EQUALS", "values": [ { "static_value": "Hardware", "input_parameter_name": null } ] }
  ]
}
```

- `repository_id`/`universe_id`/`cloud_host` and each `fields[]` entry come from the DataHub repository and its deployed model; `fields[]` are the model fields the query returns. Like Integration, a name-only `create` succeeds but is non-functional until `update`d with real IDs.
- `limit` — caps returned golden records (max 200).
- `filter_fields[]` — `{ "field_id", "operator", "values": [ <static-or-parameter object> ] }`; filtering is by Field ID only. Documented `operator` values: `EQUALS`, `STARTS_WITH`, `GREATER_THAN`, `BETWEEN`, `IS_NULL`, `IS_NOT_NULL`. `values` cardinality depends on the operator — `IS_NULL`/`IS_NOT_NULL` take none (`[]`), `BETWEEN` takes two (a low and high bound, both inclusive), enumeration-typed fields take two or more, all others take one. A value's `static_value` must be a JSON string even for numeric or date fields — stringify the bound (e.g. `"3.5"`, `"2025-05-15"`); a numeric literal is rejected. `filter_operator` (`AND`/`OR`) joins multiple filters, empty for a single one.
- One query per tool.

## Invoking an agent

`agent get` returns the agent's `deployments[]` inline — read a `deployment_id` there (or from `agentstudio-deployment.sh deployments <package-id>`) and pass it to `session invoke`. The first reply carries a `session_id`; pass it to `session continue` for the next turn.

**Conversation memory is session-scoped.** Within a session the agent retains prior turns and its tool outputs as context; there is no memory setting to configure — the scope is exactly the session. `session invoke` (no `session_id`) starts a fresh conversation with empty memory; `session continue <session_id>` carries that memory into the next turn. To reset an agent's context, start a new session with `invoke` rather than `continue`. Uploaded files are the exception — they are not retained across turns (re-attach them each turn; see **File uploads**).

Every deployment reachable here is a `PRODUCTION` one — the API only deploys agents to Production environments (see **Packaging and deploying an agent**).

## File uploads

An agent can accept file input on a `session invoke` once file uploads are enabled on it via `inference_configuration.file_inference_config` (see **Authoring an agent**). Both conversational and structured agents support files.

Attach files with `session invoke --file <path>` (repeatable) — the script base64-encodes each file, picks `document` vs `image` from the extension, and adds a top-level `files[]` entry:

```
agentstudio-session.sh invoke --deployment <id> --message "Summarize the attached report." --file report.pdf
```

- `--file` composes with `--message` (string message — conversational) or with `--body` (an object message — structured; the files are injected at the top level of the body object). With neither, an empty message is sent (a file-only request).
- Files are **not** carried across turns — re-attach them on every `session continue` where the agent needs them.

**Request shape** (what `--file` builds, and what a `--body` file specifies directly). `files[]` sits at the top level of the request; each entry has exactly one of `document` or `image`:

```json
"files": [
  { "document": { "name": "report.pdf", "format": "pdf", "source": { "bytes": "<base64>" } } },
  { "image":    { "name": "invoice.png", "format": "png", "source": { "bytes": "<base64>" } } }
]
```

- `document.format` — `pdf`, `csv`, `txt`, `docx`, or `xlsx`; `name` required.
- `image.format` — `png`, `jpg`, or `jpeg`; `name` optional.
- `source.bytes` — the base64-encoded file content.
- **Limits:** at most **5 files** per request, **2MB** per file, **10MB** total. Over-limit requests are rejected: too many files → `maximum limit of 5 files per request`; oversized file → a generic `unable to process your request` (HTTP 422, no size-specific message). `--file` enforces the 2MB limit client-side before uploading.

**Runtime gating** (from `file_inference_config`):

- Uploads disabled (`allowed: false`) → the request is **rejected** outright: `Agent does not support file uploads` — file content is never silently dropped.
- A file whose format is not in the agent's `types` allow-list → `File type '<format>' not allowed for this agent`.

**Structured agents** use the same top-level `files[]` (alongside an object `message`); the input schema need not declare a `files` field. Embedding `files` inside the `message` object also works, but prefer the top-level form.

## `<skill-path>` resolution

- Take the absolute path of this SKILL.md and drop `/SKILL.md`. That is `<skill-path>`.
- Verify by running `bash <skill-path>/scripts/agentstudio-env-check.sh` from a workspace with `.env`.
- Treat `<skill-path>` as a fixed value for the session.

## Scripts inventory

All scripts support `--help` (or run with no args) for usage. They emit the raw API response (JSON, or an SSE stream for a conversational `session`) to stdout and errors to stderr.

**Pipeline discipline.** Pipe script output only to standard text filters (`head`, `tail`, `wc`, `grep`). Do **not** pipe to `python3 -c`, `jq -r`, `awk`, or other interpreters with inline code — the harness treats each piped executable as a separate trust boundary and prompts per pipe, defeating the allowlist. If you need a transformation a script doesn't provide, surface the request rather than work around it inline.

**Temp files stay in the project tree.** Write a JSON body (agent definition, structured message) under `active-development/feedback/` — not `/tmp/`. Create it with the **Write** tool, then invoke the script with a separate **Bash** call; do not combine a heredoc and the script call in one compound command.

- `scripts/agentstudio-common.sh` — sourced helper library.
- `scripts/agentstudio-env-check.sh` — verify `.env` and reach the Design API.
- `scripts/agentstudio-agent.sh` — `list | get | create | update` (`list` filters by `--search`, `--status`, and `--has-active-deployments` — agents ready to `session invoke`)
- `scripts/agentstudio-tool.sh` — `list | get | create | update | install | uninstall` (by `--type`, case-insensitive; `list`/`get` cover all types — `get` all but Application; `create`/`update`/`install`/`uninstall` cover Prompt, OpenAPI, Integration, Hub; `list` filters by `--type`, `--status` (a `tool_status` — e.g. `DRAFT` to find not-yet-installed tools), `--source-id`, `--application-name`, and `--search`)
- `scripts/agentstudio-source.sh` — `list | get | mcp-servers | discover | create | update` (write subcommands apply to MCP-server sources only; `list` filters by `--type` MCPServer/acp_source/Application, `--status`, `--search`, `--page`, and elides base64 `application_icon` values by default — `--icons` keeps them, `get` returns the full icon)
- `scripts/agentstudio-deployment.sh` — `environments | packages | deployments | package-create | deploy` (`environments` filters by `--classification PRODUCTION|TEST`, `--status ATTACHED|DETACHED`, and `--source AGENT_GARDEN|INTEGRATION` (`AGENT_GARDEN` = the deployable ones); `deployments` filters server-side by `--search`, `--status ACTIVE|DISABLED`, `--mode conversational|structured`, `--agent`, `--runtime`, `--page`, and is always scoped to `AGENTSTUDIO_ENVIRONMENT_ID`; `deploy` and `package-create --deploy` target `AGENTSTUDIO_ENVIRONMENT_ID` from `.env` — never an inline environment ID)
- `scripts/agentstudio-session.sh` — `invoke | continue` (attach files with repeatable `--file <path>` — base64-encoded and added as top-level `files[]`; see **File uploads**)

Every list subcommand accepts the shared paging/sort flags `--page <n>`, `--page-size <1-100>` (max 100), `--sort-by <field>`, and `--sort-order asc|desc` (default `desc`; the default sort *field* varies by endpoint — `last_updated_on` for agents/tools, `created_on` for packages). `sort_by` field names are not enumerated by the API: `created_on` and `last_updated_on` sort predictably, whereas `name` is accepted but does not produce a flat A–Z order — prefer the timestamp fields when ordering must be predictable. An unrecognized `sort_by` returns `{"success":false,"error":"Invalid sort field: <field>"}` on a 2xx status, so the command still exits 0 — inspect the body, not just the exit code.
