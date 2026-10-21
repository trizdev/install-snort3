#!/usr/bin/env bash
#
# install-snort3.sh — Build and install Snort 3 (+ libdaq) on Ubuntu Server 24.04 LTS
#
# Usage:
#   chmod +x install-snort3.sh
#   ./install-snort3.sh
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

# ---- preflight checks ----
[[ $EUID -eq 0 ]] && die "Do not run as root. Run as a normal user; the script uses sudo when needed."
command -v sudo >/dev/null || die "sudo not found."
if [[ -r /etc/os-release ]]; then
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
