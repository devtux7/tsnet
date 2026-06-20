# modules/utils.sh
# General utility functions for ubuntu.sh

# ANSI Color Codes
NC='\033[0m' # No Color
GREEN='\033[0;32m'
BOLD_GREEN='\033[1;32m'
YELLOW='\033[0;33m'
BOLD_YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD_RED='\033[1;31m'
CYAN='\033[0;36m'
BOLD_CYAN='\033[1;36m'

log() {
  printf '\n%b🚀 [setup] %s%b\n' "${GREEN}" "$*" "${NC}"
}

warn() {
  printf '\n%b⚠️ [warning] %s%b\n' "${YELLOW}" "$*" "${NC}" >&2
}

error() {
  printf '\n%b❌ [error] %s%b\n' "${RED}" "$*" "${NC}" >&2
  exit 1
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

update_system_packages() {
  log "Updating Ubuntu package lists (apt-get update)..."
  $SUDO apt-get update
}

apt_install() {
  local packages=("$@")
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}
