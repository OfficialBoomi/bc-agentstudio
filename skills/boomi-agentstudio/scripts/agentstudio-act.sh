#!/usr/bin/env bash
# Agent Control Tower operations: registry GraphQL and metrics ingestion.

source "$(dirname "$0")/agentstudio-common.sh"

usage() {
  cat <<'EOF'
Usage: agentstudio-act.sh <subcommand> [args]

Subcommands:
  check                                             verify access to the registry
  gql --query <file.graphql> [--variables <file.json>]   read-only; mutations are refused
  create-account --name <name> [--sub-type <AiAgentProviderSubType>]
  create-agent --account <provider-account-id> --name <name>
  publish-alias --agent <agent-id> --name <name>
  register --kind <llm|task|tool|guardrail> --body <file.json>   create one in the registry
  update   --kind <llm|task|tool|guardrail> --body <file.json>   body carries the entity "id"
  unlink   --kind <llm|task|tool|guardrail> --body <file.json>   remove links only
  push-metric --body <file.json>                    body: {"resourceMetrics":[...]}

Reads BOOMI_* from .env. Optional host overrides: AGENTSTUDIO_ACT_AUTH_URL,
AGENTSTUDIO_ACT_GRAPHQL_URL, AGENTSTUDIO_ACT_METRICS_URL.
EOF
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

sub="$1"; shift

load_env
require_env BOOMI_USERNAME BOOMI_API_TOKEN BOOMI_ACCOUNT_ID
require_tools curl jq

ACT_AUTH_URL="${AGENTSTUDIO_ACT_AUTH_URL:-https://api.boomi.com}"
ACT_GRAPHQL_URL="${AGENTSTUDIO_ACT_GRAPHQL_URL:-https://platform.boomi.com/graphql}"
ACT_METRICS_URL="${AGENTSTUDIO_ACT_METRICS_URL:-https://agentcontroltower.boomi.com}"
ACT_ORIGIN="https://boomi-companion.local"

act_metrics_endpoint() {
  echo "${ACT_METRICS_URL%/}/metric-ingestion/v1/${BOOMI_ACCOUNT_ID}/public/metrics"
}

act_fail_http() {
  echo "ERROR: HTTP $RESPONSE_CODE" >&2
  echo "$RESPONSE_BODY" >&2
  if (( RESPONSE_CODE == 401 || RESPONSE_CODE == 403 )); then
    echo "HINT: stop and confirm credentials before retrying. Also check that the hosts match" >&2
    echo "  your platform region and that the account has the AI_AGENT_REGISTRY feature." >&2
  fi
  exit 1
}

# Sets AGENTSTUDIO_BEARER_TOKEN (unexported).
act_mint_jwt() {
  agentstudio_api -H "Accept: */*" "${ACT_AUTH_URL%/}/auth/jwt/generate/${BOOMI_ACCOUNT_ID}"
  if (( RESPONSE_CODE != 200 )); then
    echo "ERROR: JWT mint failed." >&2
    act_fail_http
  fi
  # Fence: xtrace would print the JWT this assignment expands.
  local _xtrace=0
  case $- in *x*) _xtrace=1 ;; esac
  set +x
  AGENTSTUDIO_BEARER_TOKEN=$(printf '%s' "$RESPONSE_BODY" | tr -d '\r\n')
  RESPONSE_BODY=""
  if (( _xtrace )); then set -x; fi
}

act_gql() {
  local query="$1" vars="$2"
  ACT_TMP_BODY=$(mktemp "$_AGENTSTUDIO_TMPDIR/body.XXXXXX")
  if [[ -n "$vars" ]]; then
    jq -n --rawfile q "$query" --slurpfile v "$vars" '{query: $q, variables: $v[0]}' > "$ACT_TMP_BODY"
  else
    jq -n --rawfile q "$query" '{query: $q}' > "$ACT_TMP_BODY"
  fi
  act_mint_jwt
  agentstudio_api_bearer -X POST -H "Content-Type: application/json" -H "Accept: application/json" \
    --data-binary "@$ACT_TMP_BODY" "$ACT_GRAPHQL_URL"
}

# Runs a GraphQL document, prints the response, exits 1 on HTTP or GraphQL errors.
act_run() {
  local op="$1" query="$2" vars="$3"
  act_gql "$query" "$vars"
  if (( RESPONSE_CODE < 200 || RESPONSE_CODE >= 300 )); then
    log_activity "$op" "fail" "$RESPONSE_CODE"
    act_fail_http
  fi
  echo "$RESPONSE_BODY"
  if printf '%s' "$RESPONSE_BODY" | jq -e '.errors' >/dev/null 2>&1; then
    log_activity "$op" "fail" "$RESPONSE_CODE"
    exit 1
  fi
  log_activity "$op" "success" "$RESPONSE_CODE"
}

# Runs one fixed mutation with variables built by the caller into ACT_TMP_VARS.
act_mutate() {
  local op="$1" document="$2"
  ACT_TMP_QUERY=$(mktemp "$_AGENTSTUDIO_TMPDIR/query.XXXXXX")
  printf '%s' "$document" > "$ACT_TMP_QUERY"
  act_run "$op" "$ACT_TMP_QUERY" "$ACT_TMP_VARS"
}

need_arg() {
  [[ -n "$2" ]] || { echo "Need $1" >&2; exit 1; }
}

# Selection set returned by register/update, per kind.
act_entity_fields() {
  case "$1" in
    llm)       echo 'id name description agentVersions { id version }';;
    task)      echo 'id name description taskStatus instructions metaData tags { key value } tools { id name } agentVersions { id version }';;
    tool)      echo 'id name description toolType status toolJson resources { id name resourceType } tags { key value } tasks { id name }';;
    guardrail) echo 'id name description status configurationJson tags { key value } agentVersions { id version }';;
  esac
}

# GraphQL type-name stem per kind.
act_entity_stem() {
  case "$1" in
    llm) echo Llm;; task) echo Task;; tool) echo Tool;; guardrail) echo Guardrail;;
    *) echo "ERROR: --kind must be llm, task, tool, or guardrail" >&2; exit 1;;
  esac
}

# register|update|unlink: the body file is the mutation's input object, sent verbatim.
act_entity_write() {
  local verb="$1"; shift
  local kind="" body=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kind) kind="$2"; shift 2;;
      --body) body="$2"; shift 2;;
      *) echo "Unknown arg: $1" >&2; exit 1;;
    esac
  done
  need_arg "--kind <llm|task|tool|guardrail>" "$kind"
  [[ -z "$body" || ! -f "$body" ]] && { echo "Need --body <file.json>" >&2; exit 1; }
  local stem; stem=$(act_entity_stem "$kind") || exit 1
  jq -e 'type == "object"' "$body" >/dev/null 2>&1 || { echo "ERROR: --body must be a JSON object" >&2; exit 1; }
  if [[ "$verb" != register ]] && ! jq -e '.id | type == "string" and length > 0' "$body" >/dev/null; then
    echo "ERROR: $verb body needs the entity \"id\"" >&2; exit 1
  fi
  ACT_TMP_VARS=$(mktemp "$_AGENTSTUDIO_TMPDIR/vars.XXXXXX")
  jq '{i: .}' "$body" > "$ACT_TMP_VARS"
  local suffix doc
  case "$verb" in
    register) suffix=Create;; update) suffix=Update;; unlink) suffix=Disassociation;;
  esac
  if [[ "$verb" == unlink ]]; then
    doc="mutation(\$i: AiAgent${stem}${suffix}Input!) { aiAgent${stem}${suffix}(input: \$i) }"
  else
    doc="mutation(\$i: AiAgent${stem}${suffix}Input!) { aiAgent${stem}${suffix}(input: \$i) { $(act_entity_fields "$kind") } }"
  fi
  act_mutate "act-${verb}-${kind}" "$doc"
}

case "$sub" in
  check)
    echo "Registry:     $ACT_GRAPHQL_URL"
    echo "Metrics POST: $(act_metrics_endpoint)"
    ACT_TMP_QUERY=$(mktemp "$_AGENTSTUDIO_TMPDIR/query.XXXXXX")
    printf '%s' '{ aiAgentProviderAccounts(input: {pageIndex: 0, pageSize: 1}) { numberOfResults } }' > "$ACT_TMP_QUERY"
    act_gql "$ACT_TMP_QUERY" ""
    if (( RESPONSE_CODE < 200 || RESPONSE_CODE >= 300 )); then act_fail_http; fi
    if printf '%s' "$RESPONSE_BODY" | jq -e '.errors' >/dev/null 2>&1; then
      echo "ERROR: registry query failed:" >&2
      echo "$RESPONSE_BODY" >&2
      exit 1
    fi
    echo "OK — $(printf '%s' "$RESPONSE_BODY" | jq -r '.data.aiAgentProviderAccounts.numberOfResults') provider account(s) visible."
    ;;
  gql)
    query=""; vars=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --query)     query="$2"; shift 2;;
        --variables) vars="$2"; shift 2;;
        *) echo "Unknown arg: $1" >&2; exit 1;;
      esac
    done
    [[ -z "$query" || ! -f "$query" ]] && { echo "Need --query <file.graphql>" >&2; exit 1; }
    [[ -n "$vars" && ! -f "$vars" ]] && { echo "--variables file not found: $vars" >&2; exit 1; }
    if grep -qE '(^|[^A-Za-z0-9_])mutation([^A-Za-z0-9_]|$)' "$query"; then
      echo "ERROR: gql is read-only. Registry writes go through create-account, create-agent, publish-alias, register, update, and unlink." >&2
      exit 1
    fi
    act_run "act-gql" "$query" "$vars"
    ;;
  create-account)
    name=""; subtype=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --name)     name="$2"; shift 2;;
        --sub-type) subtype="$2"; shift 2;;
        *) echo "Unknown arg: $1" >&2; exit 1;;
      esac
    done
    need_arg "--name <name>" "$name"
    ACT_TMP_VARS=$(mktemp "$_AGENTSTUDIO_TMPDIR/vars.XXXXXX")
    jq -n --arg n "$name" --arg t "$subtype" \
      '{i: ({providerType: "CUSTOM", providerAccountName: $n} + (if $t == "" then {} else {providerSubType: $t} end))}' > "$ACT_TMP_VARS"
    act_mutate "act-create-account" \
      'mutation($i: AiAgentProviderAccountCreateInput!) { aiAgentProviderAccountCreate(input: $i) { id providerAccountName providerSubType } }'
    ;;
  create-agent)
    account=""; name=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --account) account="$2"; shift 2;;
        --name)    name="$2"; shift 2;;
        *) echo "Unknown arg: $1" >&2; exit 1;;
      esac
    done
    need_arg "--account <provider-account-id>" "$account"
    need_arg "--name <name>" "$name"
    ACT_TMP_VARS=$(mktemp "$_AGENTSTUDIO_TMPDIR/vars.XXXXXX")
    jq -n --arg a "$account" --arg n "$name" '{i: {providerAccountId: $a, agentName: $n}}' > "$ACT_TMP_VARS"
    act_mutate "act-create-agent" \
      'mutation($i: AiAgentCreateInput!) { aiAgentCreate(input: $i) { id agentVersions { id version agentAliases { id name } } } }'
    ;;
  publish-alias)
    agent=""; name=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --agent) agent="$2"; shift 2;;
        --name)  name="$2"; shift 2;;
        *) echo "Unknown arg: $1" >&2; exit 1;;
      esac
    done
    need_arg "--agent <agent-id>" "$agent"
    need_arg "--name <name>" "$name"
    ACT_TMP_VARS=$(mktemp "$_AGENTSTUDIO_TMPDIR/vars.XXXXXX")
    jq -n --arg a "$agent" --arg n "$name" '{i: {agentId: $a, name: $n}}' > "$ACT_TMP_VARS"
    act_mutate "act-publish-alias" \
      'mutation($i: AiAgentAliasCreateInput!) { aiAgentAliasCreate(input: $i) { id name agentStatus agentVersion { id version } } }'
    ;;
  register|update|unlink)
    act_entity_write "$sub" "$@"
    ;;
  push-metric)
    body=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --body) body="$2"; shift 2;;
        *) echo "Unknown arg: $1" >&2; exit 1;;
      esac
    done
    [[ -z "$body" || ! -f "$body" ]] && { echo "Need --body <file.json>" >&2; exit 1; }
    op="act-push-metric"
    agentstudio_api -X POST -H "Content-Type: application/json" -H "Origin: ${ACT_ORIGIN}" \
      --data-binary "@$body" "$(act_metrics_endpoint)"
    if (( RESPONSE_CODE < 200 || RESPONSE_CODE >= 300 )); then
      log_activity "$op" "fail" "$RESPONSE_CODE"
      act_fail_http
    fi
    log_activity "$op" "success" "$RESPONSE_CODE"
    echo "$RESPONSE_BODY"
    ;;
  *) usage >&2; exit 1;;
esac
