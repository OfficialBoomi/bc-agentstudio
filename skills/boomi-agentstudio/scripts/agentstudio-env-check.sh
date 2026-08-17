#!/usr/bin/env bash
# Verify .env vars and reach the Agent Garden Design API; Execute host is informational.

source "$(dirname "$0")/agentstudio-common.sh"

usage() {
  cat <<'EOF'
Usage: agentstudio-env-check.sh [--help]

Reports three things:
  - Design API (required)    fails if missing or unreachable
  - Deploy target (optional) reports whether AGENTSTUDIO_ENVIRONMENT_ID is set and
                             confirms it resolves to an ATTACHED PRODUCTION
                             Agent Garden environment
  - Execute API (optional)   reports whether AGENTSTUDIO_EXECUTE_URL is set and
                             suggests the value to add when it is not
EOF
}
help_requested "$@"

load_env
require_env BOOMI_USERNAME BOOMI_API_TOKEN BOOMI_ACCOUNT_ID AGENTSTUDIO_DESIGN_URL
require_tools curl

echo "=== Design API (required) ==="
for v in BOOMI_USERNAME BOOMI_API_TOKEN BOOMI_ACCOUNT_ID AGENTSTUDIO_DESIGN_URL; do
  # env_is_set, not `${!v}` — by-name expansion lives in that helper.
  if env_is_set "$v"; then echo "  $v=SET"; else echo "  $v=UNSET"; fi
done

url="$(agentstudio_design_url "environments?page_size=1")"
echo "  GET $url"
# Tolerate connection failure so the FAIL line reports it.
agentstudio_api -H "Accept: application/json" "$url" || true

if (( RESPONSE_CODE < 200 || RESPONSE_CODE >= 300 )); then
  echo "  HTTP $RESPONSE_CODE — FAIL" >&2
  echo "  Response: $RESPONSE_BODY" >&2
  if (( RESPONSE_CODE == 401 || RESPONSE_CODE == 403 )); then
    agentstudio_auth_hint
  fi
  exit 1
fi
echo "  HTTP $RESPONSE_CODE — OK (authenticated as ${BOOMI_USERNAME})"

echo
echo "=== Deploy target environment (optional) ==="
if [[ -n "${AGENTSTUDIO_ENVIRONMENT_ID:-}" ]]; then
  echo "  AGENTSTUDIO_ENVIRONMENT_ID=SET (${AGENTSTUDIO_ENVIRONMENT_ID})"
  # Confirm it is an ATTACHED PRODUCTION Agent Garden environment (a valid deploy target).
  vurl="$(agentstudio_design_url "environments?classification=PRODUCTION&source=AGENT_GARDEN&env_status=ATTACHED&page_size=100")"
  agentstudio_api -H "Accept: application/json" "$vurl" || true
  if (( RESPONSE_CODE < 200 || RESPONSE_CODE >= 300 )); then
    echo "  Could not verify (HTTP $RESPONSE_CODE listing deploy targets)." >&2
  elif printf '%s' "$RESPONSE_BODY" | grep -Eq "\"ag_environment_id\"[[:space:]]*:[[:space:]]*\"${AGENTSTUDIO_ENVIRONMENT_ID}\""; then
    echo "  OK — resolves to an ATTACHED PRODUCTION Agent Garden environment."
  else
    echo "  WARNING: not found among ATTACHED PRODUCTION Agent Garden environments." >&2
    echo "  Agents deploy and run only in such an environment — list valid targets with" >&2
    echo "  'agentstudio-deployment.sh environments --classification PRODUCTION --source AGENT_GARDEN'" >&2
    echo "  and set AGENTSTUDIO_ENVIRONMENT_ID to a target's ag_environment_id." >&2
  fi
else
  echo "  AGENTSTUDIO_ENVIRONMENT_ID=UNSET — required by 'agentstudio-deployment.sh' deploy,"
  echo "  package-create --deploy, and deployments. Set it to the ag_environment_id of your"
  echo "  deploy target; list targets with:"
  echo "    agentstudio-deployment.sh environments --classification PRODUCTION --source AGENT_GARDEN"
fi

echo
echo "=== Execute API (optional) ==="
if [[ -n "${AGENTSTUDIO_EXECUTE_URL:-}" ]]; then
  echo "  AGENTSTUDIO_EXECUTE_URL=SET (${AGENTSTUDIO_EXECUTE_URL})"
  echo "  Not test-called here — a session invoke consumes an agent turn. Run a real"
  echo "  'agentstudio-session.sh invoke' to confirm it end to end."
else
  echo "  AGENTSTUDIO_EXECUTE_URL=UNSET — required only for 'agentstudio-session.sh'."
  case "$AGENTSTUDIO_DESIGN_URL" in
    *datalake-uk-prod*) suggested="https://c01-gbr.ai-agent-garden.boomi.com" ;;
    *datalake-prod*)    suggested="https://c01-usa-east.ai-agent-garden.boomi.com" ;;
    *)                  suggested="" ;;
  esac
  if [[ -n "$suggested" ]]; then
    echo "  To enable it, add this line to .env:"
    echo "    AGENTSTUDIO_EXECUTE_URL=${suggested}"
  else
    echo "  Add AGENTSTUDIO_EXECUTE_URL with your region's Execute host to enable it."
  fi
  echo "  Execute hosts by region: US c01-usa-east, UK c01-gbr, ANZ c01-aus, JP c01-jp"
  echo "  (each <host>.ai-agent-garden.boomi.com). ANZ/JP share the US Design host, so the"
  echo "  suggestion above assumes US — override it with your region's Execute host if needed."
fi
