# modules/sysctl.sh
# Network performance optimizations and IP forwarding configuration for VPN / Exit Node use cases

configure_ip_forwarding() {
  log "Configuring IP forwarding (required for Exit Node)..."
  
  {
    printf '# Managed by setup-tailscale-ssh.sh\n'
    printf 'net.ipv4.ip_forward = 1\n'
    printf 'net.ipv6.conf.all.forwarding = 1\n'
  } | $SUDO tee /etc/sysctl.d/99-tailscale-forwarding.conf >/dev/null

  $SUDO sysctl -p /etc/sysctl.d/99-tailscale-forwarding.conf >/dev/null || warn "Failed to apply IP forwarding sysctl parameters automatically. Reboot may be required."
}

optimize_network_buffers() {
  log "Optimizing network buffers and TCP performance for high throughput..."

  {
    printf '# Managed by setup-tailscale-ssh.sh\n'
    # Enable BBR congestion control
    printf 'net.core.default_qdisc = fq\n'
    printf 'net.ipv4.tcp_congestion_control = bbr\n'
    
    # Increase max socket read/write buffer sizes
    printf 'net.core.rmem_max = 16777216\n'
    printf 'net.core.wmem_max = 16777216\n'
    
    # Increase TCP read/write buffer limits (min, default, max)
    printf 'net.ipv4.tcp_rmem = 4096 87380 16777216\n'
    printf 'net.ipv4.tcp_wmem = 4096 65536 16777216\n'
    
    # Increase interface queue length to prevent package drops
    printf 'net.core.netdev_max_backlog = 10000\n'
    
    # Enable TCP window scaling
    printf 'net.ipv4.tcp_window_scaling = 1\n'
  } | $SUDO tee /etc/sysctl.d/99-tailscale-network-tuning.conf >/dev/null

  # Attempt to load the BBR module if not built-in, though on modern Ubuntu it usually is built-in or auto-loaded
  $SUDO modprobe tcp_bbr 2>/dev/null || true

  $SUDO sysctl -p /etc/sysctl.d/99-tailscale-network-tuning.conf >/dev/null || warn "Failed to apply network tuning sysctl parameters automatically. Reboot may be required."
}
