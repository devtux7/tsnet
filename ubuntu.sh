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
  local enable_ssh="false"
  local enable_exit_node="false"
  local enable_optimize="false"
  local enable_ufw_lockdown="false"
  local ans opt_ans

  printf '\n%b--- Tailscale Configuration Settings ---%b\n' "${BOLD_CYAN}" "${NC}"

  # 1. Tailscale SSH Option
  if read -p "Do you want to enable Tailscale SSH? [Y/n]: " ans < /dev/tty; then
    if [[ -z "$ans" || "$ans" =~ ^[yY](es)?$ ]]; then
      enable_ssh="true"
    fi
  else
    enable_ssh="true"
  fi

  # 2. Exit Node & Optimization Options
  if read -p "Do you want to advertise this machine as an Exit Node (VPN)? [Y/n]: " ans < /dev/tty; then
    if [[ -z "$ans" || "$ans" =~ ^[yY](es)?$ ]]; then
      enable_exit_node="true"
      
      # Networking tunings
      if read -p "Do you want to apply network performance/sysctl optimizations for Exit Node traffic? [Y/n]: " opt_ans < /dev/tty; then
        if [[ -z "$opt_ans" || "$opt_ans" =~ ^[yY](es)?$ ]]; then
          enable_optimize="true"
        fi
      else
        enable_optimize="true"
      fi
    fi
  else
    enable_exit_node="true"
    enable_optimize="true"
  fi

  # 3. Firewall Lockdown & Connection Analysis
  local is_remote_ssh="false"
  local remote_ip=""

  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    remote_ip="${SSH_CONNECTION%% *}"
    if ! is_tailscale_ipv4 "$remote_ip"; then
      is_remote_ssh="true"
    fi
  fi

  # Determine lockdown behavior
  if [[ "${LOCKDOWN_SSH_TO_TAILSCALE:-true}" == "true" ]]; then
    if is_orbstack; then
      # OrbStack VMs always keep loopback/host bridge accessible, safe to enable
      enable_ufw_lockdown="true"
    elif [[ "$is_remote_ssh" == "true" ]]; then
      # Remote Cloud VM over public SSH connection
      printf '\n%b⚠️  WARNING: Enabling UFW firewall lockdown will immediately close port 22 on your public IP.%b\n' "${BOLD_YELLOW}" "${NC}"
      printf 'Your current SSH connection will be disconnected, and you must reconnect using Tailscale SSH.\n'
      if read -p "Do you want to enable UFW lockdown anyway? [y/N]: " ans < /dev/tty; then
        if [[ "$ans" =~ ^[yY](es)?$ ]]; then
          enable_ufw_lockdown="true"
        fi
      fi
    else
      # Local console execution or already using Tailscale SSH, safe to enable
      enable_ufw_lockdown="true"
    fi
  fi

  # ----------------------------------------
  # RUN INSTALLATION FLOW
  # ----------------------------------------
  update_system_packages

  log "Installing base dependencies..."
  apt_install ca-certificates curl ufw

  # Apply sysctl network optimizations
  if [[ "$enable_optimize" == "true" ]]; then
    optimize_network_buffers
  fi

  # Apply IP forwarding if exit node is enabled
  if [[ "$enable_exit_node" == "true" ]]; then
    configure_ip_forwarding
  fi

  # Install and start Tailscale
  install_tailscale
  tailscale_up "$enable_exit_node" "$enable_ssh"
  
  if [[ "$enable_ssh" == "true" ]]; then
    enable_tailscale_ssh
  fi

  # Configure firewall
  if [[ "$enable_ufw_lockdown" == "true" ]]; then
    configure_firewall "$enable_exit_node"
  else
    log "Skipping UFW firewall lockdown to preserve current public SSH connection."
  fi

  # Print final instructions
  print_summary "$enable_exit_node" "$enable_ssh"
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
    printf '%b=============================================%b\n' "${GREEN}" "${NC}"
    printf '%b     💻   Ubuntu Setup Menu                  %b\n' "${BOLD_GREEN}" "${NC}"
    printf '%b=============================================%b\n' "${GREEN}" "${NC}"
    printf '%b1)%b Install Tailscale (Interactive Options)\n' "${BOLD_CYAN}" "${NC}"
    printf '%b2)%b Install Wireguard (Placeholder)\n' "${BOLD_CYAN}" "${NC}"
    printf '%b3)%b Exit\n' "${BOLD_CYAN}" "${NC}"
    printf '%b=============================================%b\n' "${GREEN}" "${NC}"
    
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
          printf "%bInvalid option. Please try again.%b\n" "${RED}" "${NC}"
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
