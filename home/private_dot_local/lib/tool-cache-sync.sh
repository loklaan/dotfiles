#!/usr/bin/env bash
# tool-cache-sync.sh — bridge mise-resolved versions into tool-private plugin
# caches. Designed to be sourced from chezmoi run_onchange_ scripts paired
# with bash-logging.sh.
#
# OpenCode's plugin cache (~/Library/Caches/opencode/ on macOS, ~/.cache/opencode/
# on Linux) has a package.json + bun.lock managed by opencode's embedded bun
# at startup. The cache is "sticky" — once node_modules/ is populated,
# opencode does not re-resolve on package.json changes alone, so plugins
# pinned to "@latest" freeze on whatever version was first installed.
#
# This library bridges that gap by writing directly into the cache's
# node_modules/ via npm (which is already pinned via mise as part of node).
# We deliberately do NOT depend on bun here, even though opencode embeds it
# internally — the bundled bun isn't exposed as a CLI, and pinning a
# separate external bun in mise just to populate node_modules/ would be
# redundant tooling. npm writes to node_modules/ in a layout opencode's
# bun reads happily on next startup.

tcs_require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    warning "▶ tool-cache-sync"
    warning "╍ ${cmd} not found, skipping"
    return 1
  fi
  return 0
}

tcs_get_opencode_cache() {
  if ! command -v opencode >/dev/null 2>&1; then
    warning "▶ tool-cache-sync"
    warning "╍ opencode not found"
    return 1
  fi

  local cache_dir
  cache_dir=$(opencode debug paths 2>/dev/null | awk '/^cache /{print $2}')

  if [ -z "$cache_dir" ]; then
    warning "▶ tool-cache-sync"
    warning "╍ could not resolve opencode cache dir"
    return 1
  fi

  if [ ! -d "$cache_dir" ]; then
    warning "▶ tool-cache-sync"
    warning "╍ opencode cache not yet populated at ${cache_dir} (run opencode once first)"
    return 1
  fi

  printf '%s\n' "$cache_dir"
}

# tcs_npm_sync — install a package spec into the given cache's node_modules/.
#
# Uses `npm install --save --save-exact --no-package-lock` so that:
#  - node_modules/<pkg>/ gets updated to the requested version
#  - package.json reflects the installed version (kept consistent)
#  - no package-lock.json is written (would conflict with opencode's bun.lock)
#
# We *do* mutate package.json — that's the point. opencode's cache
# package.json is a record of what's installed, and if our bridge updates
# node_modules/ but not package.json, opencode's embedded bun re-resolves on
# next launch using the stale manifest pin and may downgrade or fail. Saving
# the resolved version into the manifest keeps everything coherent.
#
# Self-heals registry-pruned pins: if package.json contains a pin that no
# longer resolves on the registry, npm aborts before doing anything. This
# function detects that ETARGET case and rewrites the unresolvable pin to
# match what's currently in node_modules/, then retries.
tcs_npm_sync() {
  local cache_dir="$1"
  local spec="$2"

  if [ -z "$cache_dir" ] || [ -z "$spec" ]; then
    warning "▶ tool-cache-sync"
    warning "╍ tcs_npm_sync: missing cache_dir or spec argument"
    return 1
  fi

  if ! tcs_require_command npm; then
    return 1
  fi

  info "▶ Syncing ${spec} into ${cache_dir}"

  local npm_output npm_rc
  npm_output=$(cd "$cache_dir" && npm install --save --save-exact --no-package-lock "$spec" 2>&1)
  npm_rc=$?

  if [ "$npm_rc" -eq 0 ]; then
    info "╍ Done"
    return 0
  fi

  if ! printf '%s\n' "$npm_output" | grep -q "ETARGET"; then
    printf '%s\n' "$npm_output" | tail -5 >&2
    error "╍ npm install failed (rc=${npm_rc})"
    return "$npm_rc"
  fi

  warning "╍ Detected unresolvable pin in package.json — repairing"
  if ! tcs_repair_package_manifest "$cache_dir"; then
    error "╍ Could not repair manifest — aborting"
    return 1
  fi

  npm_output=$(cd "$cache_dir" && npm install --save --save-exact --no-package-lock "$spec" 2>&1)
  npm_rc=$?
  if [ "$npm_rc" -ne 0 ]; then
    printf '%s\n' "$npm_output" | tail -5 >&2
    error "╍ npm install still failed after manifest repair (rc=${npm_rc})"
    return "$npm_rc"
  fi

  info "╍ Done (after manifest repair)"
}

# tcs_repair_package_manifest — rewrite any unresolvable pins in the cache's
# package.json to match the version currently installed in node_modules/.
#
# Why this exists: opencode pins exact plugin versions in its cache
# package.json at first install. If the registry later prunes that version
# (Canva's depot does this for very old @canva/* packages), npm refuses to
# operate on the manifest at all — even unrelated packages can't install.
# This function reconciles each manifest pin with the on-disk reality.
tcs_repair_package_manifest() {
  local cache_dir="$1"
  local manifest="${cache_dir}/package.json"

  if [ ! -f "$manifest" ]; then
    return 0
  fi

  if ! tcs_require_command node; then
    return 1
  fi

  node - "$manifest" "$cache_dir" <<'NODE_EOF' || return 1
const fs = require('fs');
const path = require('path');
const [, , manifestPath, cacheDir] = process.argv;
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const deps = manifest.dependencies || {};
let changed = false;
for (const [name, declaredVersion] of Object.entries(deps)) {
  const installedManifest = path.join(cacheDir, 'node_modules', name, 'package.json');
  if (!fs.existsSync(installedManifest)) continue;
  const installed = JSON.parse(fs.readFileSync(installedManifest, 'utf8')).version;
  if (installed && installed !== declaredVersion) {
    process.stderr.write(`info ╍ Reconciling ${name}: ${declaredVersion} → ${installed}\n`);
    deps[name] = installed;
    changed = true;
  }
}
if (changed) {
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
}
NODE_EOF
}
