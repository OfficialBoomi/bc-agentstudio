#!/usr/bin/env bash
# Agentstudio tool sources (Design API). Read all source types; create/update for
# MCPServer sources. Application/acp_source sources are read-only here.

source "$(dirname "$0")/agentstudio-common.sh"

AGENTSTUDIO_SOURCE_TYPES="MCPServer acp_source Application"
AGENTSTUDIO_SOURCE_STATUSES="DRAFT ACTIVE DISABLED STALE NOT_AVAILABLE"

usage() {
  cat <<'EOF'
Usage: agentstudio-source.sh <subcommand> [args]

Subcommands:
  list [--type <type>] [--status <status>] [--search <text>] [--icons]
       [--page <n>] [--page-size <1-100>] [--sort-by <field>] [--sort-order asc|desc]
                             all tool sources, with optional filters
  get <source-id>            an Application source by id
  mcp-servers [<server-id>]  list MCP servers, or get one by id; a get returns the
                             server's imported tools by default (list accepts the
                             --page/--page-size/--sort-by/--sort-order flags)
  discover --body <file.json>            probe an MCP server's tools without saving it
  create --body <file.json>              POST a new MCP server, importing its tools
  update <server-id> --body <file.json>  PUT changes to an MCP server

--type is case-insensitive, one of: MCPServer, acp_source, Application.
--status is case-insensitive, one of: DRAFT, ACTIVE, DISABLED, STALE, NOT_AVAILABLE.

A source is the application or MCP server that tools are discovered from; it is
distinct from a tool. The Design API exposes source writes only for MCP servers:
create/update apply to MCP servers; `get` reads an Application source and
`mcp-servers` reads MCP servers (Application/acp_source are read-only).

create/update/discover bodies require `name`, `url`, and `transport_type` (SSE or
HTTP); `create` also requires `description`. Other optional fields: title, headers.
authentication types: token_auth, basic_auth, platform_jwt, oauth.
Secret-bearing servers (token_auth/basic_auth/oauth) are best provisioned in the
Boomi console and referenced by id, so credentials stay out of the conversation;
platform_jwt needs no secret. discover does not persist anything; create saves
the server and imports its tools.

'list' elides application_icon by default; pass --icons to keep them, or use
'get <source-id>' for the full icon.

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
    elide_icons=1
    type=""; status=""; search=""; page=""; page_size=""; sort_by=""; sort_order=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --icons)      elide_icons=0; shift;;
        --type)       type="$2"; shift 2;;
        --status)     status="$2"; shift 2;;
        --search)     search="$2"; shift 2;;
        --page)       page="$2"; shift 2;;
        --page-size)  page_size="$2"; shift 2;;
        --sort-by)    sort_by="$2"; shift 2;;
        --sort-order) sort_order="$2"; shift 2;;
        *) echo "Unknown arg: $1" >&2; exit 1;;
      esac
    done
    if [[ -n "$type" ]]; then
      type="$(normalize_enum "$type" $AGENTSTUDIO_SOURCE_TYPES)" || {
        echo "ERROR: unknown --type; expected one of: ${AGENTSTUDIO_SOURCE_TYPES}." >&2
        exit 1
      }
    fi
    if [[ -n "$status" ]]; then
      status="$(normalize_enum "$status" $AGENTSTUDIO_SOURCE_STATUSES)" || {
        echo "ERROR: unknown --status; expected one of: ${AGENTSTUDIO_SOURCE_STATUSES}." >&2
        exit 1
      }
    fi
    paging="$(agentstudio_paging_query "$page" "$page_size" "$sort_by" "$sort_order")" || exit 1
    q=""
    [[ -n "$type" ]]   && q+="${q:+&}source_type=${type}"
    [[ -n "$status" ]] && q+="${q:+&}source_status=${status}"
    [[ -n "$search" ]] && q+="${q:+&}search_term=$(urlencode "$search")"
    [[ -n "$paging" ]] && q+="${q:+&}${paging}"
    url="$(agentstudio_design_url "sources/tools")"
    [[ -n "$q" ]] && url+="?${q}"
    agentstudio_api -H "Accept: application/json" "$url"
    ;;
  get)
    [[ -z "${1:-}" ]] && { echo "Need <source-id>" >&2; exit 1; }
    agentstudio_api -H "Accept: application/json" "$(agentstudio_design_url "sources/tools/application/$1")"
    ;;
  mcp-servers)
    if [[ -n "${1:-}" && "$1" != --* ]]; then
      agentstudio_api -H "Accept: application/json" "$(agentstudio_design_url "sources/tools/mcp-servers/$1")"
    else
      page=""; page_size=""; sort_by=""; sort_order=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --page)       page="$2"; shift 2;;
          --page-size)  page_size="$2"; shift 2;;
          --sort-by)    sort_by="$2"; shift 2;;
          --sort-order) sort_order="$2"; shift 2;;
          *) echo "Unknown arg: $1" >&2; exit 1;;
        esac
      done
      paging="$(agentstudio_paging_query "$page" "$page_size" "$sort_by" "$sort_order")" || exit 1
      url="$(agentstudio_design_url "sources/tools/mcp-servers")"
      [[ -n "$paging" ]] && url+="?${paging}"
      agentstudio_api -H "Accept: application/json" "$url"
    fi
    ;;
  discover)
    body=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --body) body="$2"; shift 2;;
        *) echo "Unknown arg: $1" >&2; exit 1;;
      esac
    done
    [[ -z "$body" || ! -f "$body" ]] && { echo "Need --body <file.json>" >&2; exit 1; }
    agentstudio_api -X POST -H "Content-Type: application/json" -H "Accept: application/json" \
      --data-binary "@$body" "$(agentstudio_design_url "sources/tools/mcp-servers/discover-tools")"
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
    op="source-create"
    agentstudio_api -X POST -H "Content-Type: application/json" -H "Accept: application/json" \
      --data-binary "@$body" "$(agentstudio_design_url "sources/tools/mcp-servers")"
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
    [[ -z "$id" ]] && { echo "Need <server-id>" >&2; exit 1; }
    [[ -z "$body" || ! -f "$body" ]] && { echo "Need --body <file.json>" >&2; exit 1; }
    op="source-update"
    agentstudio_api -X PUT -H "Content-Type: application/json" -H "Accept: application/json" \
      --data-binary "@$body" "$(agentstudio_design_url "sources/tools/mcp-servers/${id}")"
    ;;
  *) usage >&2; exit 1;;
esac

if (( RESPONSE_CODE < 200 || RESPONSE_CODE >= 300 )); then
  [[ -n "${op:-}" ]] && log_activity "$op" "fail" "$RESPONSE_CODE"
  fail_http
fi
[[ -n "${op:-}" ]] && log_activity "$op" "success" "$RESPONSE_CODE"

if [[ "${elide_icons:-0}" == 1 ]]; then
  echo "$RESPONSE_BODY" \
    | sed 's|"application_icon":[[:space:]]*"[^"]*"|"application_icon":"<elided; use source get>"|g'
else
  echo "$RESPONSE_BODY"
fi
