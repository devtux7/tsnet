#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================================
# MODULAR MODULE LOADER (Supports local execution and curl | bash)
# =============================================================================

SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

GITHUB_USER="devtux7"
GITHUB_REPO="tsnet"
GITHUB_BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH/modules"

if [[ -n "$SCRIPT_DIR" && -d "$SCRIPT_DIR/modules" ]]; then
  MODULES_DIR="$SCRIPT_DIR/modules"
else
  # Remote run: download modules to mktemp folder
  MODULES_DIR="$(mktemp -d)"
  trap 'rm -rf "$MODULES_DIR"' EXIT

  MODULES=("utils.sh" "sysctl.sh" "firewall.sh" "tailscale.sh" "wireguard.sh")
  
  if ! command -v curl >/dev/null 2>&1; then
    printf 'Error: curl is required to fetch script modules.\n' >&2
    exit 1
  fi

  for module in "${MODULES[@]}"; do
    curl -fsSL "$BASE_URL/$module" -o "$MODULES_DIR/$module" || {
      printf 'Error: Failed to download %s from %s/%s\n' "$module" "$BASE_URL" "$module" >&2
      exit 1
    }
  done
fi

# Source our loaded modules
# shellcheck disable=SC1090
source "$MODULES_DIR/utils.sh"
# shellcheck disable=SC1090
source "$MODULES_DIR/sysctl.sh"
# shellcheck disable=SC1090
source "$MODULES_DIR/firewall.sh"
# shellcheck disable=SC1090
source "$MODULES_DIR/tailscale.sh"
# shellcheck disable=SC1090
source "$MODULES_DIR/wireguard.sh"

# =============================================================================
# FLOWS
# =============================================================================

setup_tailscale_flow() {
  local exit_node
  local optimize

  # Environment variables with default values
  exit_node="${TAILSCALE_EXIT_NODE:-true}"
  optimize="${TAILSCALE_OPTIMIZE:-true}"

  log "Installing base dependencies..."
  apt_install ca-certificates curl ufw

  # Apply sysctl network optimizations
  if [[ "$optimize" == "true" ]]; then
    optimize_network_buffers
  fi

  # Apply IP forwarding if exit node is enabled
  if [[ "$exit_node" == "true" ]]; then
    configure_ip_forwarding
  fi

  # Install and start Tailscale
  install_tailscale
  tailscale_up "$exit_node"
  enable_tailscale_ssh

  # Configure firewall
  configure_firewall "$exit_node"

  # Print final instructions
  print_summary "$exit_node"
}

setup_wireguard_flow() {
  setup_wireguard_placeholder
}

# =============================================================================
# INTERACTIVE MENU
# =============================================================================

show_menu() {
  local opt
  while true; do
    printf '\n'
    printf '=============================================\n'
    printf '           Ubuntu Setup Menu                 \n'
    printf '=============================================\n'
    printf '1) Install Tailscale (SSH & Exit Node)\n'
    printf '2) Install Wireguard (Placeholder)\n'
    printf '3) Exit\n'
    printf '=============================================\n'
    
    # Read from /dev/tty to support interactive prompts when piped with curl | bash
    if read -p "Select an option [1-3]: " opt < /dev/tty; then
      printf '\n'
      case "$opt" in
        1)
          setup_tailscale_flow
          break
          ;;
        2)
          setup_wireguard_flow
          break
          ;;
        3)
          printf "Exiting...\n"
          exit 0
          ;;
        *)
          printf "Invalid option. Please try again.\n"
          ;;
      esac
    else
      # If reading from /dev/tty fails (non-interactive environment), default to Tailscale installation
      warn "Non-interactive environment detected. Defaulting to Option 1: Tailscale."
      setup_tailscale_flow
      break
    fi
  done
}

# =============================================================================
# MAIN ORCHESTRATION
# =============================================================================

main() {
  require_root_or_sudo
  detect_os
  show_menu
}

main "$@"
