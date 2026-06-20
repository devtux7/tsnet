# modules/firewall.sh
# Firewall and security rules configuration (UFW)

is_tailscale_ipv4() {
  local ip="$1"
  local first second

  IFS=. read -r first second _ _ <<<"$ip"
  [[ "$first" == "100" && "$second" =~ ^[0-9]+$ && "$second" -ge 64 && "$second" -le 127 ]]
}

configure_firewall() {
  local remote_ip
  local exit_node_enabled="${1:-false}"

  if [[ "${LOCKDOWN_SSH_TO_TAILSCALE:-true}" != "true" ]]; then
    log "Skipping firewall lockdown because LOCKDOWN_SSH_TO_TAILSCALE is not true."
    return
  fi

  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    remote_ip="${SSH_CONNECTION%% *}"
    if ! is_tailscale_ipv4 "$remote_ip" && [[ "${FORCE_LOCKDOWN:-false}" != "true" ]]; then
      warn "This script appears to be running over non-Tailscale SSH from ${remote_ip}; skipping UFW lockdown to avoid disconnecting you. Set FORCE_LOCKDOWN=true to override."
      return
    fi
  fi

  log "Configuring UFW firewall rules..."
  
  if [[ "${ALLOW_ORBSTACK_HOST_SSH:-true}" == "true" ]]; then
    local cidr
    local orbstack_cidrs="${ORBSTACK_SSH_ALLOW_CIDRS:-198.19.0.0/16}"
    for cidr in $orbstack_cidrs; do
      log "Allowing SSH from OrbStack host/bridge network ${cidr}."
      $SUDO ufw insert 1 allow in proto tcp from "$cidr" to any port 22 comment 'Allow SSH from OrbStack host'
    done
  fi

  $SUDO ufw insert 1 allow in on tailscale0 proto tcp to any port 22 comment 'Allow SSH over Tailscale'
  $SUDO ufw insert 3 deny in proto tcp to any port 22 comment 'Deny SSH outside Tailscale'

  if [[ "$exit_node_enabled" == "true" ]]; then
    log "Allowing packet forwarding in UFW for Exit Node..."
    if [[ -f /etc/default/ufw ]]; then
      # Change DEFAULT_FORWARD_POLICY from "DROP" to "ACCEPT" to allow routed traffic
      $SUDO sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw
    fi
  fi

  $SUDO ufw --force enable
}
