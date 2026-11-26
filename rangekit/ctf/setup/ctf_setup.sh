#!/usr/bin/env bash
# ctf_setup.sh - install a jeopardy CTF toolchain on Ubuntu, Debian or Kali
# (a VM or WSL2). Idempotent: rerun it any time; what is installed is skipped.
#
# Usage:
#   bash rangekit/ctf/setup/ctf_setup.sh                 # everything
#   bash rangekit/ctf/setup/ctf_setup.sh --only pwn,web  # some categories
#   bash rangekit/ctf/setup/ctf_setup.sh --dry-run       # print, change nothing
#   bash rangekit/ctf/setup/ctf_setup.sh --with-wordlists --with-pwndbg
#   bash rangekit/ctf/setup/ctf_setup.sh --with-heavy    # also angr, qiling, fpylll,
#                                                         # SageMath, PayloadsAllTheThings
#
# Categories: base reverse pwn crypto web forensic misc
# The tool lists follow the Prerequisites of the ctf-* skills in skills/.
# Python tools go into one virtualenv ($CTF_VENV, default ~/ctf-venv); Ruby gems
# and git checkouts go under $CTF_TOOLS (default ~/ctf-tools).
# A package the distribution does not ship is reported and skipped, never fatal;
# the summary at the end lists everything that did not install.

set -u

CTF_VENV="${CTF_VENV:-$HOME/ctf-venv}"
CTF_TOOLS="${CTF_TOOLS:-$HOME/ctf-tools}"
DRY_RUN=0
WITH_WORDLISTS=0
WITH_PWNDBG=0
WITH_HEAVY=0
ONLY="base,reverse,pwn,crypto,web,forensic,misc"
FAILED=()

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --only) shift; ONLY="base,${1:?--only needs a list}" ;;
    --with-wordlists) WITH_WORDLISTS=1 ;;
    --with-pwndbg) WITH_PWNDBG=1 ;;
    --with-heavy) WITH_HEAVY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

wants() { case ",$ONLY," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
say() { printf '\n=== %s ===\n' "$*"; }
run() {
  if [ "$DRY_RUN" = 1 ]; then printf '[dry-run] %s\n' "$*"; return 0; fi
  "$@"
}

SUDO=""
if [ "$(id -u)" != 0 ]; then SUDO="sudo"; fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "apt-get not found: this script supports Ubuntu, Debian and Kali (VM or WSL2)." >&2
  exit 1
fi

IS_WSL=0
# /proc/version also says "microsoft" inside Docker Desktop containers; these two do not.
if [ -n "${WSL_DISTRO_NAME:-}" ] || [ -e /proc/sys/fs/binfmt_misc/WSLInterop ]; then IS_WSL=1; fi

# "env" keeps DEBIAN_FRONTEND a variable when $SUDO is empty (running as root)
apt_get_install() { $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$@" >/dev/null; }

# Install the packages this distribution ships in ONE apt-get call (one call per
# package took ~20 s each on a fresh Ubuntu). A name the distribution lacks is
# reported and skipped; if the batch fails, retry one by one to find the culprit.
# Packages already installed are not touched.
apt_install() {
  local pkg todo=()
  for pkg in "$@"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then continue; fi
    if [ "$DRY_RUN" = 1 ]; then todo+=("$pkg"); continue; fi
    if ! apt-cache show "$pkg" >/dev/null 2>&1; then
      echo "  skip: apt package '$pkg' is not available here"; FAILED+=("apt:$pkg"); continue
    fi
    todo+=("$pkg")
  done
  [ "${#todo[@]}" -eq 0 ] && return 0
  if [ "$DRY_RUN" = 1 ]; then printf '[dry-run] apt-get install -y %s\n' "${todo[*]}"; return 0; fi
  echo "  apt-get install ${todo[*]}"
  apt_get_install "${todo[@]}" && return 0
  echo "  batch failed; retrying one by one"
  for pkg in "${todo[@]}"; do
    apt_get_install "$pkg" || { echo "  FAILED: apt-get install $pkg"; FAILED+=("apt:$pkg"); }
  done
}

pip_install() {
  if [ "$DRY_RUN" = 1 ]; then printf '[dry-run] %s/bin/pip install %s\n' "$CTF_VENV" "$*"; return 0; fi
  local pkg
  for pkg in "$@"; do
    if ! "$CTF_VENV/bin/pip" install -q "$pkg"; then echo "  FAILED: pip install $pkg"; FAILED+=("pip:$pkg"); fi
  done
}

gem_install() {
  local gem
  for gem in "$@"; do
    if [ "$DRY_RUN" = 1 ]; then printf '[dry-run] gem install --user-install %s\n' "$gem"; continue; fi
    if gem list -i "^${gem}$" >/dev/null 2>&1; then continue; fi
    if ! gem install --user-install --no-document "$gem" >/dev/null; then echo "  FAILED: gem install $gem"; FAILED+=("gem:$gem"); fi
  done
}

git_tool() { # git_tool <name> <url>: shallow clone or fast-forward under $CTF_TOOLS
  local dest="$CTF_TOOLS/$1"
  if [ -d "$dest/.git" ]; then run git -C "$dest" pull -q --ff-only || FAILED+=("git:$1"); return; fi
  run git clone -q --depth 1 "$2" "$dest" || FAILED+=("git:$1")
}

say "environment"
echo "distribution : $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
echo "WSL          : $([ "$IS_WSL" = 1 ] && echo yes || echo no)"
echo "categories   : $ONLY"
echo "virtualenv   : $CTF_VENV"
echo "tools dir    : $CTF_TOOLS"

if wants base; then
  say "base"
  run $SUDO apt-get update -q
  apt_install git curl wget ca-certificates build-essential pkg-config \
    python3 python3-pip python3-venv python3-dev ruby ruby-dev \
    jq unzip p7zip-full file xxd netcat-openbsd socat tmux \
    libgmp-dev libmpfr-dev libmpc-dev libssl-dev libffi-dev
  run mkdir -p "$CTF_TOOLS"
  if [ ! -x "$CTF_VENV/bin/python" ]; then run python3 -m venv "$CTF_VENV"; fi
  run "$CTF_VENV/bin/pip" install -q --upgrade pip wheel || FAILED+=("pip:upgrade")
  pip_install requests ipython
fi

if wants reverse; then
  say "reverse"
  apt_install gdb gdb-multiarch ltrace strace binutils upx-ucl radare2 patchelf apktool
  pip_install capstone unicorn keystone-engine uncompyle6 lief frida-tools
  if [ "$WITH_HEAVY" = 1 ]; then pip_install angr qiling; fi
fi

if wants pwn; then
  say "pwn"
  apt_install gdb gdbserver patchelf qemu-user qemu-user-static binutils-multiarch
  pip_install pwntools ropgadget ropper
  gem_install one_gadget seccomp-tools
  if [ "$WITH_PWNDBG" = 1 ]; then
    git_tool pwndbg https://github.com/pwndbg/pwndbg
    echo "  pwndbg checked out in $CTF_TOOLS/pwndbg: run its ./setup.sh once to finish"
  fi
fi

if wants crypto; then
  say "crypto"
  apt_install hashcat john
  pip_install pycryptodome gmpy2 sympy z3-solver ecdsa py_ecc hashpumpy
  git_tool RsaCtfTool https://github.com/RsaCtfTool/RsaCtfTool
  # pip_install takes one package per argument, so a requirements file is installed directly
  if [ "$DRY_RUN" = 1 ] || [ -f "$CTF_TOOLS/RsaCtfTool/requirements.txt" ]; then
    run "$CTF_VENV/bin/pip" install -q -r "$CTF_TOOLS/RsaCtfTool/requirements.txt" || FAILED+=("pip:RsaCtfTool-requirements")
  fi
  if [ "$WITH_HEAVY" = 1 ]; then
    apt_install libfplll-dev sagemath
    pip_install fpylll
    git_tool crypto-attacks https://github.com/jvdsn/crypto-attacks
  fi
fi

if wants web; then
  say "web"
  apt_install sqlmap ffuf gobuster nmap whatweb
  pip_install requests httpx beautifulsoup4 flask-unsign pyjwt
  if [ "$WITH_WORDLISTS" = 1 ]; then
    apt_install seclists
    if [ ! -d /usr/share/seclists ]; then git_tool SecLists https://github.com/danielmiessler/SecLists; fi
  fi
  if [ "$WITH_HEAVY" = 1 ]; then git_tool PayloadsAllTheThings https://github.com/swisskyrepo/PayloadsAllTheThings; fi
fi

if wants forensic; then
  say "forensic"
  apt_install binwalk foremost libimage-exiftool-perl steghide tshark sleuthkit \
    pngcheck qpdf poppler-utils sqlite3 imagemagick ffmpeg testdisk pcapfix
  pip_install volatility3 oletools matplotlib
  gem_install zsteg
fi

if wants misc; then
  say "misc"
  apt_install qrencode zbar-tools libzbar0 sox
  pip_install pillow numpy segno dnslib pyzbar
fi

say "done"
if [ "$DRY_RUN" = 1 ]; then echo "dry run: nothing was changed"; fi
echo "activate the Python tools : source $CTF_VENV/bin/activate"
echo "Ruby gems are in           : \$(gem env user_gemhome)/bin  (add it to PATH)"
if [ "$IS_WSL" = 1 ]; then
  echo "WSL2 note: GUI tools (Ghidra, Burp, Wireshark) run better on the Windows host;"
  echo "           see rangekit/ctf/setup/ctf_windows_gui.ps1"
fi
if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "not installed (${#FAILED[@]}): ${FAILED[*]}"
  exit 3
fi
if [ "$DRY_RUN" = 1 ]; then echo "dry run complete"; else echo "everything requested is installed"; fi
