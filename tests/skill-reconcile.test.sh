#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

# Guards the df-skills reconcile envelope contract in the skills lifecycle
# script. A boundary's health is true, false, or null, and null means the
# boundary was not observed, which counts as healthy. Linux renders packages as
# null because it builds no packs. SKILL_RECONCILE_SCRIPT=<file> runs the cases
# against another revision of the script.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="${SKILL_RECONCILE_SCRIPT:-${ROOT}/home/.chezmoiscripts/run_after_install-060-reconcile-skills.sh.tmpl}"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[ -f "$SCRIPT" ] || fail "missing lifecycle script: ${SCRIPT}"

test_root=$(mktemp -d)
cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

home="${test_root}/home"
mkdir -p "${home}/.local/lib" "${home}/.config/dotfiles" "${test_root}/bin"
cp "${ROOT}/home/private_dot_local/lib/bash-logging.sh" "${home}/.local/lib/bash-logging.sh"
printf '{}\n' > "${home}/.config/dotfiles/skill-lifecycle.json"

# The script runs under a temporary HOME, where a mise shim would try to
# reinstall jq. Put the real binary ahead of it.
jq_bin=$(mise which jq 2>/dev/null || command -v jq) || fail "jq is not on PATH"
ln -s "$jq_bin" "${test_root}/bin/jq"

cat > "${test_root}/bin/df-skills" <<'SHIM'
#!/usr/bin/env bash
cat "$SKILL_RECONCILE_TEST_ENVELOPE"
SHIM
chmod +x "${test_root}/bin/df-skills"

# Shaped like a Linux reconcile envelope: packages and reference unobserved.
base='{
  "manifestDigest": "0000000000000000000000000000000000000000000000000000000000000000",
  "sources": {"example:skill": {"healthy": true, "error": null, "message": null}},
  "providers": {},
  "registry": {"healthy": true, "error": null, "message": null},
  "packages": {"healthy": null, "error": null, "message": null},
  "reference": {"healthy": null, "error": null, "message": null},
  "pendingOwnership": null,
  "healthy": true,
  "reconcileHealthy": true
}'
envelope="${test_root}/envelope.json"

# run_case <name> <jq transform of the base envelope> <exit status> <output>
# The logging variables make the script log as a nested session, so it never
# discovers and appends to a real chezmoi session log.
run_case() {
  local name=$1 transform=$2 expected_status=$3 expected_output=$4
  local output status=0
  "$jq_bin" "$transform" <<< "$base" > "$envelope"
  output=$(HOME="$home" PATH="${test_root}/bin:${PATH}" \
    BASH_LOGGING_ACTIVE=1 BASH_LOGGING_FILE="${test_root}/session.log" \
    SKILL_RECONCILE_TEST_ENVELOPE="$envelope" \
    "$BASH" "$SCRIPT" 2>&1) || status=$?
  [ "$status" -eq "$expected_status" ] ||
    fail "${name}: exit ${status}, expected ${expected_status}: ${output}"
  case "$output" in
    *"$expected_output"*) ;;
    *) fail "${name}: output lacks '${expected_output}': ${output}" ;;
  esac
}

run_case "unobserved packages" '.' 0 "Reconciled: 1 sources"
run_case "package drift deferred to packaging" '.packages.healthy = false' 0 "Reconciled: 1 sources"
run_case "unobserved registry" '.registry.healthy = null' 0 "Reconciled: 1 sources"
run_case "failed registry" '.registry.healthy = false | .reconcileHealthy = false' 1 "reported a failure"
run_case "missing packages boundary" 'del(.packages)' 1 "malformed JSON"
run_case "missing packages health" 'del(.packages.healthy)' 1 "malformed JSON"
run_case "non-boolean packages health" '.packages.healthy = "true"' 1 "malformed JSON"

printf 'PASS: skill reconcile envelope contract\n'
