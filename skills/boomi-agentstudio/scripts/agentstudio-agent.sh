#!/usr/bin/env bash
# Agentstudio agent operations (Design API).

source "$(dirname "$0")/agentstudio-common.sh"

AGENTSTUDIO_AGENT_STATUSES="DRAFT ACTIVE DISABLED DELETED"

usage() {
  cat <<'EOF'
Usage: agentstudio-agent.sh <subcommand> [args]

Subcommands:
  list [--search <text>] [--status DRAFT|ACTIVE|DISABLED|DELETED] [--has-active-deployments]
       [--page <n>] [--page-size <1-100>] [--sort-by <field>] [--sort-order asc|desc]
  get <agent-id>
  create --body <file.json>            POST the JSON file verbatim
  update <agent-id> --body <file.json> PUT the JSON file verbatim

--status is case-insensitive. --has-active-deployments filters to agents that
have at least one active deployment.

get returns the agent with its deployments[] inline — read deployment_id there
to invoke the agent with agentstudio-session.sh.

create/update bodies require `objective`; omit server-assigned read-only fields
(id, created_on, last_updated_on, unique_name, deployments, packages_count,
installed_on) when mirroring a fetched agent.

Reads BOOMI_* and AGENTSTUDIO_DESIGN_URL from .env.
EOF
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

sub="$1"; shift

load_env
require_env BOOMI_USERNAME BOOMI_API_TOKEN BOOMI_ACCOUNT_ID AGENTSTUDIO_DESIGN_URL
require_tools curl

case "$sub" in
  list)
    search=""; status=""; has_active=""; page=""; page_size=""; sort_by=""; sort_order=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --search)                  search="$2"; shift 2;;
        --status)                  status="$2"; shift 2;;
        --has-active-deployments)  has_active=1; shift;;
        --page)                    page="$2"; shift 2;;
        --page-size)               page_size="$2"; shift 2;;
        --sort-by)                 sort_by="$2"; shift 2;;
        --sort-order)              sort_order="$2"; shift 2;;
        *) echo "Unknown arg: $1" >&2; exit 1;;
      esac
    done
    if [[ -n "$status" ]]; then
      status="$(normalize_enum "$status" $AGENTSTUDIO_AGENT_STATUSES)" || {
        echo "ERROR: unknown --status; expected one of: ${AGENTSTUDIO_AGENT_STATUSES}." >&2
        exit 1
      }
    fi
    paging="$(agentstudio_paging_query "$page" "$page_size" "$sort_by" "$sort_order")" || exit 1
    q=""
    [[ -n "$search" ]]     && q+="${q:+&}search_term=$(urlencode "$search")"
    [[ -n "$status" ]]     && q+="${q:+&}agent_status=${status}"
    [[ -n "$has_active" ]] && q+="${q:+&}has_active_deployments=true"
    [[ -n "$paging" ]]     && q+="${q:+&}${paging}"
    url="$(agentstudio_design_url "agents")"
    [[ -n "$q" ]] && url+="?${q}"
    agentstudio_api -H "Accept: application/json" "$url"
    ;;
  get)
    [[ -z "${1:-}" ]] && { echo "Need <agent-id>" >&2; exit 1; }
    agentstudio_api -H "Accept: application/json" "$(agentstudio_design_url "agents/$1")"
    ;;
  create)
    body=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --body) body="$2"; shift 2;;
        *) echo "Unknown arg: $1" >&2; exit 1;;
      esac
    done
    [[ -z "$body" || ! -f "$body" ]] && { echo "Need --body <file.json>" >&2; exit 1; }
    op="agent-create"
    agentstudio_api -X POST -H "Content-Type: application/json" -H "Accept: application/json" \
      --data-binary "@$body" "$(agentstudio_design_url "agents")"
    ;;
  update)
    id=""; body=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --body) body="$2"; shift 2;;
        -*) echo "Unknown arg: $1" >&2; exit 1;;
        *) id="$1"; shift;;
      esac
    done
    [[ -z "$id" ]] && { echo "Need <agent-id>" >&2; exit 1; }
    [[ -z "$body" || ! -f "$body" ]] && { echo "Need --body <file.json>" >&2; exit 1; }
    op="agent-update"
    agentstudio_api -X PUT -H "Content-Type: application/json" -H "Accept: application/json" \
      --data-binary "@$body" "$(agentstudio_design_url "agents/${id}")"
    ;;
  *) usage >&2; exit 1;;
esac

if (( RESPONSE_CODE < 200 || RESPONSE_CODE >= 300 )); then
  [[ -n "${op:-}" ]] && log_activity "$op" "fail" "$RESPONSE_CODE"
  fail_http
fi
[[ -n "${op:-}" ]] && log_activity "$op" "success" "$RESPONSE_CODE"
echo "$RESPONSE_BODY"
