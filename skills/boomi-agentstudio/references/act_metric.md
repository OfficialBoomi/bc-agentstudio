# Agent Control Tower metrics

Send usage metrics for a registered custom agent to Agent Control Tower (ACT). The agent must have a published alias first (see [act_registry.md](act_registry.md)).

A metric can never be deleted, and no API removes one. Send test metrics only to a provider account created for testing, never to one whose totals people rely on.

## The Monitoring Spec

Each published alias carries its Monitoring Spec, an OpenAPI spec for metrics ingestion: read `invocationSpecs { protocol spec }` on the alias through `gql`. It gives the endpoint, the `{"resourceMetrics": [...]}` body (one object per agent invocation), and every field. Where it differs from the service, the service wins:

- **`time` is also required** (epoch milliseconds). Ingestion rejects a metric missing `extAccountAliasId`, `sessionId`, or `time` with HTTP 400.
- **`X-Boomi-Api-Token` is not needed.** Use Basic auth in the form the spec's `x-auth` describes: username `BOOMI_TOKEN.<username>`, password the platform API token. Send a non-empty `Origin` header.
- **`providerType` must be an `AiAgentProviderSubType` value**, matching the provider account's `providerSubType`, or be omitted. Free text such as the spec's example is counted for the provider account but excluded when metrics are filtered by provider type.

## Ingestion traps

A `success` response does not mean the metric was counted.

- **`time` more than about a day old** is accepted but never counted, so usage older than a day cannot be sent with its real time. A `time` in the future is rejected (HTTP 400).
- **There is no deduplication.** Re-sending a metric counts it again. The session count is the number of distinct `sessionId` values, so it does not reveal duplicates.
- **A metric without `totalTime` or `modelLatency` counts as 0 in that average.** Send them on every metric or on none.
- **Alias status does not gate ingestion.** Metrics sent to an alias whose `agentStatus` is `INACTIVE` are counted.

Confirm a metric was counted by reading `aiAgentRegistryAggregateMetrics` through `gql`, filtered by `agentIds` and a `requestTsStart`/`requestTsEnd` window around the metric's `time`. Counted metrics appear within a couple of minutes.

## Sending from outside this skill

`agentstudio-act.sh push-metric` is for testing. In production the sender is the agent's own code, or a Boomi integration process that polls the agent platform's usage API (building that process belongs to `boomi-integration`). The user supplies the Basic credentials where the sender runs.

A polling sender must bound each run by a persisted high-water mark, such as the process's last successful run time, and never by a rolling window, because overlapping windows re-send metrics and inflate the counts. Schedule it well inside the one-day `time` limit.
