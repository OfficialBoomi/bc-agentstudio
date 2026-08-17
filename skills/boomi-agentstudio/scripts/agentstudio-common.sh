#!/usr/bin/env bash
# Shared utilities for boomi-agentstudio CLI tools; sourced, not executed directly.

set -euo pipefail

# --- Environment ---

load_env() {
  local env_file=".env"
  if [[ -f "$env_file" ]]; then
    # Fence: xtrace would print every assignment in .env, token included.
    local _xtrace=0
    case $- in *x*) _xtrace=1 ;; esac
    set +x
    # No `set -a` — values stay unexported. See CLAUDE.md.
    source "$env_file"
    if (( _xtrace )); then set -x; fi
    _set_user_agent   # .env must not override the header
  else
    echo "ERROR: .env file not found in $(pwd)" >&2
    exit 1
  fi
}

# The skill's only `${!name}` site — fenced so xtrace can't print the value.
env_is_set() {
  local _xtrace=0
  case $- in *x*) _xtrace=1 ;; esac
  set +x
  local _rc=0
  [[ -n "${!1:-}" ]] || _rc=1
  if (( _xtrace )); then set -x; fi
  return "$_rc"
}

require_env() {
  local missing=()
  local var
  for var in "$@"; do
    if ! env_is_set "$var"; then
      missing+=("$var")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required environment variables: ${missing[*]}" >&2
    echo "Check your .env file." >&2
    exit 1
  fi
}

require_tools() {
  local missing=()
  for tool in "$@"; do
    if ! command -v "$tool" &>/dev/null; then
      missing+=("$tool")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required tools: ${missing[*]}" >&2
    exit 1
  fi
}

# --- Argument handling ---

# Pass the full arg vector before load_env so --help works after the subcommand.
help_requested() {
  local arg
  for arg in "$@"; do
    case "$arg" in --help|-h) usage; exit 0 ;; esac
  done
}

# Minimal JSON escaping for a string's contents (no surrounding quotes).
json_escape() {
  local s="$1" code c esc
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  # Escape any remaining C0 control chars (0x01-0x1F, minus the named ones above) as \u00XX.
  for code in 1 2 3 4 5 6 7 8 11 12 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31; do
    printf -v c '%b' "\\$(printf '%03o' "$code")"
    if [[ "$s" == *"$c"* ]]; then
      printf -v esc '\\u%04x' "$code"
      s="${s//$c/$esc}"
    fi
  done
  printf '%s' "$s"
}

# --- Enum normalization ---

# Echo the allowed value matching `input` case-insensitively; non-zero if none match.
normalize_enum() {
  local input="$1"; shift
  local want canon
  want="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"
  for canon in "$@"; do
    if [[ "$want" == "$(printf '%s' "$canon" | tr '[:upper:]' '[:lower:]')" ]]; then
      echo "$canon"; return 0
    fi
  done
  return 1
}

# --- Paging / sorting ---

AGENTSTUDIO_SORT_ORDERS="asc desc"

# Validate page/page_size/sort_by/sort_order and echo them as a URL query fragment.
agentstudio_paging_query() {
  local page="$1" page_size="$2" sort_by="$3" sort_order="$4" q=""
  if [[ -n "$page" ]]; then
    if [[ ! "$page" =~ ^[0-9]+$ ]] || (( page < 1 )); then
      echo "ERROR: --page must be a positive integer (1 or greater)." >&2; return 1
    fi
  fi
  if [[ -n "$page_size" ]]; then
    if [[ ! "$page_size" =~ ^[0-9]+$ ]] || (( page_size < 1 || page_size > 100 )); then
      echo "ERROR: --page-size must be an integer between 1 and 100." >&2; return 1
    fi
  fi
  if [[ -n "$sort_order" ]]; then
    sort_order="$(normalize_enum "$sort_order" $AGENTSTUDIO_SORT_ORDERS)" || {
      echo "ERROR: unknown --sort-order; expected one of: ${AGENTSTUDIO_SORT_ORDERS}." >&2; return 1
    }
  fi
  [[ -n "$page" ]]       && q+="${q:+&}page=${page}"
  [[ -n "$page_size" ]]  && q+="${q:+&}page_size=${page_size}"
  [[ -n "$sort_by" ]]    && q+="${q:+&}sort_by=$(urlencode "$sort_by")"
  [[ -n "$sort_order" ]] && q+="${q:+&}sort_order=${sort_order}"
  printf '%s' "$q"
}

# Percent-encode a string for use as a URL query value.
urlencode() {
  local LC_ALL=C s="$1" i c hex out=""
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      *) printf -v hex '%02X' "'$c"; out+="%${hex: -2}" ;;
    esac
  done
  printf '%s' "$out"
}

# --- Version ---

_skill_version() {
  cat "$(dirname "${BASH_SOURCE[0]}")/../VERSION" 2>/dev/null || echo "unknown"
}

# --- Constants ---

# Skill name is a literal — standalone installs may rename the directory.
# A function because load_env re-calls it after sourcing .env, so the
# User-Agent cannot be poisoned.
_set_user_agent() {
  AGENTSTUDIO_USER_AGENT="boomi-companion/boomi-agentstudio/$(_skill_version)"
}
_set_user_agent

# --- Activity logging ---

_activity_log_dir() {
  echo "$(pwd)/.activity-log"
}

# Opt-in via BOOMI_COMPANION_LOG_ACTIVITY=1 in .env. Default is off.
log_activity() {
  [[ "${BOOMI_COMPANION_LOG_ACTIVITY:-0}" == "1" ]] || return 0

  local operation="$1"
  local result="$2"
  local http_code="${3:-}"
  local details="${4:-}"
  [[ -z "$details" ]] && details="{}"

  {
    local log_dir
    log_dir="$(_activity_log_dir)"
    mkdir -p "$log_dir" 2>/dev/null || return 0

    local log_file="${log_dir}/activity.jsonl"
    local timestamp
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local script_name
    script_name="$(basename "${BASH_SOURCE[1]:-unknown}" .sh)"

    jq -cn \
      --arg ts "$timestamp" \
      --arg name "boomi-agentstudio" \
      --arg ver "$(_skill_version)" \
      --arg ws "$(basename "$(pwd)")" \
      --arg op "$operation" \
      --arg script "$script_name" \
      --arg user "${USER:-}" \
      --arg boomi_user "${BOOMI_USERNAME:-}" \
      --arg account "${BOOMI_ACCOUNT_ID:-}" \
      --arg result "$result" \
      --arg http "$http_code" \
      --argjson details "$details" \
      '{
        timestamp: $ts,
        skill_name: $name,
        skill_version: $ver,
        workspace: $ws,
        operation: $op,
        script: $script,
        user: $user,
        boomi_user: $boomi_user,
        account_id: $account,
        result: $result,
        http_code: (if $http == "" then null else ($http | tonumber? // $http) end),
        details: $details
      }' >> "$log_file"
  # The 2>/dev/null also fences xtrace around the BOOMI_USERNAME expansion.
  } 2>/dev/null || true
}

# --- URL builders ---

# Design API URL; `endpoint` is the part after /design/api/v1/<accountId>/.
agentstudio_design_url() {
  echo "${AGENTSTUDIO_DESIGN_URL%/}/design/api/v1/${BOOMI_ACCOUNT_ID}/$1"
}

# Execute API URL; `endpoint` is the part after /execute/api/v1/<accountId>/.
agentstudio_execute_url() {
  echo "${AGENTSTUDIO_EXECUTE_URL%/}/execute/api/v1/${BOOMI_ACCOUNT_ID}/$1"
}

# --- API helper ---

# Emits curl config directives for `curl -K -`, keeping credentials out of argv.
# Usage: curl_cfg user "u:p"
curl_cfg() {
  (( $# % 2 == 0 )) || { echo "ERROR: curl_cfg needs directive/value pairs" >&2; return 1; }
  local val
  while [[ $# -gt 1 ]]; do
    # Backslash first, so the escapes added below aren't doubled.
    val="$2"
    val="${val//\\/\\\\}"
    val="${val//\"/\\\"}"
    val="${val//$'\t'/\\t}"
    val="${val//$'\r'/\\r}"
    val="${val//$'\n'/\\n}"
    printf '%s = "%s"\n' "$1" "$val"
    shift 2
  done
}

# Sets RESPONSE_BODY and RESPONSE_CODE. Always Basic auth with Platform creds.
RESPONSE_BODY=""
RESPONSE_CODE=""
agentstudio_api() {
  # Fence: xtrace would print the token the next assignment expands.
  local _xtrace=0
  case $- in *x*) _xtrace=1 ;; esac
  set +x

  local userpass="BOOMI_TOKEN.${BOOMI_USERNAME}:${BOOMI_API_TOKEN}"

  local cfg
  cfg=$(curl_cfg user "$userpass") || {
    echo "ERROR: could not build the curl auth config." >&2
    if (( _xtrace )); then set -x; fi
    return 1
  }

  local timeout="${AGENTSTUDIO_TIMEOUT:-60}"

  local tmpfile
  tmpfile=$(mktemp)

  # Run curl without errexit so connection failures return, not abort.
  local rc
  set +e
  RESPONSE_CODE=$(printf '%s\n' "$cfg" \
    | curl -s \
        --max-time "$timeout" \
        -A "$AGENTSTUDIO_USER_AGENT" \
        -K - \
        -o "$tmpfile" -w "%{http_code}" \
        "$@")
  rc=$?
  set -e
  RESPONSE_BODY=$(cat "$tmpfile")
  rm -f "$tmpfile"

  # `if`, not `&&` — a false `&&` tail returns 1 and trips a caller's set -e.
  if (( _xtrace )); then set -x; fi

  if (( rc != 0 )) || [[ -z "$RESPONSE_CODE" || "$RESPONSE_CODE" == "000" ]]; then
    # Pull the request URL out of the args so the hint can name the offending host.
    local target_url="" target_host="" arg
    for arg in "$@"; do
      case "$arg" in http://*|https://*) target_url="$arg" ;; esac
    done
    target_host="${target_url#*://}"; target_host="${target_host%%/*}"
    case "$rc" in
      6)
        echo "ERROR: DNS could not resolve host '${target_host:-?}' (curl exit 6)." >&2
        echo "  This is a bad hostname, not a network outage — verify the host in" >&2
        echo "  AGENTSTUDIO_DESIGN_URL / AGENTSTUDIO_EXECUTE_URL." >&2
        ;;
      7)
        echo "ERROR: connection refused by '${target_host:-?}' (curl exit 7)." >&2
        echo "  The host resolved but rejected the connection — check the port/scheme or a proxy." >&2
        ;;
      28)
        echo "ERROR: request to '${target_host:-?}' timed out after ${timeout}s (curl exit 28)." >&2
        echo "  Likely a slow network, VPN, or an unresponsive host." >&2
        ;;
      *)
        echo "ERROR: could not reach the Agent Garden API — network or connection failure (curl exit ${rc})." >&2
        echo "  Likely a request timeout, DNS failure, refused connection, or no network. No HTTP" >&2
        echo "  response was received, so the request may or may not have reached the server." >&2
        ;;
    esac
    return 1
  fi
  return 0
}

# Region/privilege hint for 401/403 responses.
agentstudio_auth_hint() {
  echo "HINT: verify the host in AGENTSTUDIO_DESIGN_URL / AGENTSTUDIO_EXECUTE_URL matches your" >&2
  echo "  console region — Design US datalake-prod / UK datalake-uk-prod (ANZ/JP use US);" >&2
  echo "  Execute US c01-usa-east / UK c01-gbr / ANZ c01-aus / JP c01-jp — and that your" >&2
  echo "  token carries AGENT_GARDEN_ACCESS and AGENT_VIEW (AGENT_INTERACT for session)." >&2
}

# Print the response on stderr and exit; hint at region/privilege on auth failures.
fail_http() {
  echo "ERROR: HTTP $RESPONSE_CODE" >&2
  echo "$RESPONSE_BODY" >&2
  if (( RESPONSE_CODE == 401 || RESPONSE_CODE == 403 )); then
    agentstudio_auth_hint
  fi
  exit 1
}
