#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================================
# MODULAR MODULE LOADER (Supports local execution and curl | bash)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_USER="devtux7"
GITHUB_REPO="tsnet"
GITHUB_BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH/scripts/modules"

if [[ -d "$SCRIPT_DIR/modules" ]]; then
  MODULES_DIR="$SCRIPT_DIR/modules"
elif [[ -d "$SCRIPT_DIR/scripts/modules" ]]; then
  MODULES_DIR="$SCRIPT_DIR/scripts/modules"
else
  # Remote run: download modules to mktemp folder
  MODULES_DIR="$(mktemp -d)"
  trap 'rm -rf "$MODULES_DIR"' EXIT

  MODULES=("utils.sh" "sysctl.sh" "firewall.sh" "tailscale.sh")
  
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

# =============================================================================
# MAIN ORCHESTRATION
# =============================================================================

main() {
  local exit_node
  local optimize

  require_root_or_sudo
  detect_os

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

main "$@"
