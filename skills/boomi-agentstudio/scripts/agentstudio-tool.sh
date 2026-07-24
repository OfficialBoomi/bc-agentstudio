#!/usr/bin/env bash
# Agentstudio tools (Design API): list/get, create/update, install/uninstall.

source "$(dirname "$0")/agentstudio-common.sh"

AGENTSTUDIO_TOOL_TYPES="Integration Hub Prompt MCP OpenAPI Application"
# Types with create/update/install/uninstall paths.
AGENTSTUDIO_TOOL_WRITE_TYPES="Integration Hub Prompt OpenAPI"
AGENTSTUDIO_TOOL_STATUSES="DRAFT ACTIVE DISABLED STALE NOT_AVAILABLE"

usage() {
  cat <<'EOF'
Usage: agentstudio-tool.sh <subcommand> [args]

Subcommands:
  list [--type <type>] [--status <status>] [--search <text>]
       [--source-id <id>] [--application-name <name>]
       [--page <n>] [--page-size <1-100>] [--sort-by <field>] [--sort-order asc|desc]
  get       --type <type> <tool-id>
  create    --type <type> --body <file.json>            POST the JSON file verbatim
  update    --type <type> <tool-id> --body <file.json>  PUT the JSON file verbatim
  install   --type <type> <tool-id>                     activate a tool (status -> ACTIVE)
  uninstall --type <type> <tool-id>                     deactivate a tool (status -> DISABLED)

<type> is case-insensitive, one of: Integration, Hub, Prompt, MCP, OpenAPI, Application.
'get' supports every type except Application (Application tools have no get path).
create/update/install/uninstall accept only: Integration, Hub, Prompt, OpenAPI.

list filters narrow the result server-side: --status is a tool_status, case-
insensitive, one of DRAFT, ACTIVE, DISABLED, STALE, NOT_AVAILABLE; --source-id
and --application-name restrict to one tool source / application.
--application-name matches the whole value (case-insensitive, not a prefix or
substring), so pass the exact application name.

A newly created tool lands in DRAFT. A DRAFT tool can be attached to an agent,
but the agent can't be packaged until every referenced tool is installed (ACTIVE).
create/update bodies omit server-assigned read-only fields (id, created_on,
last_updated_on, created_by, last_updated_by, last_used_on, installed_on,
pre_installed, provider_name, provider_id, unique_name, tool_status, type).

An OpenAPI (API) tool's authentication (None, token_auth, basic_auth, platform_jwt,
oauth) follows the same doctrine as MCP-server sources: provision secret-bearing
tools in the Boomi console and reference them by id; None/platform_jwt need no
secret. See SKILL.md "Authenticating sources and tools".

create requires the AGENT_CREATE privilege; install/uninstall require AGENT_INSTALL.

Reads BOOMI_* and AGENTSTUDIO_DESIGN_URL from .env.
EOF
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

# Normalize a write-capable type and echo its lowercase path segment; non-zero if invalid.
tool_write_seg() {
  local t
  t="$(normalize_enum "$1" $AGENTSTUDIO_TOOL_WRITE_TYPES)" || {
    echo "ERROR: unknown --type for writes; expected one of: ${AGENTSTUDIO_TOOL_WRITE_TYPES}." >&2
    echo "  (MCP tools are managed via agentstudio-source.sh; Application tools are read-only.)" >&2
    return 1
  }
  printf '%s' "$t" | tr '[:upper:]' '[:lower:]'
}

sub="$1"; shift

load_env
require_env BOOMI_USERNAME BOOMI_API_TOKEN BOOMI_ACCOUNT_ID AGENTSTUDIO_DESIGN_URL
require_tools curl

case "$sub" in
  list)
    type=""; status=""; search=""; source_id=""; app_name=""; page=""; page_size=""; sort_by=""; sort_order=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --type)             type="$2"; shift 2;;
        --status)           status="$2"; shift 2;;
        --search)           search="$2"; shift 2;;
        --source-id)        source_id="$2"; shift 2;;
        --application-name) app_name="$2"; shift 2;;
        --page)             page="$2"; shift 2;;
        --page-size)        page_size="$2"; shift 2;;
        --sort-by)          sort_by="$2"; shift 2;;
        --sort-order)       sort_order="$2"; shift 2;;
        *) echo "Unknown arg: $1" >&2; exit 1;;
      esac
    done
    if [[ -n "$type" ]]; then
      type="$(normalize_enum "$type" $AGENTSTUDIO_TOOL_TYPES)" || {
        echo "ERROR: unknown --type; expected one of: ${AGENTSTUDIO_TOOL_TYPES}." >&2
        exit 1
      }
    fi
    if [[ -n "$status" ]]; then
      status="$(normalize_enum "$status" $AGENTSTUDIO_TOOL_STATUSES)" || {
        echo "ERROR: unknown --status; expected one of: ${AGENTSTUDIO_TOOL_STATUSES}." >&2
        exit 1
      }
    fi
    paging="$(agentstudio_paging_query "$page" "$page_size" "$sort_by" "$sort_order")" || exit 1
    q=""
    [[ -n "$type" ]]      && q+="${q:+&}tool_type=${type}"
    [[ -n "$status" ]]    && q+="${q:+&}tool_status=${status}"
    [[ -n "$search" ]]    && q+="${q:+&}search_term=$(urlencode "$search")"
    [[ -n "$source_id" ]] && q+="${q:+&}source_id=$(urlencode "$source_id")"
    [[ -n "$app_name" ]]  && q+="${q:+&}application_name=$(urlencode "$app_name")"
    [[ -n "$paging" ]]    && q+="${q:+&}${paging}"
    url="$(agentstudio_design_url "tools")"
    [[ -n "$q" ]] && url+="?${q}"
    agentstudio_api -H "Accept: application/json" "$url"
    ;;
  get)
    [[ "${1:-}" != "--type" || -z "${2:-}" ]] && { echo "Need --type <type>" >&2; exit 1; }
    type="$(normalize_enum "$2" $AGENTSTUDIO_TOOL_TYPES)" || {
      echo "ERROR: unknown --type; expected one of: ${AGENTSTUDIO_TOOL_TYPES}." >&2
      exit 1
    }
    shift 2
    if [[ "$type" == "Application" ]]; then
      echo "ERROR: Application tools have no get path; use 'list --type Application' to enumerate them." >&2
      exit 1
    fi
    [[ -z "${1:-}" ]] && { echo "Need <tool-id>" >&2; exit 1; }
    # the get path segment is lowercase
    seg="$(printf '%s' "$type" | tr '[:upper:]' '[:lower:]')"
    agentstudio_api -H "Accept: application/json" "$(agentstudio_design_url "tools/${seg}/$1")"
    ;;
  create)
    type=""; body=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --type) type="$2"; shift 2;;
        --body) body="$2"; shift 2;;
        *) echo "Unknown arg: $1" >&2; exit 1;;
      esac
    done
    [[ -z "$type" ]] && { echo "Need --type <type>" >&2; exit 1; }
    [[ -z "$body" || ! -f "$body" ]] && { echo "Need --body <file.json>" >&2; exit 1; }
    seg="$(tool_write_seg "$type")" || exit 1
    op="tool-create"
    agentstudio_api -X POST -H "Content-Type: application/json" -H "Accept: application/json" \
      --data-binary "@$body" "$(agentstudio_design_url "tools/${seg}")"
    ;;
  update)
    type=""; body=""; id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --type) type="$2"; shift 2;;
        --body) body="$2"; shift 2;;
        -*) echo "Unknown arg: $1" >&2; exit 1;;
        *) id="$1"; shift;;
      esac
    done
    [[ -z "$type" ]] && { echo "Need --type <type>" >&2; exit 1; }
    [[ -z "$id" ]] && { echo "Need <tool-id>" >&2; exit 1; }
    [[ -z "$body" || ! -f "$body" ]] && { echo "Need --body <file.json>" >&2; exit 1; }
    seg="$(tool_write_seg "$type")" || exit 1
    op="tool-update"
    agentstudio_api -X PUT -H "Content-Type: application/json" -H "Accept: application/json" \
      --data-binary "@$body" "$(agentstudio_design_url "tools/${seg}/${id}")"
    ;;
  install|uninstall)
    type=""; id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --type) type="$2"; shift 2;;
        -*) echo "Unknown arg: $1" >&2; exit 1;;
        *) id="$1"; shift;;
      esac
    done
    [[ -z "$type" ]] && { echo "Need --type <type>" >&2; exit 1; }
    [[ -z "$id" ]] && { echo "Need <tool-id>" >&2; exit 1; }
    seg="$(tool_write_seg "$type")" || exit 1
    op="tool-${sub}"
    agentstudio_api -X POST -H "Accept: application/json" \
      "$(agentstudio_design_url "tools/${seg}/${id}/${sub}")"
    ;;
  *) usage >&2; exit 1;;
esac

if (( RESPONSE_CODE < 200 || RESPONSE_CODE >= 300 )); then
  [[ -n "${op:-}" ]] && log_activity "$op" "fail" "$RESPONSE_CODE"
  fail_http
fi
[[ -n "${op:-}" ]] && log_activity "$op" "success" "$RESPONSE_CODE"
echo "$RESPONSE_BODY"
