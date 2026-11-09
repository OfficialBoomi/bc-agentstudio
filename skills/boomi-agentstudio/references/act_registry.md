# Agent Control Tower registry

Register a custom AI agent in Agent Control Tower (ACT) so its metrics have somewhere to land. Writes go through `agentstudio-act.sh` subcommands. Reads go through `agentstudio-act.sh gql`, which is read-only; introspect a type with `__type(name: "...")` to find its fields.

## Model

A provider account (`providerType: CUSTOM`) holds agents. An agent has one editable DRAFT version and any number of published, numbered versions (v1, v2, …). Aliases point at versions. A published alias's `id` is the `extAccountAliasId` every metric for that agent is addressed to.

`providerSubType` on the provider account takes a value of the `AiAgentProviderSubType` enum. Pick the one naming the agent's framework or platform (e.g. `LANGGRAPH`, `CREWAI`), or `CUSTOM_PROVIDER` when none fits. Metrics carry the same value in `providerType` (see [act_metric.md](act_metric.md)).

## Registering an agent

1. Find the provider account (`aiAgentProviderAccounts` through `gql`), or create one with `create-account`.
2. `create-agent`. This also creates the agent's DRAFT version and a default alias named `TestDeployment` on the DRAFT.
3. Optionally describe the agent: register its LLMs, tasks, tools, and guardrails against the DRAFT (see **Describing an agent**).
4. `publish-alias`. This snapshots the DRAFT as the next numbered version, with status `ACTIVE`, and returns the new alias on it.
5. Send metrics to the returned alias `id`.

Agent names are unique within a provider account; a second `create-agent` with the same name fails with `AI_AGENT_NAME_ALREADY_EXIST`. Anything that registers on every run, such as a scheduled integration, must look the agent up first and create it only when absent. The same applies to LLMs, tasks, tools, and guardrails, whose names are not unique at all.

## Reading the registry

Read an agent with `aiAgent(id: "...") { agentVersions { id version name agentStatus llms { ... } agentTasks { ... tools { ... } } agentGuardrails { ... } agentAliases { id name } } }`. Identify a version by its `version` field (`DRAFT`, `v1`, …); the order of `agentVersions` is not stable. `aiAgentProviderAccount(id) { agents { ... } }` returns empty stubs, so do not read agents through it.

The list queries take `input: { providerAccountId }` and wrap their results:

| Query | Results field | Count field |
|---|---|---|
| `aiAgentLlms` | `llms` | `totalResults` |
| `aiAgentTasks` | `aiAgentTasks` | `numberOfResults` |
| `aiAgentTools` | `aiAgentTools` | `numberOfResults` |
| `aiAgentGuardrails` | `guardrails` | `totalResults` |

## Describing an agent: LLMs, tasks, tools, guardrails

These four entities describe what an agent is built from. Each belongs to a provider account, and each is linked to an agent's DRAFT version. Metrics never reference them (see [act_metric.md](act_metric.md)), so registering them only describes the agent in ACT.

Write them with `register`, `update`, and `unlink`, each taking `--kind llm|task|tool|guardrail --body <file.json>`. The body is the mutation's input object, sent verbatim: `aiAgent<Kind>CreateInput`, `aiAgent<Kind>UpdateInput`, or `aiAgent<Kind>DisassociationInput`.

| Kind | `register` body | Linked through |
|---|---|---|
| `llm` | `providerAccountId`, `name` (required); `description`, `agentIds` | `agentIds` |
| `task` | `providerAccountId`, `name` (required); `description`, `instructions` (string array), `taskMetaData` (string), `tags`, `agentIds`, `agentToolIds` | `agentIds` |
| `tool` | `providerAccountId`, `toolType`, `name` (required); `description`, `toolJson` (string), `resources`, `tags`, `aiAgentTaskIds` | `aiAgentTaskIds` (tasks only) |
| `guardrail` | `providerAccountId`, `name` (required); `description`, `configurationJson` (string), `tags`, `agentIds` | `agentIds` |

- **`agentIds` takes agent IDs, not version IDs.** Each ID resolves to that agent's DRAFT version. An ID that does not exist, or that belongs to another provider account, is rejected (for an LLM, `LLM_INVALID_AGENT_IDS`) and changes nothing.
- **Tools link to tasks, never to an agent.** A tool appears under `agentTasks[].tools`; the version's `agentTools` stays empty. Link a tool from either side: the tool's `aiAgentTaskIds` or the task's `agentToolIds`. A tool can sit on several tasks. A tool body with `agentIds` is rejected.
- **`toolType`:** use `CUSTOM` for a custom agent's tools.
- **The JSON-string fields are free-form.** `toolJson`, `configurationJson`, and `taskMetaData` accept any JSON string, including `"{}"`. An LLM's `name` is free text.
- **Defaults:** a task is `taskStatus: ACTIVE`; a tool and a guardrail are `status: ENABLED`. `tags` entries are `{ "key", "value" }`.
- **Names are not unique.** Registering a name that already exists creates a second entity with a new `id`. Before registering, list the provider account's entities of that kind and reuse a match by `name`.

### Updating

`update` takes the entity's `id` plus only the fields to change; omitted fields keep their values.

- `agentIds`, `aiAgentTaskIds`, and `agentToolIds` **add** links. Existing links stay. To remove one, use `unlink`.
- A task's `instructions` is **replaced** as a whole list. The stored order is not guaranteed to match the order sent, so keep each instruction self-contained.
- `status` (`ENABLED`/`DISABLED`) on a tool or guardrail changes in place and leaves its links intact.
- `update` and `unlink` act on DRAFT entities. Pass the DRAFT entity's `id`, never the `id` of a published snapshot.

### Unlinking

`unlink` removes links and keeps the entity. Its body is `{ "id", "agentIds": [...] }` for `llm`, `task`, and `guardrail`, and `{ "id", "aiAgentTaskIds": [...] }` for `tool`. For a tool, an empty `aiAgentTaskIds` removes it from every task. `unlink` returns `true`. Unlinking affects only the DRAFT; published versions keep their entities.

### Publishing

`publish-alias` snapshots each LLM, task, tool, and guardrail linked to the DRAFT into a **new entity with a new `id`**, attached to the new version. A snapshot tool sits under the snapshot task. On each snapshot, `externalId` is the DRAFT entity's `id`; match published entities to DRAFT entities by `externalId`. A snapshot's `version` (on a guardrail, `externalVersion`) counts that entity's own snapshots, so it can differ from the agent's version number. On DRAFT entities, `externalId` equals `id`.

Register and link everything before `publish-alias`. Changes made to the DRAFT afterwards reach a published version only through the next `publish-alias`.
