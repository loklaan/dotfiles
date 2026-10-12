#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROFILES="${ROOT}/home/.chezmoidata/profiles.json"
SIDECAR_TEMPLATE="${ROOT}/home/private_dot_config/opencode/modify_private_dot_omo-profile.json"
OMO_TEMPLATE="${ROOT}/home/dot_omo/modify_omo.jsonc"
OPENCODE_TEMPLATE="${ROOT}/home/private_dot_config/opencode/modify_opencode.json"
OPENCODE2_TEMPLATE="${ROOT}/home/private_dot_config/opencode2/modify_opencode.json"
SYNC_TEMPLATE="${ROOT}/home/.chezmoiscripts/run_after_install-067-sync-opencode-plugins.sh.tmpl"
WORK_PLUGIN_V2="example-work-plugin"
WORK_PLUGIN_REPO="/path/to/plugin-repo"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

GPTISH_CATEGORIES=$(cat <<'JSON'
{
  "unspecified-high": {"model": "openai/gpt-6.1-sol", "reasoning": "high"},
  "unspecified-low": {"model": "openai/gpt-6-luna", "reasoning": "medium"},
  "ultrabrain": {"model": "openai/gpt-6-astra", "reasoning": "high"},
  "deep": {"model": "openai/gpt-6.1-sol", "reasoning": "high"},
  "quick": {"model": "openai/gpt-6-luna", "reasoning": "low"},
  "visual-engineering": {"model": "openai/gpt-6.1-sol", "reasoning": "medium"},
  "artistry": {"model": "openai/gpt-5.6-terra", "reasoning": "medium"},
  "writing": {"model": "openai/gpt-5.6-terra", "reasoning": "medium"}
}
JSON
)

GPTISH_AGENTS=$(cat <<'JSON'
{
  "sisyphus": {"model": "openai/gpt-6.1-sol", "reasoning": "medium"},
  "hephaestus": {"model": "openai/gpt-6.1-sol", "reasoning": "medium"},
  "oracle": {"model": "openai/gpt-6.1-sol", "reasoning": "xhigh"},
  "prometheus": {"model": "openai/gpt-6-astra", "reasoning": "xhigh"},
  "metis": {"model": "openai/gpt-6-astra", "reasoning": "max"},
  "momus": {"model": "openai/gpt-6-astra", "reasoning": "xhigh"},
  "atlas": {"model": "openai/gpt-6-luna", "reasoning": "low"},
  "sisyphus-junior": {"model": "openai/gpt-6.1-sol", "reasoning": "medium"},
  "librarian": {"model": "openai/gpt-6-luna", "reasoning": "low"},
  "explore": {"model": "openai/gpt-6-luna", "reasoning": "low"},
  "multimodal-looker": {"model": "openai/gpt-6.1-sol", "reasoning": "low"}
}
JSON
)

CLAUDEISH_CATEGORIES=$(cat <<'JSON'
{
  "unspecified-high": {"model": "amazon-bedrock/global.anthropic.claude-opus-5-5", "reasoning": "max"},
  "unspecified-low": {"model": "amazon-bedrock/global.anthropic.claude-haiku-5-5", "reasoning": "max"},
  "ultrabrain": {"model": "openai/gpt-6-astra", "reasoning": "max"},
  "deep": {"model": "openai/gpt-6-astra", "reasoning": "high"},
  "quick": {"model": "amazon-bedrock/global.anthropic.claude-haiku-5-5", "reasoning": "max"},
  "visual-engineering": {"model": "amazon-bedrock/global.anthropic.claude-opus-5-5", "reasoning": "max"},
  "artistry": {"model": "amazon-bedrock/global.anthropic.claude-opus-5-5", "reasoning": "max"},
  "writing": {"model": "amazon-bedrock/global.anthropic.claude-opus-5-5", "reasoning": "high"}
}
JSON
)

CLAUDEISH_AGENTS=$(cat <<'JSON'
{
  "sisyphus": {"model": "amazon-bedrock/global.anthropic.claude-opus-5-5", "reasoning": "max"},
  "hephaestus": {"model": "openai/gpt-6.1-sol", "reasoning": "medium"},
  "oracle": {"model": "amazon-bedrock/global.anthropic.claude-opus-5-5", "reasoning": "max"},
  "prometheus": {"model": "amazon-bedrock/global.anthropic.claude-opus-5-5", "reasoning": "max"},
  "metis": {"model": "amazon-bedrock/global.anthropic.claude-opus-5-5", "reasoning": "max"},
  "momus": {"model": "openai/gpt-6-astra", "reasoning": "xhigh"},
  "atlas": {"model": "amazon-bedrock/global.anthropic.claude-sonnet-5-5"},
  "sisyphus-junior": {"model": "amazon-bedrock/global.anthropic.claude-sonnet-5-5"},
  "librarian": {"model": "amazon-bedrock/global.anthropic.claude-haiku-5-5", "reasoning": "max"},
  "explore": {"model": "amazon-bedrock/global.anthropic.claude-haiku-5-5", "reasoning": "max"},
  "multimodal-looker": {"model": "openai/gpt-6.1-sol", "reasoning": "low"}
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
  .profiles.work.model == "amazon-bedrock/global.anthropic.claude-opus-5-5" and
  (.profiles.work.provider_block["amazon-bedrock"].whitelist | index("global.anthropic.claude-opus-5-5")) != null and
  .profiles.work.provider_block["amazon-bedrock"].models == {
    "global.anthropic.claude-opus-5-5": {
      "reasoning": true,
      "limit": {"context": 1000000, "output": 128000}
    },
    "global.anthropic.claude-haiku-5-5": {
      "reasoning": true,
      "limit": {"context": 100000, "output": 32000}
    }
  }
' "$PROFILES" >/dev/null || fail "Bedrock Opus and Haiku model registration is incomplete"
jq -e '
  .profiles.work.provider_block["amazon-bedrock"] as $bedrock |
  $bedrock.models | keys | all(. as $id | $bedrock.whitelist | index($id) != null)
' "$PROFILES" >/dev/null || fail "a Bedrock model override targets a model that is not whitelisted"
jq -e '[.profiles[] | .. | strings | select(test("gpt-[^/]*-(fast|flex|ultrafast)$"))] == []' \
  "$PROFILES" >/dev/null ||
  fail "a pin uses an OpenCode service-tier alias (-fast/-flex/-ultrafast), which Coder boxes do not list"
jq -e '
  .profiles.work as $work |
  $work.provider_block["amazon-bedrock"].whitelist as $whitelist |
  [$work.model, ($work.agent_tiers[] as $tier | $work[$tier] | (.agents, .categories) | .[] | .model // empty)] |
  map(select(startswith("amazon-bedrock/")) | ltrimstr("amazon-bedrock/")) |
  all(. as $id | $whitelist | index($id) != null)
' "$PROFILES" >/dev/null || fail "a pinned amazon-bedrock model is missing from the work whitelist"

TEST_ROOT=$(mktemp -d)
DESTINATION="${TEST_ROOT}/destination"
TEST_HOME="${TEST_ROOT}/home"
DATA="${TEST_ROOT}/data.json"
EMPTY_CONFIG="${TEST_ROOT}/chezmoi-empty.json"
cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$DESTINATION" "$TEST_HOME/.config/opencode"
printf '{}\n' > "$EMPTY_CONFIG"
jq -n --arg home "$TEST_HOME" \
  '{machineProfile: "work", chezmoi: {homeDir: $home}}' > "$DATA"

render_sidecar() {
  local requested=$1
  jq -nc --arg profile "$requested" '{profile: $profile}' |
    chezmoi execute-template --config "$EMPTY_CONFIG" -S "$ROOT" -D "$DESTINATION" \
      --override-data-file "$DATA" --with-stdin -f "$SIDECAR_TEMPLATE"
}

render_omo() {
  local requested=$1
  local existing=${2:-'{}'}
  jq -n --arg profile "$requested" '{profile: $profile}' \
    > "$TEST_HOME/.config/opencode/.omo-profile.json"
  printf '%s\n' "$existing" |
    chezmoi execute-template --config "$EMPTY_CONFIG" -S "$ROOT" -D "$DESTINATION" \
      --override-data-file "$DATA" --with-stdin -f "$OMO_TEMPLATE"
}

render_opencode2() {
  local plugin=$1
  local existing=${2:-'{}'}
  local data="${TEST_ROOT}/data-opencode2.json"
  jq -n --arg home "$TEST_HOME" --arg plugin "$plugin" \
    '{machineProfile: "work", openCodeWorkPluginV2: $plugin, chezmoi: {homeDir: $home}}' \
    > "$data"
  printf '%s\n' "$existing" |
    chezmoi execute-template --config "$EMPTY_CONFIG" -S "$ROOT" -D "$DESTINATION" \
      --override-data-file "$data" --with-stdin -f "$OPENCODE2_TEMPLATE"
}

render_work_plugin() {
  local template=$1
  local overrides=$2
  local existing=${3:-'{}'}
  local data="${TEST_ROOT}/data-work-plugin.json"
  jq -n --arg home "$TEST_HOME" --argjson overrides "$overrides" '
    {machineProfile: "work", openCodeWorkPlugin: "example-work-plugin@latest",
     npmWorkRegistry: "https://registry.example.invalid/",
     bwsTokenPath: ($home + "/missing-token"), chezmoi: {homeDir: $home}} + $overrides
  ' > "$data"
  printf '%s\n' "$existing" |
    chezmoi execute-template --config "$EMPTY_CONFIG" -S "$ROOT" -D "$DESTINATION" \
      --override-data-file "$data" --with-stdin -f "$template"
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

BEDROCK_LIMITS=$(jq -c '
  .profiles.work.provider_block["amazon-bedrock"].models |
  with_entries(select(.value | has("limit")) | .value = {limit: .value.limit})
' "$PROFILES")

with_plugin=$(render_opencode2 "$WORK_PLUGIN_V2")
jq -e --argjson limits "$BEDROCK_LIMITS" '
  .providers["amazon-bedrock"] == {models: $limits} and
  .providers["amazon-bedrock"].models["global.anthropic.claude-haiku-5-5"].limit.context == 100000 and
  (.enabled_providers | index("amazon-bedrock")) != null
' <<< "$with_plugin" >/dev/null ||
  fail "OpenCode 2 does not carry the Bedrock model limits when the work plugin admits Bedrock"

without_plugin=$(render_opencode2 "")
jq -e '
  (.providers // {} | has("amazon-bedrock") | not) and
  .enabled_providers == [] and
  (has("plugins") | not)
' <<< "$without_plugin" >/dev/null ||
  fail "OpenCode 2 emits Bedrock config while the work plugin lever is empty"

cleared=$(render_opencode2 "" "$with_plugin")
jq -e --argjson expected "$without_plugin" '. == $expected' <<< "$cleared" >/dev/null ||
  fail "OpenCode 2 kept Bedrock config after the work plugin lever was cleared"

stale=$(jq '.providers["amazon-bedrock"].models["global.anthropic.claude-retired"] = {limit: {context: 1, output: 1}}' \
  <<< "$with_plugin")
reapplied=$(render_opencode2 "$WORK_PLUGIN_V2" "$stale")
jq -e --argjson first "$with_plugin" '. == $first' <<< "$reapplied" >/dev/null ||
  fail "OpenCode 2 kept a model limit the profile no longer declares, or changed on second render"

printf 'PASS: OMO profile source, migration, and OpenCode 2 model limit contract\n'

# Both entry points come from the repo, even when the legacy levers are set.
EXPECTED_PROVIDERS=$(jq -c '.profiles.work.enabled_providers | sort' "$PROFILES")
for explicit in '{}' \
  '{"openCodeWorkPluginLocalPath":"/path/to/old-plugin/dist/index.js","openCodeWorkPluginV2":" example-work-plugin-v2@latest "}'; do
  repo_set=$(jq -c --arg repo "$WORK_PLUGIN_REPO" '. + {openCodeWorkPluginRepo: $repo}' <<< "$explicit")
  repo_empty=$(jq -c '. + {openCodeWorkPluginRepo: ""}' <<< "$explicit")
  v1=$(render_work_plugin "$OPENCODE_TEMPLATE" "$repo_set")
  v2=$(render_work_plugin "$OPENCODE2_TEMPLATE" "$repo_set")
  jq -e --arg repo "$WORK_PLUGIN_REPO" '
    .plugin == [($repo + "/packages/opencode-plugin/dist/index.js"), "oh-my-openagent@latest"]
  ' <<< "$v1" >/dev/null || fail "repo override did not select the V1 monorepo entry"
  jq -e --arg repo "$WORK_PLUGIN_REPO" --argjson providers "$EXPECTED_PROVIDERS" '
    .plugins == [($repo + "/packages/opencode2-plugin/dist")] and
    .enabled_providers == $providers
  ' <<< "$v2" >/dev/null || fail "repo override did not select the V2 entry and admit proxied providers"

  fallback_v1=$(render_work_plugin "$OPENCODE_TEMPLATE" "$repo_empty")
  fallback_v2=$(render_work_plugin "$OPENCODE2_TEMPLATE" "$repo_empty")
  jq -e --argjson explicit "$explicit" '
    .plugin == [($explicit.openCodeWorkPluginLocalPath // "example-work-plugin@latest"), "oh-my-openagent@latest"]
  ' <<< "$fallback_v1" >/dev/null || fail "empty repo changed the explicit V1 entry or published fallback"
  jq -e --argjson explicit "$explicit" '
    if $explicit | has("openCodeWorkPluginV2") then
      .plugins == [($explicit.openCodeWorkPluginV2 | gsub("^\\s+|\\s+$"; ""))]
    else has("plugins") | not end
  ' <<< "$fallback_v2" >/dev/null || fail "empty repo changed the explicit V2 entry or its whitespace trimming"

  for template in "$OPENCODE_TEMPLATE" "$OPENCODE2_TEMPLATE" "$SYNC_TEMPLATE"; do
    render_work_plugin "$template" "$explicit" > "${TEST_ROOT}/absent"
    render_work_plugin "$template" "$repo_empty" > "${TEST_ROOT}/empty"
    cmp -s "${TEST_ROOT}/absent" "${TEST_ROOT}/empty" ||
      fail "empty and absent repo render differently: ${template}"
    if [ "$template" != "$SYNC_TEMPLATE" ]; then
      selected=$(render_work_plugin "$template" "$repo_set")
      render_work_plugin "$template" "$repo_set" "$selected" > "${TEST_ROOT}/reapplied"
      render_work_plugin "$template" "$repo_set" > "${TEST_ROOT}/selected"
      cmp -s "${TEST_ROOT}/selected" "${TEST_ROOT}/reapplied" ||
        fail "repo override is not idempotent: ${template}"
      render_work_plugin "$template" "$repo_empty" "$selected" > "${TEST_ROOT}/restored"
      cmp -s "${TEST_ROOT}/empty" "${TEST_ROOT}/restored" ||
        fail "clearing repo did not restore the explicit keys: ${template}"
    fi
  done
done
printf 'PASS: work plugin repo paths, precedence, empty/absent fallback, re-render, and rollback\n'

# Positive control: published caches are still busted when neither local lever is set.
render_work_plugin "$SYNC_TEMPLATE" '{}' > "${TEST_ROOT}/sync-published.sh"
grep -Fx "tcs_bust_opencode_plugin \"\$packages_dir\" \"@canva/opencode-plugin-llmproxy@latest\"" \
  "${TEST_ROOT}/sync-published.sh" >/dev/null || fail "published work plugin cache bust is missing"
grep -Fx "tcs_bust_opencode_plugin \"\$packages_dir\" \"@canva/opencode-plugin-llmproxy\"" \
  "${TEST_ROOT}/sync-published.sh" >/dev/null || fail "legacy work plugin cache bust is missing"
render_work_plugin "$SYNC_TEMPLATE" "$(jq -nc --arg repo "$WORK_PLUGIN_REPO" '{openCodeWorkPluginRepo: $repo}')" \
  > "${TEST_ROOT}/sync-repo.sh"
if grep -F '@canva/opencode-plugin-llmproxy' "${TEST_ROOT}/sync-repo.sh" >/dev/null; then
  fail "repo override still busts published work plugin caches"
fi
grep -Fx "tcs_bust_opencode_plugin \"\$packages_dir\" \"oh-my-openagent@latest\"" \
  "${TEST_ROOT}/sync-repo.sh" >/dev/null || fail "repo override suppressed the unrelated OMO cache bust"
for script in "${TEST_ROOT}/sync-published.sh" "${TEST_ROOT}/sync-repo.sh"; do
  bash -n "$script"
done
printf 'PASS: work plugin repo skips published cache busting without suppressing OMO\n'

# --init only simulates config-template rendering; never run chezmoi init/apply.
# Load the value from an actual temporary config [data], not override-data.
for data in '{}' '{"openCodeWorkPluginRepo":""}' \
  '{"openCodeWorkPluginRepo":"/path/to/plugin-repo"}'; do
  jq -n --argjson data "$data" '{data: $data}' > "${TEST_ROOT}/chezmoi-init.json"
  chezmoi execute-template --init --no-tty --config "${TEST_ROOT}/chezmoi-init.json" \
    -S "$ROOT" -D "$DESTINATION" -f "${ROOT}/home/.chezmoi.toml.tmpl" > "${TEST_ROOT}/config.toml"
  expected=$(jq -r '"  openCodeWorkPluginRepo = " + (.openCodeWorkPluginRepo // "" | tojson)' <<< "$data")
  [ "$(grep -Fxc "$expected" "${TEST_ROOT}/config.toml")" = 1 ] ||
    fail "config-template rendering did not preserve/default the repo key as one editable line"
done
chezmoi execute-template --config "$EMPTY_CONFIG" -S "$ROOT" -D "$DESTINATION" \
  '{{ includeTemplate "opencode-work-plugin-tmpl" (dict) }}' |
  jq -e '. == {v1Local: "", v2: ""}' >/dev/null || fail "shared plugin template requires an optional key"
printf 'PASS: config-template repo persistence and missing-key fleet safety\n'
