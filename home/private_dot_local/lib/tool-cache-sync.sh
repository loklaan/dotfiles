#!/usr/bin/env bash
# tool-cache-sync.sh — force OpenCode to re-resolve its @latest plugins.
# Designed to be sourced from chezmoi run_onchange_ scripts paired with
# bash-logging.sh.
#
# OpenCode installs a plugin once into
# <cache>/packages/<sanitized-spec>/node_modules/<pkg> and thereafter treats
# that directory's existence as a cache hit — it never re-checks the registry
# for an @latest spec (see packages/core/src/npm.ts Npm.add in sst/opencode).
# There is no CLI flag, env var, or lockfile check that re-resolves @latest, so
# a plugin freezes on its first-installed version indefinitely. Deleting the
# package's cache dir is the only lever: OpenCode reinstalls the current @latest
# on next launch.

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

# tcs_bust_opencode_plugin — remove a plugin's cache dir so OpenCode re-resolves
# it from the registry on next launch. The spec is the dir name OpenCode
# sanitizes it to under packages/ (scoped names keep their @scope subdir, e.g.
# "@canva/opencode-plugin-llmproxy@latest"). No-op if the dir is absent.
tcs_bust_opencode_plugin() {
  local packages_dir="$1"
  local spec="$2"

  if [ -z "$packages_dir" ] || [ -z "$spec" ]; then
    warning "▶ tool-cache-sync"
    warning "╍ tcs_bust_opencode_plugin: missing packages_dir or spec argument"
    return 1
  fi

  local target="${packages_dir}/${spec}"
  if [ -d "$target" ]; then
    rm -rf "$target"
    info "╍ Cleared OpenCode plugin cache: ${spec} (re-resolves @latest on next launch)"
  fi
}
