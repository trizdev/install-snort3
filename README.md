# install-snort3

One-command script to **build and install [Snort 3](https://github.com/snort3/snort3)** (plus `libdaq`) on **Ubuntu Server 24.04 LTS**.

Ubuntu only ships Snort 2.9 through `apt`. Snort 3 — rewritten in modular C++, configured in Lua (`snort.lua`) and dependent on DAQ 3.x — has to be compiled from source. This script automates the whole process.

## What it does

1. Installs build dependencies (`cmake`, `flex`, `bison`, `libpcap`, `libpcre2`, `libdnet`/`libdumbnet`, `hwloc`, `luajit`, `openssl`, and more).
2. Builds and installs **libdaq** from the official `snort3/libdaq` repo.
3. Builds and installs **Snort 3** from `snort3/snort3` (with `--enable-tcmalloc`).
4. Runs `ldconfig` and verifies the install with `snort -V`.

By default it installs into `/usr/local` and uses `~/snort-src` as the work directory.

## Usage

```bash
git clone https://github.com/trizdev/install-snort3.git
cd install-snort3
chmod +x install-snort3.sh
./install-snort3.sh
```

Run it as a **regular user** (not root) — the script calls `sudo` when needed. The build takes **15–30 min**.

### Optional variables

| Variable    | Default           | Description                          |
|-------------|-------------------|--------------------------------------|
| `PREFIX`    | `/usr/local`      | Install directory                    |
| `SRC_DIR`   | `$HOME/snort-src` | Where sources are cloned and built   |
| `FORCE_DAQ` | `0`               | Set to `1` to force rebuilding libdaq |

Example: `PREFIX=$HOME/.local ./install-snort3.sh`

## Verify

```bash
snort -V                                   # should print "Version 3.x"
snort -c /usr/local/etc/snort/snort.lua    # validates the default config
```

## Requirements

- Ubuntu 24.04 LTS (works on other Ubuntu/Debian-based releases with minor tweaks).
- `sudo` access.
- Internet connection (clones from GitHub).

## Disclaimer

This script is a community convenience. **Snort** is a trademark and software of Cisco/OISF, licensed under **GPLv2**; all source code is pulled from the official repositories. This installer is independent and not affiliated with the Snort project.

## License

Code in this repository is released under the [MIT License](LICENSE).
