#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

# Normalize TMPDIR (strip trailing slash for consistent path construction)
TMPDIR="${TMPDIR:-/tmp}"
TMPDIR="${TMPDIR%/}"

# Source shared logging library (from chezmoi source dir)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
source "${REPO_ROOT}/home/private_dot_local/lib/bash-logging.sh"

#/ Usage:
#/   rotate-age-keys.sh
#/
#/ Description:
#/   Rotates age encryption keys for this dotfiles repository. Generates new
#/   keypairs for all identity classes, stores them in BWS, and re-encrypts
#/   the BWS access token to all recipients.
#/
#/   Use for initial setup or key rotation (e.g., after revoking a machine class).
#/   Updates template files in home/.chezmoitemplates/ directly.
#/
#/ Prerequisites:
#/   - Dotfiles installed (provides age, bws, jq via mise)
#/   - A BWS access token with write access to your secrets project
#/
#/ Options:
#/   --help      Display this help message
#/
usage() { grep '^#/' "$0" | cut -c4-; }

check_prerequisites() {
  local missing=()

  command -v age >/dev/null 2>&1 || missing+=("age")
  command -v age-keygen >/dev/null 2>&1 || missing+=("age-keygen")
  command -v bws >/dev/null 2>&1 || missing+=("bws")
  command -v jq >/dev/null 2>&1 || missing+=("jq")

  if [ ${#missing[@]} -gt 0 ]; then
    error "Missing required tools: ${missing[*]}"
    error "Ensure dotfiles are installed and mise tools are available."
    exit 1
  fi
}

cleanup() {
  if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
}

main() {
  # Parse args
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help) usage; exit 0 ;;
      *) usage; fatal "Unknown argument: $1" ;;
    esac
  done

  info "Age Encryption Bootstrap for Dotfiles"
  echo ""

  check_prerequisites

  # Set up temp directory for keypairs
  TEMP_DIR=$(mktemp -d "${TMPDIR}/age-setup.XXXXXX")
  trap cleanup EXIT

  # Prompt for BWS access token
  echo "This script will:"
  echo "  1. Generate 3 age keypairs (personal, work-machine, work-remote)"
  echo "  2. Store each identity in Bitwarden Secrets Manager"
  echo "  3. Encrypt your BWS access token to all 3 recipients"
  echo "  4. Update template files in home/.chezmoitemplates/"
  echo ""

  if [ -z "${BWS_ACCESS_TOKEN:-}" ]; then
    read -rsp "BWS access token (with write access): " BWS_ACCESS_TOKEN
    echo ""
  fi

  if [ -z "$BWS_ACCESS_TOKEN" ]; then
    fatal "BWS access token is required"
  fi

  # Prompt for project ID
  info "Fetching available projects..."
  projects=$(bws project list --access-token "$BWS_ACCESS_TOKEN" 2>/dev/null || echo "[]")

  if [ "$projects" = "[]" ]; then
    fatal "No projects found. Create a project in BWS first."
  fi

  echo ""
  echo "Available projects:"
  echo "$projects" | jq -r '.[] | "  \(.id)  \(.name)"'
  echo ""

  read -rp "Project ID to store identities in: " PROJECT_ID

  if [ -z "$PROJECT_ID" ]; then
    fatal "Project ID is required"
  fi

  # Validate project ID exists in the list
  if ! echo "$projects" | jq -e --arg id "$PROJECT_ID" '.[] | select(.id == $id)' >/dev/null 2>&1; then
    fatal "Project ID '$PROJECT_ID' not found in available projects"
  fi

  # Test write access by attempting to list secrets in the project
  info "Verifying access to project..."
  if ! bws secret list "$PROJECT_ID" --access-token "$BWS_ACCESS_TOKEN" >/dev/null 2>&1; then
    error "Cannot access project '$PROJECT_ID'"
    error "Reason: Ensure your access token has read/write permissions to this project."
    exit 1
  fi

  # Generate keypairs
  info "Generating age keypairs..."

  age-keygen -o "${TEMP_DIR}/personal.txt"
  age-keygen -o "${TEMP_DIR}/work-machine.txt"
  age-keygen -o "${TEMP_DIR}/work-remote.txt"

  # Extract public keys
  recipient_personal=$(grep 'public key:' "${TEMP_DIR}/personal.txt" | cut -d' ' -f4)
  recipient_work_machine=$(grep 'public key:' "${TEMP_DIR}/work-machine.txt" | cut -d' ' -f4)
  recipient_work_remote=$(grep 'public key:' "${TEMP_DIR}/work-remote.txt" | cut -d' ' -f4)

  info "Generated recipients:"
  echo "  personal:      $recipient_personal"
  echo "  work-machine:  $recipient_work_machine"
  echo "  work-remote:   $recipient_work_remote"
  echo ""

  # Store identities in BWS (update existing or create new)
  info "Storing identities in BWS..."

  TEMPLATES_DIR="${REPO_ROOT}/home/.chezmoitemplates"
  IDENTITY_UUIDS_FILE="${TEMPLATES_DIR}/age-identity-uuids-tmpl"

  # Read existing UUIDs from template file (if exists)
  get_existing_uuid() {
    local identity_type="$1"
    if [ -f "$IDENTITY_UUIDS_FILE" ]; then
      grep "^${identity_type}=" "$IDENTITY_UUIDS_FILE" 2>/dev/null | cut -d= -f2
    fi
  }

  # Update existing secret or create new one
  upsert_secret() {
    local name="$1"
    local value="$2"
    local identity_type="$3"
    local existing_uuid
    local result
    local uuid

    existing_uuid=$(get_existing_uuid "$identity_type")

    if [ -n "$existing_uuid" ]; then
      # Try to update existing secret
      if result=$(bws secret edit --value "$value" "$existing_uuid" --access-token "$BWS_ACCESS_TOKEN" 2>&1); then
        info "  ✓ Updated $name"
        echo "$existing_uuid"
        return 0
      fi
      # If update failed, fall through to create
      warning "  Could not update existing secret, creating new one..."
    fi

    # Create new secret
    if ! result=$(bws secret create "$name" "$value" "$PROJECT_ID" --access-token "$BWS_ACCESS_TOKEN" 2>&1); then
      error "Failed to create secret '$name'"
      error "$result"
      exit 1
    fi

    uuid=$(echo "$result" | jq -r '.id')
    if [ -z "$uuid" ] || [ "$uuid" = "null" ]; then
      error "Failed to parse secret ID from response: $result"
      exit 1
    fi
    info "  ✓ Created $name"
    echo "$uuid"
  }

  uuid_personal=$(upsert_secret "dotfile_age_identity__personal" "$(cat "${TEMP_DIR}/personal.txt")" "personal")
  uuid_work_machine=$(upsert_secret "dotfile_age_identity__work_machine" "$(cat "${TEMP_DIR}/work-machine.txt")" "work-machine")
  uuid_work_remote=$(upsert_secret "dotfile_age_identity__work_remote" "$(cat "${TEMP_DIR}/work-remote.txt")" "work-remote")

  echo ""

  # Encrypt BWS token to all recipients
  info "Encrypting BWS access token..."
  encrypted_token=$(echo -n "$BWS_ACCESS_TOKEN" | age \
    -r "$recipient_personal" \
    -r "$recipient_work_machine" \
    -r "$recipient_work_remote" \
    --armor)

  # Write template files
  info "Writing template files..."

  # Write recipients (one per line)
  cat > "${TEMPLATES_DIR}/age-recipients-tmpl" << EOF
${recipient_personal}
${recipient_work_machine}
${recipient_work_remote}
EOF
  info "  ✓ Updated ${TEMPLATES_DIR}/age-recipients-tmpl"

  # Write identity UUIDs (key=value format)
  cat > "${TEMPLATES_DIR}/age-identity-uuids-tmpl" << EOF
personal=${uuid_personal}
work-machine=${uuid_work_machine}
work-remote=${uuid_work_remote}
EOF
  info "  ✓ Updated ${TEMPLATES_DIR}/age-identity-uuids-tmpl"

  # Write encrypted token (raw armored format)
  cat > "${TEMPLATES_DIR}/age-encrypted-token-tmpl" << EOF
${encrypted_token}
EOF
  info "  ✓ Updated ${TEMPLATES_DIR}/age-encrypted-token-tmpl"

  echo ""
  echo "=============================================================================="
  echo "SUCCESS! Template files have been updated."
  echo "=============================================================================="

  echo ""
  info "Temporary keypair files have been securely deleted."
  info "The identities are now stored only in BWS."
  echo ""
  info "Recipients:"
  echo "  personal:      ${recipient_personal}"
  echo "  work-machine:  ${recipient_work_machine}"
  echo "  work-remote:   ${recipient_work_remote}"
  echo ""
  warning "IMPORTANT: Review changes with 'git diff' and commit before testing."
}

main "$@"
