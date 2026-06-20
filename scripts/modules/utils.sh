# modules/utils.sh
# General utility functions for setup-tailscale-ssh.sh

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
