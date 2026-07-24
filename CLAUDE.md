# bc-agentstudio

Notes for developers working on this plugin.

## What's here

A Boomi Companion plugin shipping the `boomi-agentstudio` skill for Boomi Agentstudio (the Agent Garden APIs). See `README.md` for user-facing setup (the `.env` and `.claude/settings.json` contract) and `skills/boomi-agentstudio/` for the skill itself.

`bc-agentstudio` plugin is standalone-installable. If `bc-integration` plugin or `boomi-integration` skill is already setup in the same workspace, the shared `BOOMI_*` Platform credentials are re-used; otherwise they should be set directly in `.env`.

## Architecture

Agent Garden has two API surfaces on separate, region-specific host families: a Design API (`/design/api/v1`) for building and managing agents, and an Execute API (`/execute/api/v1`) for invoking deployed agents. Neither shares a host with the Boomi Platform REST API. The per-skill helper `skills/boomi-agentstudio/scripts/agentstudio-common.sh` provides the two URL builders (`agentstudio_design_url`, `agentstudio_execute_url`) and the shared `agentstudio_api` wrapper.
