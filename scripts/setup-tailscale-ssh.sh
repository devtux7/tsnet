#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '\n[setup] %s\n' "$*"
}

warn() {
  printf '\n[warning] %s\n' "$*" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_root_or_sudo() {
  if [[ "${EUID}" -eq 0 ]]; then
    SUDO=""
  elif need_cmd sudo; then
    SUDO="sudo"
  else
    printf 'This script must run as root or with sudo available.\n' >&2
    exit 1
  fi
}

detect_os() {
  if [[ ! -r /etc/os-release ]]; then
    printf 'Cannot read /etc/os-release. This script is intended for Ubuntu.\n' >&2
    exit 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    warn "Detected ${PRETTY_NAME:-unknown OS}; continuing, but this script is tested for Ubuntu."
  fi
}

apt_install() {
  local packages=("$@")
  $SUDO apt-get update
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}

install_tailscale() {
  if need_cmd tailscale; then
    log "Tailscale already installed."
    return
  fi

  log "Installing Tailscale with the official install script."
  curl -fsSL https://tailscale.com/install.sh | $SUDO sh
}

tailscale_up_supports_qr() {
  tailscale up --help 2>&1 | grep -q -- '--qr'
}

install_openssh_server() {
  log "Installing OpenSSH server."
  apt_install openssh-server

  log "Enabling ssh service."
  $SUDO systemctl enable --now ssh
}

configure_sshd() {
  local config_dir="/etc/ssh/sshd_config.d"
  local config_file="${config_dir}/99-tailscale-ssh.conf"

  $SUDO mkdir -p "$config_dir"

  log "Writing SSH hardening config to ${config_file}."
  {
    printf '# Managed by setup-tailscale-ssh.sh\n'
    printf 'PermitRootLogin prohibit-password\n'
    printf 'PubkeyAuthentication yes\n'
    if [[ "${DISABLE_PASSWORD_AUTH:-false}" == "true" ]]; then
      printf 'PasswordAuthentication no\n'
      printf 'KbdInteractiveAuthentication no\n'
    fi
  } | $SUDO tee "$config_file" >/dev/null

  if ! $SUDO sshd -t; then
    warn "Generated sshd config is invalid. Removing ${config_file} and restarting ssh with default config."
    $SUDO rm -f "$config_file"
    $SUDO systemctl restart ssh
    exit 1
  fi

  $SUDO systemctl restart ssh
}

is_tailscale_ipv4() {
  local ip="$1"
  local first second

  IFS=. read -r first second _ _ <<<"$ip"
  [[ "$first" == "100" && "$second" =~ ^[0-9]+$ && "$second" -ge 64 && "$second" -le 127 ]]
}

configure_authorized_keys() {
  local target_user
  local user_info
  local home_dir
  local primary_group
  local ssh_dir
  local auth_file
  local mac_key

  target_user="${TARGET_USER:-${SUDO_USER:-$USER}}"
  user_info="$(getent passwd "$target_user" || true)"
  home_dir="$(cut -d: -f6 <<<"$user_info")"
  primary_group="$(cut -d: -f4 <<<"$user_info")"

  if [[ -z "$home_dir" || ! -d "$home_dir" ]]; then
    warn "Could not find home directory for ${target_user}; skipping authorized_keys setup."
    return
  fi

  ssh_dir="${home_dir}/.ssh"
  auth_file="${ssh_dir}/authorized_keys"

  $SUDO install -d -m 700 -o "$target_user" -g "$primary_group" "$ssh_dir"
  $SUDO touch "$auth_file"
  $SUDO chown "$target_user:$primary_group" "$auth_file"
  $SUDO chmod 600 "$auth_file"

  if [[ -n "${SSH_PUBLIC_KEY:-}" ]]; then
    log "Adding SSH_PUBLIC_KEY to ${auth_file}."
    printf '%s\n' "$SSH_PUBLIC_KEY" | $SUDO tee -a "$auth_file" >/dev/null
  fi

  if [[ -n "${AUTHORIZED_KEYS_FILE:-}" && -r "${AUTHORIZED_KEYS_FILE}" ]]; then
    log "Adding keys from ${AUTHORIZED_KEYS_FILE}."
    $SUDO tee -a "$auth_file" < "$AUTHORIZED_KEYS_FILE" >/dev/null
  fi

  if [[ -n "${GITHUB_USER:-}" ]]; then
    log "Adding public SSH keys from GitHub user ${GITHUB_USER}."
    curl -fsSL "https://github.com/${GITHUB_USER}.keys" | $SUDO tee -a "$auth_file" >/dev/null
  fi

  if [[ "${IMPORT_MAC_ED25519_KEY:-true}" == "true" ]]; then
    mac_key="/mnt/mac/Users/${target_user}/.ssh/id_ed25519.pub"
    if [[ -r "$mac_key" ]]; then
      log "Adding macOS ed25519 public key from ${mac_key}."
      $SUDO tee -a "$auth_file" < "$mac_key" >/dev/null
    fi
  fi

  $SUDO awk '!seen[$0]++ && NF { print }' "$auth_file" | $SUDO tee "${auth_file}.tmp" >/dev/null
  $SUDO mv "${auth_file}.tmp" "$auth_file"
  $SUDO chown "$target_user:$primary_group" "$auth_file"
  $SUDO chmod 600 "$auth_file"
}

configure_firewall() {
  local cidr
  local orbstack_cidrs
  local remote_ip

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

  log "Restricting SSH to the tailscale0 interface with UFW."
  if [[ "${ALLOW_ORBSTACK_HOST_SSH:-true}" == "true" ]]; then
    orbstack_cidrs="${ORBSTACK_SSH_ALLOW_CIDRS:-198.19.0.0/16}"
    for cidr in $orbstack_cidrs; do
      log "Allowing SSH from OrbStack host/bridge network ${cidr}."
      $SUDO ufw insert 1 allow in proto tcp from "$cidr" to any port 22 comment 'Allow SSH from OrbStack host'
    done
  fi
  $SUDO ufw insert 1 allow in on tailscale0 proto tcp to any port 22 comment 'Allow SSH over Tailscale'
  $SUDO ufw insert 3 deny in proto tcp to any port 22 comment 'Deny SSH outside Tailscale'
  $SUDO ufw --force enable
}

tailscale_up() {
  local args=()
  local login_args=()
  local ts_ipv4

  if [[ -n "${TAILSCALE_HOSTNAME:-}" ]]; then
    args+=(--hostname "$TAILSCALE_HOSTNAME")
  fi

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
  elif [[ "${#args[@]}" -gt 0 ]]; then
    log "Tailscale is already authenticated; applying requested tailscale up options."
    $SUDO tailscale up "${args[@]}"
  else
    log "Tailscale is already authenticated."
  fi

}

enable_tailscale_ssh() {
  log "Enabling Tailscale SSH."
  $SUDO tailscale set --ssh
}

print_summary() {
  local access_mode
  local user_name
  local ts_ipv4
  local host_name

  access_mode="${SSH_ACCESS_MODE:-tailscale}"
  user_name="${SUDO_USER:-$USER}"
  ts_ipv4="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"
  host_name="$(hostname)"

  printf '\n'
  printf 'Setup complete.\n'
  printf '\n'

  if [[ -n "${ts_ipv4}" ]]; then
    case "$access_mode" in
      openssh)
        printf 'OpenSSH terminal access:\n'
        ;;
      both)
        printf 'Tailscale SSH terminal access (OpenSSH also configured):\n'
        ;;
      *)
        printf 'Tailscale SSH terminal access:\n'
        ;;
    esac
    printf '  ssh %s@%s\n' "$user_name" "$ts_ipv4"
    printf '\n'
    if [[ "$access_mode" == "openssh" ]]; then
      printf 'VS Code Remote - SSH config example:\n'
      printf '  Host %s\n' "$host_name"
      printf '    HostName %s\n' "$ts_ipv4"
      printf '    User %s\n' "$user_name"
      printf '    Port 22\n'
    else
      printf 'VS Code:\n'
      printf '  Use the Tailscale VS Code extension, or connect with Remote - SSH after Tailscale SSH is allowed by your tailnet policy.\n'
    fi
  else
    printf 'Tailscale is installed, but no Tailscale IPv4 address was detected yet.\n'
    printf 'Authenticate with:\n'
    printf '  sudo tailscale up\n'
    printf 'Then rerun this script.\n'
  fi

  printf '\n'
  printf 'Useful checks:\n'
  printf '  tailscale status\n'
  printf '  tailscale debug prefs\n'
  if [[ "$access_mode" == "openssh" || "$access_mode" == "both" ]]; then
    printf '  systemctl status ssh\n'
  fi
}

main() {
  local ssh_access_mode

  require_root_or_sudo
  detect_os

  ssh_access_mode="${SSH_ACCESS_MODE:-tailscale}"

  log "Installing base dependencies."
  apt_install ca-certificates curl ufw

  install_tailscale
  tailscale_up

  case "$ssh_access_mode" in
    tailscale)
      enable_tailscale_ssh
      ;;
    openssh)
      install_openssh_server
      configure_authorized_keys
      configure_sshd
      if [[ "${ENABLE_TAILSCALE_SSH:-false}" == "true" ]]; then
        enable_tailscale_ssh
      fi
      ;;
    both)
      enable_tailscale_ssh
      install_openssh_server
      configure_authorized_keys
      configure_sshd
      ;;
    *)
      printf 'Unsupported SSH_ACCESS_MODE: %s. Use tailscale, openssh, or both.\n' "$ssh_access_mode" >&2
      exit 1
      ;;
  esac

  configure_firewall
  print_summary
}

main "$@"
