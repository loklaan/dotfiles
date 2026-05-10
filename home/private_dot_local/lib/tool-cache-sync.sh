#!/usr/bin/env bash
# tool-cache-sync.sh — bridge mise-resolved versions into tool-private plugin
# caches. Designed to be sourced from chezmoi run_onchange_ scripts paired
# with bash-logging.sh.

tcs_require_bun() {
  if ! command -v bun >/dev/null 2>&1; then
    warning "▶ tool-cache-sync"
    warning "╍ bun not found, skipping (install via: mise install bun)"
    return 1
  fi
  return 0
}

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

tcs_bun_sync() {
  local cache_dir="$1"
  local spec="$2"

  if [ -z "$cache_dir" ] || [ -z "$spec" ]; then
    warning "▶ tool-cache-sync"
    warning "╍ tcs_bun_sync: missing cache_dir or spec argument"
    return 1
  fi

  info "▶ Syncing ${spec} into ${cache_dir}"
  (cd "$cache_dir" && bun add "$spec" --save 2>&1 | tail -5)
  info "╍ Done"
}

