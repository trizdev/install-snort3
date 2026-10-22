#!/usr/bin/env bash
#
# install-snort3.sh — Build and install Snort 3 (+ libdaq) on Ubuntu Server 24.04 LTS
#
# Usage:
#   chmod +x install-snort3.sh
#   ./install-snort3.sh              # Snort 3 only
#   ./install-snort3.sh --dashboard  # Snort 3 + JSON alert logging + web dashboard
#
# The script calls sudo when needed. Do not run it directly as root.
#
set -euo pipefail

# ---- colors ----
if [[ -t 1 ]]; then
  BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"
else
  BOLD=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi
log()  { echo -e "${GREEN}==>${RESET} ${BOLD}$*${RESET}"; }
warn() { echo -e "${YELLOW}[warn]${RESET} $*"; }
die()  { echo -e "${RED}[error]${RESET} $*" >&2; exit 1; }

PREFIX="${PREFIX:-/usr/local}"
SRC_DIR="${SRC_DIR:-$HOME/snort-src}"
JOBS="$(nproc)"
DASHBOARD="${DASHBOARD:-0}"
SNORT_LOG_DIR="${SNORT_LOG_DIR:-/var/log/snort}"
DASHBOARD_DIR="${DASHBOARD_DIR:-/opt/snort-dashboard}"
DASHBOARD_PORT="${DASHBOARD_PORT:-8080}"
# snort3-dashboard release to install, pinned to a tag and its commit.
DASHBOARD_REPO="${DASHBOARD_REPO:-https://github.com/trizdev/snort3-dashboard.git}"
DASHBOARD_REF="${DASHBOARD_REF:-v0.1.0}"
DASHBOARD_COMMIT="${DASHBOARD_COMMIT-aca1b7142ae6ec733cf233a3135a5937bdb29748}"

usage() {
  cat <<USAGE
Usage: $0 [--dashboard] [--help]

  --dashboard   Also enable alert_json logging to $SNORT_LOG_DIR and install
                snort3-dashboard ($DASHBOARD_REF) as a systemd service (same as DASHBOARD=1).
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --dashboard) DASHBOARD=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $arg" ;;
  esac
done

# ---- preflight checks ----
[[ $EUID -eq 0 ]] && die "Do not run as root. Run as a normal user; the script uses sudo when needed."
command -v sudo >/dev/null || die "sudo not found."
if [[ -r /etc/os-release ]]; then
  # shellcheck source=/dev/null
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || warn "Made for Ubuntu. Detected: ${PRETTY_NAME:-unknown}."
  [[ "${VERSION_ID:-}" == "24.04" ]] || warn "Tested on Ubuntu 24.04. Detected: ${VERSION_ID:-?}."
fi

log "Updating package indexes..."
sudo apt-get update -y

log "Installing build dependencies..."
sudo apt-get install -y --no-install-recommends \
  build-essential cmake git pkg-config \
  libpcap-dev libpcre2-dev libdumbnet-dev \
  bison flex zlib1g-dev liblzma-dev \
  libhwloc-dev libluajit-5.1-dev libssl-dev \
  uuid-dev libunwind-dev libgoogle-perftools-dev \
  autotools-dev libtool ca-certificates

mkdir -p "$SRC_DIR"
cd "$SRC_DIR"

# ---- libdaq ----
if command -v daq-modules-config >/dev/null 2>&1 || [[ -e "$PREFIX/lib/libdaq.so" ]]; then
  log "libdaq already looks installed — skipping (set FORCE_DAQ=1 to rebuild)."
  [[ "${FORCE_DAQ:-0}" == "1" ]] && NEED_DAQ=1 || NEED_DAQ=0
else
  NEED_DAQ=1
fi
if [[ "$NEED_DAQ" == "1" ]]; then
  log "Building libdaq (Snort 3 prerequisite)..."
  rm -rf libdaq
  git clone --depth 1 https://github.com/snort3/libdaq.git
  cd libdaq
  ./bootstrap
  ./configure --prefix="$PREFIX"
  make -j"$JOBS"
  sudo make install
  cd "$SRC_DIR"
  sudo ldconfig
fi

# ---- snort3 ----
log "Cloning Snort 3..."
rm -rf snort3
git clone --depth 1 https://github.com/snort3/snort3.git
cd snort3
log "Configuring the build (cmake)..."
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
./configure_cmake.sh --prefix="$PREFIX" --enable-tcmalloc
cd build
log "Compiling Snort 3 (this takes 15-30 min)..."
make -j"$JOBS"
log "Installing..."
sudo make install
sudo ldconfig

# ---- verification ----
export PATH="$PREFIX/bin:$PATH"
if "$PREFIX/bin/snort" -V 2>/dev/null; then
  echo
  log "${GREEN}Snort 3 installed successfully!${RESET}"
  echo "Binary: $PREFIX/bin/snort"
  echo "Default config: $PREFIX/etc/snort/snort.lua"
  echo "Test the config:  snort -c $PREFIX/etc/snort/snort.lua"
else
  die "Build finished but 'snort -V' failed. Run 'sudo ldconfig' and open a new terminal."
fi

# ---- optional: alert_json logging + snort3-dashboard ----
enable_alert_json() {
  local conf="$PREFIX/etc/snort/snort.lua"
  local marker="-- install-snort3: alert_json for the dashboard"
  local output_line="output = { logdir = '$SNORT_LOG_DIR' }"

  [[ -f "$conf" ]] || die "$conf not found."
  if sudo grep -qF -- "$marker" "$conf" || sudo grep -qE '^[[:space:]]*alert_json[[:space:]]*=' "$conf"; then
    log "alert_json is already configured in $conf — leaving it as is."
    return
  fi
  log "Enabling alert_json output in $conf..."
  if sudo grep -qE '^[[:space:]]*output[[:space:]]*=' "$conf"; then
    warn "$conf already sets 'output'. Make sure its logdir is $SNORT_LOG_DIR."
    output_line="-- output.logdir is set elsewhere in this file"
  fi
  sudo cp -a "$conf" "$conf.bak.$(date +%Y%m%d%H%M%S)"
  sudo tee -a "$conf" >/dev/null <<LUA

$marker
$output_line
alert_json =
{
    file = true,
    limit = 100,  -- MB before Snort rolls the file over
    fields = 'seconds timestamp priority class msg rule gid sid rev proto service ' ..
             'pkt_len src_addr src_port dst_addr dst_port action dir iface',
}
LUA
}

install_dashboard() {
  local dest="$SRC_DIR/snort3-dashboard"

  log "Fetching snort3-dashboard $DASHBOARD_REF..."
  command -v python3 >/dev/null || sudo apt-get install -y --no-install-recommends python3
  rm -rf "$dest"
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$DASHBOARD_REF" "$DASHBOARD_REPO" "$dest"
  if [[ -n "$DASHBOARD_COMMIT" ]]; then
    local head
    head="$(git -C "$dest" rev-parse HEAD)"
    [[ "$head" == "$DASHBOARD_COMMIT" ]] \
      || die "snort3-dashboard $DASHBOARD_REF is at $head, expected $DASHBOARD_COMMIT. Set DASHBOARD_COMMIT= to skip this check."
  fi

  "$dest/install.sh" --log-dir "$SNORT_LOG_DIR" --dir "$DASHBOARD_DIR" --port "$DASHBOARD_PORT"

  log "Checking the Snort config..."
  if sudo "$PREFIX/bin/snort" -c "$PREFIX/etc/snort/snort.lua" -T -q >/dev/null 2>&1; then
    log "Config OK. Start Snort with: sudo snort -c $PREFIX/etc/snort/snort.lua -i <interface>"
  else
    warn "snort -T reported a problem. Check it with: sudo snort -c $PREFIX/etc/snort/snort.lua -T"
  fi
}

if [[ "$DASHBOARD" == "1" ]]; then
  enable_alert_json
  install_dashboard
fi
