#!/usr/bin/env bash
# Invoke a deployed Agentstudio agent (Execute API).

source "$(dirname "$0")/agentstudio-common.sh"

usage() {
  cat <<'EOF'
Usage: agentstudio-session.sh <subcommand> [args]

Subcommands:
  invoke   --deployment <id> [--message <text|@file>] [--file <path>]... [--body <file.json>] [--session <ulid>]
  continue --deployment <id> --session <ulid> [--message <text|@file>] [--file <path>]... [--body <file.json>]

invoke starts a conversation; continue resumes one with the session_id from a
prior reply. --message takes literal text, or @path to read a file. --body supplies
the request JSON (e.g. {"message": {...}} for a structured-agent object message);
deployment_id and session_id are spliced in from --deployment/--session.

--file <path> attaches a file to the request (repeatable). The script base64-
encodes it and adds a top-level files[] entry, picking document vs image from the
extension (document: pdf csv txt docx xlsx; image: png jpg jpeg). The agent must
have file uploads enabled (inference_configuration.file_inference_config.allowed)
and the format must be in its allow-list. Limits: max 5 files, 2MB per file, 10MB
total. --file composes with --message (string message) or with --body (files are
injected at the top level of the body object); with neither, an empty message is
sent (file-only request).

A conversational agent streams its reply as Server-Sent Events (text/event-stream);
a structured agent returns one JSON object. The raw response is emitted on stdout.

Reads BOOMI_* and AGENTSTUDIO_EXECUTE_URL from .env. AGENTSTUDIO_SESSION_TIMEOUT
sets the per-turn timeout in seconds (default 120); a turn that overruns is
aborted and its output discarded.
EOF
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

sub="$1"; shift
case "$sub" in invoke|continue) ;; *) usage >&2; exit 1;; esac
op="session-${sub}"

dep=""; msg=""; body_file=""; session=""; have_msg=0; file_paths=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --deployment) dep="$2"; shift 2;;
    --session)    session="$2"; shift 2;;
    --message)    msg="$2"; have_msg=1; shift 2;;
    --file)       file_paths+=("$2"); shift 2;;
    --body)       body_file="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

[[ -z "$dep" ]] && { echo "Need --deployment <id>" >&2; exit 1; }
[[ "$sub" == "continue" && -z "$session" ]] && { echo "continue needs --session <ulid>" >&2; exit 1; }
if (( have_msg )) && [[ -n "$body_file" ]]; then echo "Use --message or --body, not both" >&2; exit 1; fi
if (( ! have_msg )) && [[ -z "$body_file" ]] && (( ${#file_paths[@]} == 0 )); then
  echo "Need --message <text|@file>, --file <path>, or --body <file.json>" >&2; exit 1
fi

load_env
require_env BOOMI_USERNAME BOOMI_API_TOKEN BOOMI_ACCOUNT_ID AGENTSTUDIO_EXECUTE_URL
require_tools curl
(( ${#file_paths[@]} > 0 )) && require_tools base64

# Session deadline; set after load_env so .env cannot override it.
AGENTSTUDIO_TIMEOUT="${AGENTSTUDIO_SESSION_TIMEOUT:-120}"

url="$(agentstudio_execute_url "session")"

# Build the files[] JSON array from the --file paths.
build_files_json() {
  local out="[" first=1 f ext kind fmt b64 name size total=0
  if (( ${#file_paths[@]} > 5 )); then
    echo "Too many files (${#file_paths[@]}); the limit is 5 per request." >&2; return 1
  fi
  for f in "${file_paths[@]}"; do
    [[ ! -f "$f" ]] && { echo "No such file: $f" >&2; return 1; }
    size=$(wc -c < "$f" | tr -d ' ')
    if (( size > 2097152 )); then
      echo "File exceeds the 2MB per-file limit (${size} bytes): $f" >&2; return 1
    fi
    total=$(( total + size ))
    if (( total > 10485760 )); then
      echo "Files exceed the 10MB total limit (${total} bytes so far)." >&2; return 1
    fi
    ext="$(printf '%s' "${f##*.}" | tr '[:upper:]' '[:lower:]')"
    case "$ext" in
      pdf|csv|txt|docx|xlsx) kind="document"; fmt="$ext" ;;
      png)                   kind="image";    fmt="png" ;;
      jpg)                   kind="image";    fmt="jpg" ;;
      jpeg)                  kind="image";    fmt="jpeg" ;;
      *) echo "Unsupported file type '.$ext' for $f (supported: pdf csv txt docx xlsx png jpg jpeg)" >&2; return 1 ;;
    esac
    b64=$(base64 < "$f" | tr -d '\n\r')
    name="$(json_escape "$(basename "$f")")"
    (( first )) || out+=","
    first=0
    out+="{\"${kind}\":{\"name\":\"${name}\",\"format\":\"${fmt}\",\"source\":{\"bytes\":\"${b64}\"}}}"
  done
  out+="]"
  printf '%s' "$out"
}

# Splice flag-derived top-level fields into a JSON object body:
# deployment_id always; session_id and files when set.
inject_fields_into_body() {
  local body="$1" trimmed core had_extglob=0 inject
  shopt -q extglob && had_extglob=1
  shopt -s extglob
  trimmed="${body##+([[:space:]])}"; trimmed="${trimmed%%+([[:space:]])}"
  (( had_extglob )) || shopt -u extglob
  if [[ "${trimmed:0:1}" != "{" || "${trimmed: -1}" != "}" ]]; then
    echo "--body requires the body to be a single JSON object" >&2; return 1
  fi
  core="${trimmed:1:$(( ${#trimmed} - 2 ))}"
  inject="\"deployment_id\":\"${dep}\""
  [[ -n "$session" ]] && inject+=",\"session_id\":\"${session}\""
  [[ -n "$files_json" ]] && inject+=",\"files\":${files_json}"
  if [[ -z "${core//[[:space:]]/}" ]]; then
    printf '{%s}' "$inject"
  else
    printf '{%s,%s}' "$core" "$inject"
  fi
}

files_json=""
if (( ${#file_paths[@]} > 0 )); then
  files_json="$(build_files_json)" || exit 1
fi

# Send bodies via a temp file, never an inline argv string: a large base64 body would exceed ARG_MAX.
post_body_file() { agentstudio_api -X POST -H "Content-Type: application/json" --data-binary "@$1" "$url"; }
post_body_inline() {
  local tmp rc; tmp=$(mktemp)
  printf '%s' "$1" > "$tmp"
  post_body_file "$tmp" && rc=0 || rc=$?
  rm -f "$tmp"
  return "$rc"
}

if [[ -n "$body_file" ]]; then
  [[ ! -f "$body_file" ]] && { echo "No such file: $body_file" >&2; exit 1; }
  request="$(inject_fields_into_body "$(cat "$body_file")")" || exit 1
  post_body_inline "$request"
else
  if (( have_msg )); then
    [[ "$msg" == @* ]] && { f="${msg#@}"; [[ ! -f "$f" ]] && { echo "No such file: $f" >&2; exit 1; }; msg="$(cat "$f")"; }
  fi
  json="{\"deployment_id\":\"${dep}\""
  [[ -n "$session" ]] && json+=",\"session_id\":\"${session}\""
  json+=",\"message\":\"$(json_escape "$msg")\""
  [[ -n "$files_json" ]] && json+=",\"files\":${files_json}"
  json+="}"
  post_body_inline "$json"
fi

if (( RESPONSE_CODE < 200 || RESPONSE_CODE >= 300 )); then
  [[ -n "${op:-}" ]] && log_activity "$op" "fail" "$RESPONSE_CODE"
  fail_http
fi
[[ -n "${op:-}" ]] && log_activity "$op" "success" "$RESPONSE_CODE"
echo "$RESPONSE_BODY"
