#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROFILES="${ROOT}/home/.chezmoidata/profiles.json"
SIDECAR_TEMPLATE="${ROOT}/home/private_dot_config/opencode/modify_private_dot_omo-profile.json"
OMO_TEMPLATE="${ROOT}/home/dot_omo/modify_omo.jsonc"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

GPTISH_CATEGORIES=$(cat <<'JSON'
{
  "unspecified-high": {"model": "openai/gpt-6-sol", "reasoning": "high"},
  "unspecified-low": {"model": "openai/gpt-6-luna", "reasoning": "medium"},
  "ultrabrain": {"model": "openai/gpt-6-astra", "reasoning": "high"},
  "deep": {"model": "openai/gpt-6-sol", "reasoning": "high"},
  "quick": {"model": "openai/gpt-6-luna", "reasoning": "low"},
  "visual-engineering": {"model": "openai/gpt-6-sol", "reasoning": "medium"},
  "artistry": {"model": "openai/gpt-5.6-terra", "reasoning": "medium"},
  "writing": {"model": "openai/gpt-5.6-terra", "reasoning": "medium"}
}
JSON
)

GPTISH_AGENTS=$(cat <<'JSON'
{
  "sisyphus": {"model": "openai/gpt-6-sol", "reasoning": "medium"},
  "hephaestus": {"model": "openai/gpt-6-sol", "reasoning": "medium"},
  "oracle": {"model": "openai/gpt-6-sol", "reasoning": "xhigh"},
  "prometheus": {"model": "openai/gpt-6-astra", "reasoning": "xhigh"},
  "metis": {"model": "openai/gpt-6-astra", "reasoning": "max"},
  "momus": {"model": "openai/gpt-6-astra", "reasoning": "xhigh"},
  "atlas": {"model": "openai/gpt-6-luna", "reasoning": "low"},
  "sisyphus-junior": {"model": "openai/gpt-6-sol", "reasoning": "medium"},
  "librarian": {"model": "openai/gpt-6-luna", "reasoning": "low"},
  "explore": {"model": "openai/gpt-6-luna", "reasoning": "low"},
  "multimodal-looker": {"model": "openai/gpt-6-sol", "reasoning": "low"}
}
JSON
)

CLAUDEISH_CATEGORIES=$(cat <<'JSON'
{
  "unspecified-high": {"model": "amazon-bedrock/global.anthropic.claude-opus-5-5", "reasoning": "max"},
  "unspecified-low": {"model": "openai/gpt-6-luna", "reasoning": "medium"},
  "ultrabrain": {"model": "openai/gpt-6-astra", "reasoning": "max"},
  "deep": {"model": "openai/gpt-6-astra", "reasoning": "high"},
  "quick": {"model": "openai/gpt-6-luna", "reasoning": "low"},
  "visual-engineering": {"model": "amazon-bedrock/global.anthropic.claude-fable-5-1", "reasoning": "max"},
  "artistry": {"model": "amazon-bedrock/global.anthropic.claude-fable-5-1", "reasoning": "max"},
  "writing": {"model": "amazon-bedrock/global.anthropic.claude-fable-5-1", "reasoning": "low"}
}
JSON
)

CLAUDEISH_AGENTS=$(cat <<'JSON'
{
  "sisyphus": {"model": "amazon-bedrock/global.anthropic.claude-opus-5-5", "reasoning": "max"},
  "hephaestus": {"model": "openai/gpt-6-sol", "reasoning": "medium"},
  "oracle": {"model": "amazon-bedrock/global.anthropic.claude-opus-5-5", "reasoning": "max"},
  "prometheus": {"model": "amazon-bedrock/global.anthropic.claude-fable-5-1", "reasoning": "xhigh"},
  "metis": {"model": "amazon-bedrock/global.anthropic.claude-fable-5-1", "reasoning": "max"},
  "momus": {"model": "openai/gpt-6-astra", "reasoning": "xhigh"},
  "atlas": {"model": "amazon-bedrock/global.anthropic.claude-sonnet-5"},
  "sisyphus-junior": {"model": "amazon-bedrock/global.anthropic.claude-sonnet-5"},
  "librarian": {"model": "amazon-bedrock/global.anthropic.claude-haiku-4-5-20251001-v1:0", "reasoning": "off"},
  "explore": {"model": "amazon-bedrock/global.anthropic.claude-haiku-4-5-20251001-v1:0", "reasoning": "off"},
  "multimodal-looker": {"model": "openai/gpt-6-sol", "reasoning": "low"}
}
JSON
)

jq -e '.profiles.work.agent_tiers == ["gptish", "claudeish"]' "$PROFILES" >/dev/null ||
  fail "work tiers are not exactly gptish and claudeish"
jq -e '(.profiles.work | has("default") or has("cheap")) | not' "$PROFILES" >/dev/null ||
  fail "legacy work tier keys remain"
jq -e --argjson expected "$GPTISH_CATEGORIES" \
  '.profiles.work.gptish.categories == $expected' "$PROFILES" >/dev/null ||
  fail "gptish categories do not match the requested mapping"
jq -e --argjson expected "$GPTISH_AGENTS" \
  '.profiles.work.gptish.agents == $expected' "$PROFILES" >/dev/null ||
  fail "gptish agents do not match the role-fitting mapping"
jq -e --argjson expected "$CLAUDEISH_CATEGORIES" \
  '.profiles.work.claudeish.categories == $expected' "$PROFILES" >/dev/null ||
  fail "claudeish categories do not match the requested mapping"
jq -e --argjson expected "$CLAUDEISH_AGENTS" \
  '.profiles.work.claudeish.agents == $expected' "$PROFILES" >/dev/null ||
  fail "claudeish agents do not match the role-fitting mapping"
jq -e '
  .profiles.work.model == "amazon-bedrock/global.anthropic.claude-opus-5" and
  (.profiles.work.provider_block["amazon-bedrock"].whitelist | index("global.anthropic.claude-opus-5-5")) != null and
  .profiles.work.provider_block["amazon-bedrock"].models["global.anthropic.claude-opus-5-5"] == {
    "reasoning": true,
    "limit": {"context": 1000000, "output": 128000}
  } and
  .profiles.work.provider_block["amazon-bedrock"].models["global.anthropic.claude-opus-5"] == {
    "limit": {"context": 1000000, "output": 128000}
  }
' "$PROFILES" >/dev/null || fail "Bedrock Opus model registration is incomplete"

TEST_ROOT=$(mktemp -d)
DESTINATION="${TEST_ROOT}/destination"
TEST_HOME="${TEST_ROOT}/home"
DATA="${TEST_ROOT}/data.json"
cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$DESTINATION" "$TEST_HOME/.config/opencode"
jq -n --arg home "$TEST_HOME" \
  '{machineProfile: "work", chezmoi: {homeDir: $home}}' > "$DATA"

render_sidecar() {
  local requested=$1
  jq -nc --arg profile "$requested" '{profile: $profile}' |
    chezmoi execute-template -S "$ROOT" -D "$DESTINATION" \
      --override-data-file "$DATA" --with-stdin -f "$SIDECAR_TEMPLATE"
}

render_omo() {
  local requested=$1
  local existing=${2:-'{}'}
  jq -n --arg profile "$requested" '{profile: $profile}' \
    > "$TEST_HOME/.config/opencode/.omo-profile.json"
  printf '%s\n' "$existing" |
    chezmoi execute-template -S "$ROOT" -D "$DESTINATION" \
      --override-data-file "$DATA" --with-stdin -f "$OMO_TEMPLATE"
}

assert_sidecar_profile() {
  local requested=$1
  local expected=$2
  render_sidecar "$requested" | jq -e --arg expected "$expected" \
    '.profile == $expected and .availableTiers == ["gptish", "claudeish"]' >/dev/null ||
    fail "sidecar migration failed for ${requested}"
}

assert_omo_categories() {
  local requested=$1
  local tier=$2
  local expected
  expected=$(jq -c --arg tier "$tier" '.profiles.work[$tier].categories' "$PROFILES")
  render_omo "$requested" | jq -e --argjson expected "$expected" \
    '.["[opencode]"].categories == $expected' >/dev/null || fail "OMO category selection failed for ${requested}"
  expected=$(jq -c --arg tier "$tier" '.profiles.work[$tier].agents' "$PROFILES")
  render_omo "$requested" | jq -e --argjson expected "$expected" \
    '.["[opencode]"].agents == $expected' >/dev/null || fail "OMO agent selection failed for ${requested}"
}

assert_sidecar_profile default gptish
assert_sidecar_profile cheap claudeish
assert_sidecar_profile gptish gptish
assert_sidecar_profile claudeish claudeish
assert_sidecar_profile unrelated gptish
assert_omo_categories default gptish
assert_omo_categories cheap claudeish
assert_omo_categories gptish gptish
assert_omo_categories claudeish claudeish
assert_omo_categories unrelated gptish

fresh=$(render_omo gptish)
jq -e 'has("codegraph") | not' <<< "$fresh" >/dev/null ||
  fail "invalid OMO config: retired top-level codegraph emitted on fresh render"

existing=$(cat <<'JSON'
{
  "codegraph": {"excluded_roots": ["~/projects/keep"]},
  "$schema": "https://example.invalid/omo.schema.json",
  "_migrations": ["existing-migration"],
  "legacy_migrations": {"completed": true},
  "[opencode]": {
    "disabled_agents": ["oracle"],
    "disabled_skills": ["example-skill"]
  }
}
JSON
)
migrated=$(render_omo gptish "$existing")
jq -e 'has("codegraph") | not' <<< "$migrated" >/dev/null ||
  fail "invalid OMO config: retired top-level codegraph survived existing excluded_roots"
jq -e --argjson input "$existing" '
  .["$schema"] == $input["$schema"] and
  ._migrations == $input._migrations and
  .legacy_migrations == $input.legacy_migrations
' <<< "$migrated" >/dev/null || fail "unrelated OMO top-level metadata was not preserved"
jq -e --argjson input "$existing" '
  .["[opencode]"].disabled_agents == $input["[opencode]"].disabled_agents and
  .["[opencode]"].disabled_skills == $input["[opencode]"].disabled_skills
' <<< "$migrated" >/dev/null || fail "user-owned [opencode] fields were not preserved"

second=$(render_omo gptish "$migrated")
jq -e --argjson first "$migrated" '. == $first and (has("codegraph") | not)' <<< "$second" >/dev/null ||
  fail "OMO render reintroduced codegraph or changed on second render"

printf 'PASS: OMO profile source and migration contract\n'
