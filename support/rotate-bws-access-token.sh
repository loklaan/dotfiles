#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

# Source shared logging library (from chezmoi source dir)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
source "${REPO_ROOT}/home/private_dot_local/lib/bash-logging.sh"

#/ Usage:
#/   rotate-bws-access-token.sh [OPTIONS]
#/
#/ Description:
#/   Guide and tool for rotating the BWS access token used by this dotfiles repo.
#/   Prints instructions for rotating the token in Bitwarden Secrets Manager,
#/   and optionally encrypts a new token against the age recipients.
#/
#/ Options:
#/   --help      Display this help message
#/
usage() { grep '^#/' "$0" | cut -c4-; }

check_prerequisites() {
  local missing=()

  command -v age >/dev/null 2>&1 || missing+=("age")

  if [ ${#missing[@]} -gt 0 ]; then
    error "Missing required tools: ${missing[*]}"
    error "Ensure dotfiles are installed and mise tools are available."
    exit 1
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

  TEMPLATES_DIR="${REPO_ROOT}/home/.chezmoitemplates"
  RECIPIENTS_FILE="${TEMPLATES_DIR}/age-recipients-tmpl"
  ENCRYPTED_TOKEN_FILE="${TEMPLATES_DIR}/age-encrypted-token-tmpl"

  echo ""
  _print cyan bold "BWS Access Token Rotation Guide"
  echo ""
  echo "To rotate your BWS access token:"
  echo ""
  echo "  1. Go to Bitwarden Secrets Manager"
  echo "     https://vault.bitwarden.com/#/sm/"
  echo ""
  echo "  2. Navigate to Machine accounts"
  echo ""
  echo "  3. Select the machine account used for dotfiles"
  echo ""
  echo "  4. Go to the Access tokens tab"
  echo ""
  echo "  5. Revoke old tokens and/or create a new access token"
  echo "     (Copy the new token - it won't be shown again)"
  echo ""
  echo "  6. Run this script again and paste the new token when prompted,"
  echo "     or manually encrypt with:"
  echo ""
  echo "       echo -n 'YOUR_TOKEN' | age \\"

  # Read recipients from template file
  if [ -f "$RECIPIENTS_FILE" ]; then
    while IFS= read -r recipient; do
      [ -n "$recipient" ] && echo "         -r \"$recipient\" \\"
    done < "$RECIPIENTS_FILE"
  else
    echo "         -r <recipient1> \\"
    echo "         -r <recipient2> \\"
    echo "         -r <recipient3> \\"
  fi

  echo "         --armor"
  echo ""
  echo "     Then paste the output into:"
  echo "       ${ENCRYPTED_TOKEN_FILE}"
  echo ""

  # Offer to encrypt a new token
  if [ -t 0 ]; then
    echo ""
    read -rp "Do you have a new token to encrypt? [y/N] " response
    case "$response" in
      [yY]|[yY][eE][sS])
        check_prerequisites

        if [ ! -f "$RECIPIENTS_FILE" ]; then
          fatal "Recipients file not found: $RECIPIENTS_FILE"
        fi

        echo ""
        read -rsp "Paste new BWS access token (input hidden): " new_token
        echo ""

        if [ -z "$new_token" ]; then
          fatal "No token provided"
        fi

        info "Encrypting token to all recipients..."

        # Build age command with all recipients
        age_args=()
        while IFS= read -r recipient; do
          [ -n "$recipient" ] && age_args+=("-r" "$recipient")
        done < "$RECIPIENTS_FILE"

        encrypted_token=$(echo -n "$new_token" | age "${age_args[@]}" --armor)

        # Write to template file
        cat > "$ENCRYPTED_TOKEN_FILE" << EOF
${encrypted_token}
EOF

        echo ""
        info "✓ Updated ${ENCRYPTED_TOKEN_FILE}"
        echo ""
        warning "IMPORTANT: Review changes with 'git diff' and commit."
        warning "Then run 'chezmoi apply' to update your local config."
        ;;
      *)
        echo ""
        info "No changes made."
        ;;
    esac
  fi
}

main "$@"
