# modules/settings.sh
# System settings configuration module for Ubuntu

read_password_with_asterisks() {
  local prompt="$1"
  local var_name="$2"
  local char
  local password=""

  # Print prompt directly to /dev/tty
  printf "%s" "$prompt" > /dev/tty

  # Disable input echoing and read key by key from /dev/tty
  while IFS= read -r -s -n 1 char < /dev/tty; do
    # Enter key ends the password input
    # Carriage return (\r) or newline (\n) or empty char
    if [[ -z "$char" || "$char" == $'\n' || "$char" == $'\r' ]]; then
      break
    fi
    
    # Backspace (ASCII 127 or 8)
    if [[ "$char" == $'\x7f' || "$char" == $'\x08' ]]; then
      if [[ ${#password} -gt 0 ]]; then
        # Remove last char from password string
        password="${password%?}"
        # Erase one asterisk on screen: move cursor back, print space, move cursor back again
        printf '\b \b' > /dev/tty
      fi
    else
      # Append character to password
      password+="$char"
      # Print an asterisk directly to /dev/tty
      printf '*' > /dev/tty
    fi
  done
  printf '\n' > /dev/tty
  
  # Return value by reference
  eval "$var_name=\"\$password\""
}

change_password_flow() {
  local target_user="${SUDO_USER:-$USER}"
  log "Changing password for Linux user: ${target_user}..."
  
  local pass1 pass2
  
  while true; do
    read_password_with_asterisks "New password: " "pass1"
    if [[ -z "$pass1" ]]; then
      warn "Password cannot be empty. Please try again."
      continue
    fi
    
    read_password_with_asterisks "Retype new password: " "pass2"
    
    if [[ "$pass1" != "$pass2" ]]; then
      warn "Passwords do not match. Please try again."
      continue
    fi
    break
  done

  # Apply password using chpasswd
  if echo "${target_user}:${pass1}" | $SUDO chpasswd; then
    log "Password updated successfully for user: ${target_user}."
  else
    warn "Failed to update password. Make sure you have correct permissions."
  fi
}
