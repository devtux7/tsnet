# modules/settings.sh
# System settings configuration module for Ubuntu

change_password_flow() {
  local target_user="${SUDO_USER:-$USER}"
  log "Changing password for Linux user: ${target_user}..."
  
  if [[ -n "${SUDO:-}" ]]; then
    $SUDO passwd "$target_user" < /dev/tty
  else
    passwd "$target_user" < /dev/tty
  fi
}
