#!/usr/bin/env bash
# Agentstudio deploy lifecycle: environments, packages, deployments (Design API).

source "$(dirname "$0")/agentstudio-common.sh"

AGENTSTUDIO_DEPLOYMENT_STATUSES="ACTIVE DISABLED"
AGENTSTUDIO_AGENT_MODES="conversational structured"
AGENTSTUDIO_ENV_CLASSIFICATIONS="PRODUCTION TEST"
# env_status also accepts DELETED, beyond the ATTACHED/DETACHED shown in usage.
AGENTSTUDIO_ENV_STATUSES="ATTACHED DETACHED DELETED"
AGENTSTUDIO_ENV_SOURCES="AGENT_GARDEN INTEGRATION"

usage() {
  cat <<'EOF'
Usage: agentstudio-deployment.sh <subcommand> [args]

Read:
  environments [--classification PRODUCTION|TEST] [--status ATTACHED|DETACHED]
               [--source AGENT_GARDEN|INTEGRATION]
               [--page <n>] [--page-size <1-100>] [--sort-by <field>] [--sort-order asc|desc]
                                 deploy-target environments; agents deploy and run
                                 only in a PRODUCTION environment (a TEST environment
                                 is rejected), so filter --classification PRODUCTION
                                 to find deploy targets. --source AGENT_GARDEN narrows
                                 to Agent Garden environments (the deployable ones)
  packages [--agent <id>]
           [--page <n>] [--page-size <1-100>] [--sort-by <field>] [--sort-order asc|desc]
                                 all packages, or one agent's packages
  deployments <package-id> [--search <text>] [--status ACTIVE|DISABLED]
              [--mode conversational|structured] [--agent <id>] [--runtime <id>]
              [--page <n>] [--page-size <1-100>] [--sort-by <field>] [--sort-order asc|desc]
                                 deployments of a package; filters narrow the
                                 result server-side (--search matches a substring
                                 of name or agent/deployment ID). Always scoped to
                                 AGENTSTUDIO_ENVIRONMENT_ID from .env

Enum filters (--classification, --status, --mode, --source) are case-insensitive.
Paging: page_size max 100; sort_by field names are not enumerated by the API.

Write:
  package-create <agent-id> [--deploy]
                                 new package; --deploy also deploys it to the
                                 environment set in AGENTSTUDIO_ENVIRONMENT_ID
  deploy <agent-id> --package <package-id>
                                 deploy an existing package to the environment
                                 set in AGENTSTUDIO_ENVIRONMENT_ID

Returns the deployment_id used by agentstudio-session.sh.
The deploy target is fixed to AGENTSTUDIO_ENVIRONMENT_ID in .env and is never
passed as an argument.
Reads BOOMI_*, AGENTSTUDIO_DESIGN_URL, and — for deploy, package-create --deploy,
and deployments — AGENTSTUDIO_ENVIRONMENT_ID from .env.
EOF
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

sub="$1"; shift

load_env
require_env BOOMI_USERNAME BOOMI_API_TOKEN BOOMI_ACCOUNT_ID AGENTSTUDIO_DESIGN_URL
require_tools curl

case "$sub" in
  environments)
    page=""; classification=""; status=""; env_source=""; page_size=""; sort_by=""; sort_order=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --page)           page="$2"; shift 2;;
        --page-size)      page_size="$2"; shift 2;;
        --sort-by)        sort_by="$2"; shift 2;;
        --sort-order)     sort_order="$2"; shift 2;;
        --classification) classification="$2"; shift 2;;
        --status)         status="$2"; shift 2;;
        --source)         env_source="$2"; shift 2;;
        *) echo "Unknown arg: $1" >&2; exit 1;;
      esac
    done
    if [[ -n "$classification" ]]; then
      classification="$(normalize_enum "$classification" $AGENTSTUDIO_ENV_CLASSIFICATIONS)" || {
        echo "ERROR: unknown --classification; expected one of: ${AGENTSTUDIO_ENV_CLASSIFICATIONS}." >&2
        exit 1
      }
    fi
    if [[ -n "$status" ]]; then
      status="$(normalize_enum "$status" $AGENTSTUDIO_ENV_STATUSES)" || {
        echo "ERROR: unknown --status; expected one of: ${AGENTSTUDIO_ENV_STATUSES}." >&2
        exit 1
      }
    fi
    if [[ -n "$env_source" ]]; then
      env_source="$(normalize_enum "$env_source" $AGENTSTUDIO_ENV_SOURCES)" || {
        echo "ERROR: unknown --source; expected one of: ${AGENTSTUDIO_ENV_SOURCES}." >&2
        exit 1
      }
    fi
    paging="$(agentstudio_paging_query "$page" "$page_size" "$sort_by" "$sort_order")" || exit 1
    url="$(agentstudio_design_url "environments")"
    q=""
    [[ -n "$classification" ]] && q+="${q:+&}classification=${classification}"
    [[ -n "$status" ]]         && q+="${q:+&}env_status=${status}"
    [[ -n "$env_source" ]]     && q+="${q:+&}source=${env_source}"
    [[ -n "$paging" ]]         && q+="${q:+&}${paging}"
    [[ -n "$q" ]] && url+="?${q}"
    agentstudio_api -H "Accept: application/json" "$url"
    ;;
  packages)
    agent_id=""; page=""; page_size=""; sort_by=""; sort_order=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --agent)      agent_id="$2"; shift 2;;
        --page)       page="$2"; shift 2;;
        --page-size)  page_size="$2"; shift 2;;
        --sort-by)    sort_by="$2"; shift 2;;
        --sort-order) sort_order="$2"; shift 2;;
        *) echo "Unknown arg: $1" >&2; exit 1;;
      esac
    done
    paging="$(agentstudio_paging_query "$page" "$page_size" "$sort_by" "$sort_order")" || exit 1
    if [[ -n "$agent_id" ]]; then
      url="$(agentstudio_design_url "agents/${agent_id}/packages")"
    else
      url="$(agentstudio_design_url "packages")"
    fi
    [[ -n "$paging" ]] && url+="?${paging}"
    agentstudio_api -H "Accept: application/json" "$url"
    ;;
  deployments)
    [[ -z "${1:-}" ]] && { echo "Need <package-id>" >&2; exit 1; }
    package_id="$1"; shift
    search=""; status=""; mode=""; agent_id=""; runtime_id=""
    page=""; page_size=""; sort_by=""; sort_order=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --search)      search="$2"; shift 2;;
        --status)      status="$2"; shift 2;;
        --mode)        mode="$2"; shift 2;;
        --agent)       agent_id="$2"; shift 2;;
        --runtime)     runtime_id="$2"; shift 2;;
        --page)        page="$2"; shift 2;;
        --page-size)   page_size="$2"; shift 2;;
        --sort-by)     sort_by="$2"; shift 2;;
        --sort-order)  sort_order="$2"; shift 2;;
        *) echo "Unknown arg: $1" >&2; exit 1;;
      esac
    done
    if [[ -n "$status" ]]; then
      status="$(normalize_enum "$status" $AGENTSTUDIO_DEPLOYMENT_STATUSES)" || {
        echo "ERROR: unknown --status; expected one of: ${AGENTSTUDIO_DEPLOYMENT_STATUSES}." >&2
        exit 1
      }
    fi
    if [[ -n "$mode" ]]; then
      mode="$(normalize_enum "$mode" $AGENTSTUDIO_AGENT_MODES)" || {
        echo "ERROR: unknown --mode; expected one of: ${AGENTSTUDIO_AGENT_MODES}." >&2
        exit 1
      }
    fi
    require_env AGENTSTUDIO_ENVIRONMENT_ID
    paging="$(agentstudio_paging_query "$page" "$page_size" "$sort_by" "$sort_order")" || exit 1
    q=""
    [[ -n "$search" ]]         && q+="${q:+&}search_term=$(urlencode "$search")"
    [[ -n "$status" ]]         && q+="${q:+&}deployment_status=${status}"
    [[ -n "$mode" ]]           && q+="${q:+&}agent_mode=${mode}"
    [[ -n "$agent_id" ]]       && q+="${q:+&}agent_id=$(urlencode "$agent_id")"
    q+="${q:+&}environment_id=$(urlencode "$AGENTSTUDIO_ENVIRONMENT_ID")"
    [[ -n "$runtime_id" ]]     && q+="${q:+&}runtime_id=$(urlencode "$runtime_id")"
    [[ -n "$paging" ]]         && q+="${q:+&}${paging}"
    url="$(agentstudio_design_url "packages/${package_id}/deployments")"
    [[ -n "$q" ]] && url+="?${q}"
    agentstudio_api -H "Accept: application/json" "$url"
    ;;
  package-create)
    [[ -z "${1:-}" ]] && { echo "Need <agent-id>" >&2; exit 1; }
    agent_id="$1"; shift
    deploy=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --deploy) deploy=1; shift;;
        *) echo "Unknown arg: $1" >&2; exit 1;;
      esac
    done
    if (( deploy )); then
      require_env AGENTSTUDIO_ENVIRONMENT_ID
      body="{\"deploy_to_environment_id\":\"${AGENTSTUDIO_ENVIRONMENT_ID}\"}"
    else
      body="{}"
    fi
    op="deployment-package-create"
    agentstudio_api -X POST -H "Content-Type: application/json" -H "Accept: application/json" \
      --data-binary "$body" "$(agentstudio_design_url "agents/${agent_id}/packages")"
    ;;
  deploy)
    [[ -z "${1:-}" ]] && { echo "Need <agent-id>" >&2; exit 1; }
    agent_id="$1"; shift
    package_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --package)     package_id="$2"; shift 2;;
        *) echo "Unknown arg: $1" >&2; exit 1;;
      esac
    done
    [[ -z "$package_id" ]] && { echo "Need --package <package-id>" >&2; exit 1; }
    require_env AGENTSTUDIO_ENVIRONMENT_ID
    body="{\"package_id\":\"${package_id}\",\"environment_id\":\"${AGENTSTUDIO_ENVIRONMENT_ID}\"}"
    op="deployment-deploy"
    agentstudio_api -X POST -H "Content-Type: application/json" -H "Accept: application/json" \
      --data-binary "$body" "$(agentstudio_design_url "agents/${agent_id}/deployments")"
    ;;
  *) usage >&2; exit 1;;
esac

if (( RESPONSE_CODE < 200 || RESPONSE_CODE >= 300 )); then
  [[ -n "${op:-}" ]] && log_activity "$op" "fail" "$RESPONSE_CODE"
  fail_http
fi
[[ -n "${op:-}" ]] && log_activity "$op" "success" "$RESPONSE_CODE"
echo "$RESPONSE_BODY"
