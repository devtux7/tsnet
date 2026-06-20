# modules/tailscale.sh
# Tailscale installation, login, and configuration module

tailscale_up_supports_qr() {
  tailscale up --help 2>&1 | grep -q -- '--qr'
}

install_tailscale() {
  if need_cmd tailscale; then
    log "Tailscale already installed."
    return
  fi

  log "Installing Tailscale with the official install script..."
  curl -fsSL https://tailscale.com/install.sh | $SUDO sh
}

tailscale_up() {
  local exit_node_enabled="${1:-false}"
  local args=()
  local login_args=()
  local ts_ipv4

  if [[ -n "${TAILSCALE_HOSTNAME:-}" ]]; then
    args+=(--hostname "$TAILSCALE_HOSTNAME")
  fi

  if [[ "$exit_node_enabled" == "true" ]]; then
    log "Configuring Tailscale to advertise as an exit node..."
    args+=(--advertise-exit-node)
  fi

  # Enable Tailscale SSH
  args+=(--ssh)

  ts_ipv4="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"

  if [[ -z "$ts_ipv4" ]]; then
    login_args=("${args[@]}")
    if [[ "${TAILSCALE_LOGIN_QR:-true}" == "true" ]]; then
      if tailscale_up_supports_qr; then
        login_args+=(--qr --qr-format "${TAILSCALE_QR_FORMAT:-small}")
      else
        warn "This Tailscale version does not support login QR codes; falling back to the login URL only."
      fi
    fi

    log "Running tailscale up. Open the printed Tailscale login URL, or scan the QR code if shown."
    $SUDO tailscale up "${login_args[@]}"
  else
    log "Tailscale is already authenticated; applying requested options..."
    $SUDO tailscale up "${args[@]}"
  fi
}

enable_tailscale_ssh() {
  log "Ensuring Tailscale SSH is enabled..."
  $SUDO tailscale set --ssh
}

print_summary() {
  local exit_node_enabled="${1:-false}"
  local user_name
  local ts_ipv4

  user_name="${SUDO_USER:-$USER}"
  ts_ipv4="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"

  printf '\n'
  printf '%b🎉 Setup complete!%b\n' "${BOLD_GREEN}" "${NC}"
  printf '\n'

  if [[ -n "${ts_ipv4}" ]]; then
    printf 'Tailscale SSH terminal access:\n'
    printf '  %bssh %s@%s%b\n' "${BOLD_GREEN}" "$user_name" "$ts_ipv4" "${NC}"
    printf '\n'
    
    if [[ "$exit_node_enabled" == "true" ]]; then
      printf '%b🔑 Exit Node Active:%b\n' "${BOLD_YELLOW}" "${NC}"
      printf '  %bPlease open your Tailscale Admin Console and approve this machine as an Exit Node.%b\n' "${BOLD_YELLOW}" "${NC}"
      printf '  Admin Console: %bhttps://login.tailscale.com/admin/machines%b\n' "${CYAN}" "${NC}"
      printf '\n'
    fi

    printf 'VS Code:\n'
    printf '  Use the Tailscale VS Code extension, or connect with Remote - SSH after Tailscale SSH is allowed by your tailnet policy.\n'
  else
    printf '%bTailscale is installed, but no Tailscale IPv4 address was detected yet.%b\n' "${BOLD_RED}" "${NC}"
    printf 'Authenticate with:\n'
    printf '  %bsudo tailscale up%b\n' "${BOLD_CYAN}" "${NC}"
    printf 'Then rerun this script.\n'
  fi

  printf '\n'
  printf 'Useful checks:\n'
  printf '  tailscale status\n'
  printf '  tailscale debug prefs\n'
}
