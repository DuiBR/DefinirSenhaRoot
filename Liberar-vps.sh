#!/usr/bin/env bash
# By DuiBR - Otimizado
# Script para habilitar login root por senha, liberar portas e personalizar o terminal Fastmob
# Instalador universal Fastmob para VPS Linux
# Detecta distribuição, versão, arquitetura, libc, gerenciador de pacotes e dependências.
# Usa Fastfetch quando compatível e possui terminal Fastmob nativo como fallback.

set -Eeuo pipefail
IFS=$'\n\t'
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

# ==========================================================
# CONFIGURAÇÕES
# ==========================================================

INSTALL_DEPENDENCIES="true"
CONFIGURE_DNS="true"
ENABLE_ROOT_PASSWORD_LOGIN="true"
OPEN_ALL_PORTS="true"
CONFIGURE_FASTMOB_TERMINAL="true"

FASTMOB_ROOT_HOME="/root"
FASTMOB_CONFIG_DIR="${FASTMOB_ROOT_HOME}/.config/fastfetch"
FASTMOB_CONFIG_FILE="${FASTMOB_CONFIG_DIR}/config.jsonc"
FASTMOB_MOBILE_CONFIG_FILE="${FASTMOB_CONFIG_DIR}/config-mobile.jsonc"
FASTMOB_BASHRC="${FASTMOB_ROOT_HOME}/.bashrc"
FASTMOB_WRAPPER="/usr/local/bin/fastmob-terminal"

# Informações detectadas automaticamente (preenchidas por detect_system)
SYSTEM_KERNEL=""
SYSTEM_OS_ID=""
SYSTEM_OS_LIKE=""
SYSTEM_OS_VERSION=""
SYSTEM_OS_PRETTY=""
SYSTEM_ARCH_RAW=""
SYSTEM_ARCH=""
SYSTEM_LIBC=""
SYSTEM_LIBC_VERSION=""
PKG_MANAGER=""
SYSTEM_INIT=""

DNS_1="1.1.1.1"
DNS_2="8.8.8.8"

LOG_FILE="/var/log/liberar-vps-root-portas.log"
BACKUP_DIR="/root/backup-liberar-vps-$(date +%Y%m%d-%H%M%S)"

# ==========================================================
# CORES
# ==========================================================

if [[ -t 1 ]]; then
  RED=$'\e[1;31m'
  GREEN=$'\e[1;32m'
  YELLOW=$'\e[1;33m'
  BLUE=$'\e[1;34m'
  WHITE=$'\e[1;37m'
  NC=$'\e[0m'
else
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  WHITE=""
  NC=""
fi

# ==========================================================
# FUNÇÕES BASE
# ==========================================================

log_init() {
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"
  chmod 600 "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
}

die() {
  printf '\n%b[ERRO]%b %s\n' "$RED" "$NC" "$*"
  printf '%bBackup salvo em:%b %s\n' "$YELLOW" "$NC" "$BACKUP_DIR"
  printf '%bLog salvo em:%b %s\n' "$YELLOW" "$NC" "$LOG_FILE"
  exit 1
}

on_error() {
  local line="$1"
  die "Falha inesperada na linha ${line}."
}

trap 'on_error "$LINENO"' ERR

is_root() {
  [[ "${EUID}" -eq 0 ]]
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

print_banner() {
  clear || true

  printf '%b\n' "${RED} ______        _   ${WHITE} __  __       _${NC}"
  printf '%b\n' "${RED}|  ____|      | |  ${WHITE}|  \\/  |     | |${NC}"
  printf '%b\n' "${RED}| |__ __ _ ___| |_ ${WHITE}| \\  / | ___ | |__${NC}"
  printf '%b\n' "${RED}|  __/ _\` / __| __|${WHITE}| |\\/| |/ _ \\| '_ \\${NC}"
  printf '%b\n' "${RED}| | | (_| \\__ \\ |_ ${WHITE}| |  | | (_) | |_) |${NC}"
  printf '%b\n' "${RED}|_|  \\__,_|___/\\__|${WHITE}|_|  |_|\\___/|_.__/${NC}"
  echo
  printf '%b\n' "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
  printf '%b\n' "${RED}║                 🚨 AVISO DE SEGURANÇA 🚨                  ║${NC}"
  printf '%b\n' "${WHITE}║ Este script habilita login root por senha e libera portas. ║${NC}"
  printf '%b\n' "${WHITE}║ Também instala o terminal personalizado Fastmob.           ║${NC}"
  printf '%b\n' "${WHITE}║ Use apenas em VPS própria e com responsabilidade.          ║${NC}"
  printf '%b\n' "${WHITE}║ O mais seguro é usar SSH por chave e firewall restrito.    ║${NC}"
  printf '%b\n' "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
  echo
}

run_step() {
  local msg="$1"
  shift

  local tmp_log
  tmp_log="$(mktemp)"

  # O ERR trap global nao deve encerrar o script dentro do worker.
  # O status e tratado aqui para exibir apenas uma mensagem de falha.
  (
    trap - ERR
    set +e
    "$@"
    exit $?
  ) >"$tmp_log" 2>&1 &

  local pid=$!
  local delay=0.12
  local spin='|/-\'

  while kill -0 "$pid" >/dev/null 2>&1; do
    for i in 0 1 2 3; do
      printf "\r\033[K%b[AGUARDE]%b %s %b%s%b" \
        "$YELLOW" "$NC" "$msg" "$RED" "${spin:$i:1}" "$NC"
      sleep "$delay"
    done
  done

  local status=0
  wait "$pid" || status=$?

  if [[ "$status" -eq 0 ]]; then
    printf "\r\033[K%b[OK]%b %s %b✔%b\n" \
      "$GREEN" "$NC" "$msg" "$GREEN" "$NC"
    rm -f "$tmp_log"
    return 0
  fi

  printf "\r\033[K%b[FALHOU]%b %s %b✖%b\n" \
    "$RED" "$NC" "$msg" "$RED" "$NC"

  echo
  printf '%bDetalhes do erro:%b\n' "$YELLOW" "$NC"
  cat "$tmp_log" || true
  rm -f "$tmp_log"

  return "$status"
}

backup_file() {
  local file="$1"

  [[ -e "$file" ]] || return 0

  local safe_name
  safe_name="$(echo "$file" | sed 's#/#_#g')"

  cp -a "$file" "$BACKUP_DIR/$safe_name"
}

backup_dir() {
  local dir="$1"

  [[ -d "$dir" ]] || return 0

  local safe_name
  safe_name="$(echo "$dir" | sed 's#/#_#g')"

  tar -czf "$BACKUP_DIR/$safe_name.tar.gz" "$dir" >/dev/null 2>&1 || true
}

# ==========================================================
# BACKUP
# ==========================================================

make_backup() {
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"

  backup_file "/etc/ssh/sshd_config"
  backup_dir "/etc/ssh/sshd_config.d"
  backup_file "/etc/resolv.conf"
  backup_file "/etc/nftables.conf"
  backup_file "$FASTMOB_BASHRC"
  backup_file "${FASTMOB_ROOT_HOME}/.profile"
  backup_file "${FASTMOB_ROOT_HOME}/.bash_profile"
  backup_file "${FASTMOB_ROOT_HOME}/.bash_login"
  backup_dir "$FASTMOB_CONFIG_DIR"
  backup_file "$FASTMOB_WRAPPER"

  if command_exists iptables-save; then
    iptables-save > "$BACKUP_DIR/iptables-rules.v4" || true
  fi

  if command_exists ip6tables-save; then
    ip6tables-save > "$BACKUP_DIR/iptables-rules.v6" || true
  fi

  if command_exists nft; then
    nft list ruleset > "$BACKUP_DIR/nftables-ruleset.txt" 2>/dev/null || true
  fi

  if command_exists ufw; then
    ufw status verbose > "$BACKUP_DIR/ufw-status.txt" 2>/dev/null || true
  fi

  if command_exists firewall-cmd; then
    firewall-cmd --list-all > "$BACKUP_DIR/firewalld-status.txt" 2>/dev/null || true
  fi
}

# ==========================================================
# DETECÇÃO DO SISTEMA / DEPENDÊNCIAS
# ==========================================================

detect_system() {
  SYSTEM_KERNEL="$(uname -s 2>/dev/null || echo unknown)"
  SYSTEM_ARCH_RAW="$(uname -m 2>/dev/null || echo unknown)"

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    SYSTEM_OS_ID="${ID:-linux}"
    SYSTEM_OS_LIKE="${ID_LIKE:-}"
    SYSTEM_OS_VERSION="${VERSION_ID:-}"
    SYSTEM_OS_PRETTY="${PRETTY_NAME:-${NAME:-Linux}}"
  else
    SYSTEM_OS_ID="linux"
    SYSTEM_OS_LIKE=""
    SYSTEM_OS_VERSION=""
    SYSTEM_OS_PRETTY="Linux"
  fi

  case "$SYSTEM_ARCH_RAW" in
    x86_64|amd64)                  SYSTEM_ARCH="amd64" ;;
    aarch64|arm64)                 SYSTEM_ARCH="aarch64" ;;
    armv7l|armv7*|armhf)           SYSTEM_ARCH="armv7l" ;;
    i386|i486|i586|i686|x86)       SYSTEM_ARCH="i686" ;;
    ppc64le|ppc64el)               SYSTEM_ARCH="ppc64le" ;;
    s390x)                         SYSTEM_ARCH="s390x" ;;
    riscv64)                       SYSTEM_ARCH="riscv64" ;;
    loongarch64|loong64)           SYSTEM_ARCH="loongarch64" ;;
    *)                             SYSTEM_ARCH="$SYSTEM_ARCH_RAW" ;;
  esac

  if command_exists getconf; then
    SYSTEM_LIBC_VERSION="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}' || true)"
  fi

  if command_exists ldd; then
    local ldd_out=""
    ldd_out="$(ldd --version 2>&1 | head -n2 || true)"
    if echo "$ldd_out" | grep -qi 'musl'; then
      SYSTEM_LIBC="musl"
      SYSTEM_LIBC_VERSION="$(echo "$ldd_out" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)"
    elif echo "$ldd_out" | grep -Eqi 'glibc|GNU libc|GNU C Library|Ubuntu GLIBC|Debian GLIBC'; then
      SYSTEM_LIBC="glibc"
      if [[ -z "$SYSTEM_LIBC_VERSION" ]]; then
        SYSTEM_LIBC_VERSION="$(echo "$ldd_out" | grep -oE '[0-9]+\.[0-9]+' | tail -n1 || true)"
      fi
    fi
  fi

  if [[ -z "$SYSTEM_LIBC" ]]; then
    if [[ -n "$SYSTEM_LIBC_VERSION" ]]; then
      SYSTEM_LIBC="glibc"
    elif [[ -e /lib/libc.musl-x86_64.so.1 || -e /lib/ld-musl-aarch64.so.1 ]]; then
      SYSTEM_LIBC="musl"
    else
      SYSTEM_LIBC="unknown"
    fi
  fi

  if command_exists systemctl && [[ -d /run/systemd/system ]]; then
    SYSTEM_INIT="systemd"
  elif command_exists rc-service; then
    SYSTEM_INIT="openrc"
  elif command_exists sv; then
    SYSTEM_INIT="runit"
  elif command_exists service; then
    SYSTEM_INIT="sysv"
  else
    SYSTEM_INIT="unknown"
  fi

  if command_exists apt-get; then
    PKG_MANAGER="apt"
  elif command_exists dnf; then
    PKG_MANAGER="dnf"
  elif command_exists microdnf; then
    PKG_MANAGER="microdnf"
  elif command_exists yum; then
    PKG_MANAGER="yum"
  elif command_exists zypper; then
    PKG_MANAGER="zypper"
  elif command_exists pacman; then
    PKG_MANAGER="pacman"
  elif command_exists apk; then
    PKG_MANAGER="apk"
  elif command_exists xbps-install; then
    PKG_MANAGER="xbps"
  elif command_exists eopkg; then
    PKG_MANAGER="eopkg"
  elif command_exists emerge; then
    PKG_MANAGER="emerge"
  elif command_exists slackpkg; then
    PKG_MANAGER="slackpkg"
  else
    PKG_MANAGER="unknown"
  fi
}

print_detected_system() {
  printf '%b[INFO]%b Sistema: %s\n' "$BLUE" "$NC" "$SYSTEM_OS_PRETTY"
  printf '%b[INFO]%b Arquitetura: %s (%s)\n' "$BLUE" "$NC" "$SYSTEM_ARCH" "$SYSTEM_ARCH_RAW"
  printf '%b[INFO]%b Libc: %s %s\n' "$BLUE" "$NC" "$SYSTEM_LIBC" "${SYSTEM_LIBC_VERSION:-desconhecida}"
  printf '%b[INFO]%b Gerenciador: %s\n' "$BLUE" "$NC" "$PKG_MANAGER"
  printf '%b[INFO]%b Init: %s\n' "$BLUE" "$NC" "$SYSTEM_INIT"
  echo
}

refresh_package_index() {
  case "$PKG_MANAGER" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      ;;
    dnf)
      dnf -y makecache || true
      ;;
    microdnf)
      microdnf makecache -y || true
      ;;
    yum)
      yum -y makecache || true
      ;;
    zypper)
      zypper --non-interactive refresh || true
      ;;
    pacman)
      pacman -Sy --noconfirm
      ;;
    apk)
      apk update
      ;;
    xbps)
      xbps-install -S
      ;;
    eopkg)
      eopkg update-repo || true
      ;;
    emerge)
      # Não força emerge --sync: pode ser muito demorado em uma VPS recém-criada.
      true
      ;;
    slackpkg)
      slackpkg update || true
      ;;
    *)
      return 1
      ;;
  esac
}

install_package() {
  local pkg="$1"

  case "$PKG_MANAGER" in
    apt)
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$pkg"
      ;;
    dnf)
      dnf install -y "$pkg"
      ;;
    microdnf)
      microdnf install -y "$pkg"
      ;;
    yum)
      yum install -y "$pkg"
      ;;
    zypper)
      zypper --non-interactive install -y "$pkg"
      ;;
    pacman)
      pacman -S --noconfirm --needed "$pkg"
      ;;
    apk)
      apk add --no-cache "$pkg"
      ;;
    xbps)
      xbps-install -Sy "$pkg"
      ;;
    eopkg)
      eopkg install -y "$pkg"
      ;;
    emerge)
      emerge --quiet-build=y "$pkg"
      ;;
    slackpkg)
      slackpkg -batch=on -default_answer=y install "$pkg"
      ;;
    *)
      return 1
      ;;
  esac
}

try_packages_until_command() {
  local cmd="$1"
  shift

  command_exists "$cmd" && return 0

  local pkg=""
  for pkg in "$@"; do
    [[ -n "$pkg" ]] || continue
    install_package "$pkg" >/dev/null 2>&1 || true
    command_exists "$cmd" && return 0
  done

  return 1
}

ensure_base_tools() {
  # Ferramentas usadas pelo próprio instalador e pelo terminal fallback.
  case "$PKG_MANAGER" in
    apt)
      try_packages_until_command curl curl || try_packages_until_command wget wget || true
      try_packages_until_command ip iproute2 || true
      try_packages_until_command pgrep procps || true
      try_packages_until_command awk gawk mawk || true
      try_packages_until_command tar tar || true
      try_packages_until_command gzip gzip || true
      try_packages_until_command sshd openssh-server || true
      try_packages_until_command chpasswd passwd || true
      try_packages_until_command usermod passwd || true
      try_packages_until_command iptables iptables || true
      try_packages_until_command nft nftables || true
      install_package ca-certificates >/dev/null 2>&1 || true
      # Persistência clássica Debian/Ubuntu. É opcional porque nftables também é suportado.
      install_package iptables-persistent >/dev/null 2>&1 || true
      install_package netfilter-persistent >/dev/null 2>&1 || true
      ;;
    dnf|microdnf|yum)
      try_packages_until_command curl curl || try_packages_until_command wget wget || true
      try_packages_until_command ip iproute || true
      try_packages_until_command pgrep procps-ng procps || true
      try_packages_until_command awk gawk || true
      try_packages_until_command tar tar || true
      try_packages_until_command gzip gzip || true
      try_packages_until_command sshd openssh-server || true
      try_packages_until_command chpasswd shadow-utils || true
      try_packages_until_command usermod shadow-utils || true
      try_packages_until_command iptables iptables iptables-services || true
      try_packages_until_command nft nftables || true
      install_package ca-certificates >/dev/null 2>&1 || true
      install_package iptables-services >/dev/null 2>&1 || true
      ;;
    zypper)
      try_packages_until_command curl curl || try_packages_until_command wget wget || true
      try_packages_until_command ip iproute2 iproute || true
      try_packages_until_command pgrep procps || true
      try_packages_until_command awk gawk || true
      try_packages_until_command tar tar || true
      try_packages_until_command gzip gzip || true
      try_packages_until_command sshd openssh openssh-server || true
      try_packages_until_command chpasswd shadow || true
      try_packages_until_command usermod shadow || true
      try_packages_until_command iptables iptables || true
      try_packages_until_command nft nftables || true
      install_package ca-certificates >/dev/null 2>&1 || true
      ;;
    pacman)
      try_packages_until_command curl curl || try_packages_until_command wget wget || true
      try_packages_until_command ip iproute2 || true
      try_packages_until_command pgrep procps-ng || true
      try_packages_until_command awk gawk || true
      try_packages_until_command tar tar || true
      try_packages_until_command gzip gzip || true
      try_packages_until_command sshd openssh || true
      try_packages_until_command chpasswd shadow || true
      try_packages_until_command usermod shadow || true
      try_packages_until_command iptables iptables-nft iptables || true
      try_packages_until_command nft nftables || true
      install_package ca-certificates >/dev/null 2>&1 || true
      ;;
    apk)
      try_packages_until_command curl curl || try_packages_until_command wget wget || true
      try_packages_until_command ip iproute2 || true
      try_packages_until_command pgrep procps || true
      try_packages_until_command awk gawk || true
      try_packages_until_command tar tar || true
      try_packages_until_command gzip gzip || true
      try_packages_until_command sshd openssh-server openssh || true
      try_packages_until_command chpasswd shadow || true
      try_packages_until_command usermod shadow || true
      try_packages_until_command iptables iptables || true
      try_packages_until_command nft nftables || true
      install_package ca-certificates >/dev/null 2>&1 || true
      ;;
    xbps)
      try_packages_until_command curl curl || try_packages_until_command wget wget || true
      try_packages_until_command ip iproute2 || true
      try_packages_until_command pgrep procps-ng || true
      try_packages_until_command awk gawk || true
      try_packages_until_command tar tar || true
      try_packages_until_command gzip gzip || true
      try_packages_until_command sshd openssh || true
      try_packages_until_command chpasswd shadow || true
      try_packages_until_command usermod shadow || true
      try_packages_until_command iptables iptables || true
      try_packages_until_command nft nftables || true
      install_package ca-certificates >/dev/null 2>&1 || true
      ;;
    eopkg)
      try_packages_until_command curl curl || try_packages_until_command wget wget || true
      try_packages_until_command ip iproute2 iproute || true
      try_packages_until_command pgrep procps-ng procps || true
      try_packages_until_command awk gawk || true
      try_packages_until_command tar tar || true
      try_packages_until_command gzip gzip || true
      try_packages_until_command sshd openssh-server openssh || true
      try_packages_until_command chpasswd shadow || true
      try_packages_until_command usermod shadow || true
      try_packages_until_command iptables iptables || true
      try_packages_until_command nft nftables || true
      install_package ca-certificates >/dev/null 2>&1 || true
      ;;
    emerge)
      try_packages_until_command curl net-misc/curl || try_packages_until_command wget net-misc/wget || true
      try_packages_until_command ip sys-apps/iproute2 || true
      try_packages_until_command pgrep sys-process/procps || true
      try_packages_until_command awk sys-apps/gawk || true
      try_packages_until_command sshd net-misc/openssh || true
      try_packages_until_command chpasswd sys-apps/shadow || true
      try_packages_until_command iptables net-firewall/iptables || true
      try_packages_until_command nft net-firewall/nftables || true
      ;;
    *)
      printf '%b[AVISO]%b Gerenciador de pacotes não reconhecido; usando dependências já presentes.\n' "$YELLOW" "$NC"
      ;;
  esac
}

validate_required_dependencies() {
  local missing=()
  local cmd=""

  for cmd in awk sed grep cat cp chmod mkdir mktemp tee install; do
    command_exists "$cmd" || missing+=("$cmd")
  done

  if [[ "$ENABLE_ROOT_PASSWORD_LOGIN" == "true" ]]; then
    if ! command_exists sshd && [[ ! -x /usr/sbin/sshd ]]; then
      missing+=("sshd")
    fi
    command_exists chpasswd || missing+=("chpasswd")
    command_exists usermod || missing+=("usermod")
  fi

  if [[ "$OPEN_ALL_PORTS" == "true" ]]; then
    if ! command_exists iptables && ! command_exists nft; then
      missing+=("iptables/nft")
    fi
  fi

  if ((${#missing[@]} > 0)); then
    printf '%bDependências obrigatórias ausentes:%b %s\n' "$RED" "$NC" "${missing[*]}"
    return 1
  fi

  return 0
}

install_dependencies() {
  if [[ "$SYSTEM_KERNEL" != "Linux" ]]; then
    die "Este instalador completo de SSH/firewall foi projetado para Linux. Kernel detectado: $SYSTEM_KERNEL"
  fi

  if [[ "$PKG_MANAGER" != "unknown" ]]; then
    refresh_package_index || printf '%b[AVISO]%b Não foi possível atualizar os repositórios; continuando com os índices existentes.\n' "$YELLOW" "$NC"
  fi

  ensure_base_tools
  validate_required_dependencies
}

# ==========================================================
# TERMINAL FASTMOB / FASTFETCH
# ==========================================================

version_ge() {
  # Comparação sem sort -V para funcionar também em BusyBox/Alpine.
  local a="$1" b="$2"
  [[ -n "$a" && -n "$b" ]] || return 1
  awk -v A="$a" -v B="$b" 'BEGIN {
    split(A,a,"."); split(B,b,".");
    n=(length(a)>length(b)?length(a):length(b));
    for(i=1;i<=n;i++) {
      x=(a[i]==""?0:a[i])+0; y=(b[i]==""?0:b[i])+0;
      if(x>y) exit 0; if(x<y) exit 1;
    }
    exit 0;
  }'
}

fastfetch_upstream_arch_supported() {
  case "$SYSTEM_ARCH" in
    amd64|aarch64|armv7l|i686|ppc64le|s390x|riscv64|loongarch64) return 0 ;;
    *) return 1 ;;
  esac
}

download_file() {
  local url="$1" dest="$2"

  if command_exists curl; then
    curl -fL --retry 3 --retry-delay 1 --connect-timeout 20 "$url" -o "$dest"
    return $?
  fi

  if command_exists wget; then
    wget -O "$dest" "$url"
    return $?
  fi

  return 1
}

try_native_fastfetch_package() {
  case "$PKG_MANAGER" in
    apt|dnf|microdnf|yum|zypper|pacman|apk|xbps|eopkg)
      install_package fastfetch >/dev/null 2>&1 || return 1
      ;;
    emerge)
      install_package app-misc/fastfetch >/dev/null 2>&1 || return 1
      ;;
    *)
      return 1
      ;;
  esac

  command_exists fastfetch && fastfetch --version >/dev/null 2>&1
}

install_fastfetch_deb_asset() {
  command_exists dpkg || return 1
  command_exists apt-get || return 1
  fastfetch_upstream_arch_supported || return 1

  local asset_arch="$SYSTEM_ARCH"
  local suffix=""
  local tmpdir=""
  local file=""
  local url=""

  if [[ "$asset_arch" == "amd64" || "$asset_arch" == "aarch64" ]]; then
    if [[ "$SYSTEM_LIBC" == "glibc" && -n "$SYSTEM_LIBC_VERSION" ]] && ! version_ge "$SYSTEM_LIBC_VERSION" "2.35"; then
      suffix="-polyfilled"
    fi
  fi

  tmpdir="$(mktemp -d /tmp/fastmob-ff.XXXXXX)" || return 1
  file="$tmpdir/fastfetch.deb"
  url="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${asset_arch}${suffix}.deb"

  if ! download_file "$url" "$file"; then
    rm -rf "$tmpdir"
    return 1
  fi

  if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "$file"; then
    rm -rf "$tmpdir"
    return 1
  fi

  rm -rf "$tmpdir"
  command_exists fastfetch && fastfetch --version >/dev/null 2>&1
}

install_fastfetch_rpm_asset() {
  command_exists rpm || return 1
  fastfetch_upstream_arch_supported || return 1

  local asset_arch="$SYSTEM_ARCH"
  local suffix=""
  local tmpdir=""
  local file=""
  local url=""

  if [[ "$asset_arch" == "amd64" || "$asset_arch" == "aarch64" ]]; then
    if [[ "$SYSTEM_LIBC" == "glibc" && -n "$SYSTEM_LIBC_VERSION" ]] && ! version_ge "$SYSTEM_LIBC_VERSION" "2.35"; then
      suffix="-polyfilled"
    fi
  fi

  tmpdir="$(mktemp -d /tmp/fastmob-ff.XXXXXX)" || return 1
  file="$tmpdir/fastfetch.rpm"
  url="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${asset_arch}${suffix}.rpm"

  download_file "$url" "$file" || { rm -rf "$tmpdir"; return 1; }

  case "$PKG_MANAGER" in
    dnf)       dnf install -y "$file" ;;
    microdnf)  microdnf install -y "$file" ;;
    yum)       yum install -y "$file" ;;
    zypper)    zypper --non-interactive install -y "$file" ;;
    *)         rpm -Uvh --replacepkgs "$file" ;;
  esac
  local status=$?
  rm -rf "$tmpdir"
  [[ $status -eq 0 ]] || return $status

  command_exists fastfetch && fastfetch --version >/dev/null 2>&1
}

install_fastfetch_tar_asset() {
  fastfetch_upstream_arch_supported || return 1
  command_exists tar || return 1

  local asset_arch="$SYSTEM_ARCH"
  local asset="fastfetch-linux-${asset_arch}.tar.gz"
  local tmpdir=""
  local archive=""
  local ffbin=""

  # Upstream oferece builds polyfilled para amd64/aarch64 e build musl amd64.
  if [[ "$SYSTEM_LIBC" == "musl" && "$asset_arch" == "amd64" ]]; then
    asset="fastfetch-musl-amd64.tar.gz"
  elif [[ "$asset_arch" == "amd64" || "$asset_arch" == "aarch64" ]]; then
    if [[ "$SYSTEM_LIBC" == "glibc" && -n "$SYSTEM_LIBC_VERSION" ]] && ! version_ge "$SYSTEM_LIBC_VERSION" "2.35"; then
      asset="fastfetch-linux-${asset_arch}-polyfilled.tar.gz"
    fi
  fi

  tmpdir="$(mktemp -d /tmp/fastmob-ff.XXXXXX)" || return 1
  archive="$tmpdir/fastfetch.tar.gz"

  download_file "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/${asset}" "$archive" || {
    rm -rf "$tmpdir"
    return 1
  }

  tar -xzf "$archive" -C "$tmpdir" || {
    rm -rf "$tmpdir"
    return 1
  }

  ffbin="$(find "$tmpdir" -type f -name fastfetch -perm -u+x 2>/dev/null | head -n1 || true)"
  [[ -n "$ffbin" ]] || { rm -rf "$tmpdir"; return 1; }

  install -m 0755 "$ffbin" /usr/local/bin/fastfetch || {
    rm -rf "$tmpdir"
    return 1
  }

  rm -rf "$tmpdir"
  /usr/local/bin/fastfetch --version >/dev/null 2>&1
}

install_fastfetch() {
  if command_exists fastfetch && fastfetch --version >/dev/null 2>&1; then
    return 0
  fi

  # 1. Repositório nativo: melhor integração e compatibilidade com a distribuição.
  if try_native_fastfetch_package; then
    return 0
  fi

  # 2. Pacote oficial compatível com o formato do sistema.
  if [[ "$PKG_MANAGER" == "apt" ]] && install_fastfetch_deb_asset; then
    return 0
  fi

  case "$PKG_MANAGER" in
    dnf|microdnf|yum|zypper)
      if install_fastfetch_rpm_asset; then
        return 0
      fi
      ;;
  esac

  # 3. Tarball oficial: independe do gerenciador de pacotes.
  if install_fastfetch_tar_asset; then
    return 0
  fi

  # Não aborta o instalador. O wrapper Fastmob nativo assume automaticamente.
  return 1
}

write_fastmob_fastfetch_config() {
  mkdir -p "$FASTMOB_CONFIG_DIR"

  # Desktop / terminais largos: logo padrão da distribuição.
  cat > "$FASTMOB_CONFIG_FILE" <<'FASTFETCH'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "auto",
        "padding": { "right": 3 }
    },
    "display": {
        "separator": ": "
    },
    "modules": [
        { "type": "title", "format": "{user-name}@{host-name}" },
        { "type": "separator", "string": "----" },
        { "type": "os", "key": "OS" },
        { "type": "kernel", "key": "Kernel" },
        { "type": "uptime", "key": "Uptime" },
        { "type": "processes", "key": "Processes" },
        { "type": "packages", "key": "Packages" },
        { "type": "shell", "key": "Shell" },
        { "type": "separator", "string": "----" },
        {
            "type": "command",
            "key": "CPU",
            "text": "cores=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1); freq=$(awk '/cpu MHz/ {printf \\\"%.2f GHz\\\", $4/1000; exit}' /proc/cpuinfo 2>/dev/null); [ -n \\\"$freq\\\" ] && echo \\\"$cores cores @ $freq\\\" || echo \\\"$cores cores\\\""
        },
        { "type": "memory", "key": "Memory" },
        { "type": "disk", "key": "Disk (/)", "folders": "/" },
        { "type": "localip", "key": "IPv4", "format": "{ipv4}" },
        {
            "type": "command",
            "key": "IPv6",
            "text": "ipv6=$(ip -6 addr show scope global 2>/dev/null | awk '/inet6/ {print $2; exit}'); [ -n \\\"$ipv6\\\" ] && echo \\\"$ipv6\\\" || echo \\\"Not configured\\\""
        },
        "break",
        { "type": "custom", "format": "{#red} ______        _   {#white} __  __       _" },
        { "type": "custom", "format": "{#red}|  ____|      | |  {#white}|  \\\\/  |     | |" },
        { "type": "custom", "format": "{#red}| |__ __ _ ___| |_ {#white}| \\\\  / | ___ | |__" },
        { "type": "custom", "format": "{#red}|  __/ _` / __| __|{#white}| |\\\\/| |/ _ \\\\| '_ \\\\" },
        { "type": "custom", "format": "{#red}| | | (_| \\\\__ \\\\ |_ {#white}| |  | | (_) | |_) |" },
        { "type": "custom", "format": "{#red}|_|  \\\\__,_|___/\\\\__|{#white}|_|  |_|\\\\___/|_.__/" }
    ]
}
FASTFETCH

  # Mobile / terminais estreitos: usa a logo SMALL oficial embutida no Fastfetch.
  # Ex.: Ubuntu usa o ubuntu_small, evitando a arte grande que quebra no celular.
  cat > "$FASTMOB_MOBILE_CONFIG_FILE" <<'FASTFETCH_MOBILE'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "small",
        "padding": { "right": 2 }
    },
    "display": {
        "separator": ": "
    },
    "modules": [
        { "type": "title", "format": "{user-name}@{host-name}" },
        { "type": "separator", "string": "----" },
        { "type": "os", "key": "OS" },
        { "type": "kernel", "key": "Kernel" },
        { "type": "uptime", "key": "Uptime" },
        {
            "type": "command",
            "key": "CPU",
            "text": "cores=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1); freq=$(awk '/cpu MHz/ {printf \\\"%.2f GHz\\\", $4/1000; exit}' /proc/cpuinfo 2>/dev/null); [ -n \\\"$freq\\\" ] && echo \\\"$cores cores @ $freq\\\" || echo \\\"$cores cores\\\""
        },
        { "type": "memory", "key": "Memory" },
        { "type": "disk", "key": "Disk", "folders": "/" },
        { "type": "localip", "key": "IPv4", "format": "{ipv4}" },
        {
            "type": "command",
            "key": "IPv6",
            "text": "ipv6=$(ip -6 addr show scope global 2>/dev/null | awk '/inet6/ {print $2; exit}'); [ -n \\\"$ipv6\\\" ] && echo \\\"$ipv6\\\" || echo \\\"Not configured\\\""
        },
        { "type": "shell", "key": "Shell" },
        "break",
        { "type": "custom", "format": "{#red} ______        _   {#white} __  __       _" },
        { "type": "custom", "format": "{#red}|  ____|      | |  {#white}|  \\\\/  |     | |" },
        { "type": "custom", "format": "{#red}| |__ __ _ ___| |_ {#white}| \\\\  / | ___ | |__" },
        { "type": "custom", "format": "{#red}|  __/ _` / __| __|{#white}| |\\\\/| |/ _ \\\\| '_ \\\\" },
        { "type": "custom", "format": "{#red}| | | (_| \\\\__ \\\\ |_ {#white}| |  | | (_) | |_) |" },
        { "type": "custom", "format": "{#red}|_|  \\\\__,_|___/\\\\__|{#white}|_|  |_|\\\\___/|_.__/" }
    ]
}
FASTFETCH_MOBILE

  chmod 600 "$FASTMOB_CONFIG_FILE" "$FASTMOB_MOBILE_CONFIG_FILE"
}

write_fastmob_wrapper() {
  mkdir -p "$(dirname "$FASTMOB_WRAPPER")"

  cat > "$FASTMOB_WRAPPER" <<'WRAPPER'
#!/usr/bin/env bash
# Fastmob Terminal - layout responsivo usando logos oficiais small do Fastfetch.

if [[ -t 1 ]]; then
  RED=$'\e[1;31m'; GREEN=$'\e[1;32m'; BLUE=$'\e[1;34m'; WHITE=$'\e[1;37m'; NC=$'\e[0m'
else
  RED=""; GREEN=""; BLUE=""; WHITE=""; NC=""
fi

get_cols() {
  local cols=""
  cols="$(tput cols 2>/dev/null || true)"
  [[ "$cols" =~ ^[0-9]+$ ]] || cols="80"
  printf '%s\n' "$cols"
}

print_fastmob_logo() {
  printf '\n%b ______        _   %b __  __       _%b\n' "$RED" "$WHITE" "$NC"
  printf '%b|  ____|      | |  %b|  \\/  |     | |%b\n' "$RED" "$WHITE" "$NC"
  printf '%b| |__ __ _ ___| |_ %b| \\  / | ___ | |__%b\n' "$RED" "$WHITE" "$NC"
  printf '%b|  __/ _` / __| __|%b| |\\/| |/ _ \\| '\''_ \\%b\n' "$RED" "$WHITE" "$NC"
  printf '%b| | | (_| \\__ \\ |_ %b| |  | | (_) | |_) |%b\n' "$RED" "$WHITE" "$NC"
  printf '%b|_|  \\__,_|___/\\__|%b|_|  |_|\\___/|_.__/%b\n' "$RED" "$WHITE" "$NC"
}

print_fallback() {
  local os_id="linux" os_pretty="Linux"
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    os_id="${ID:-linux}"
    os_pretty="${PRETTY_NAME:-${NAME:-Linux}}"
  fi

  local user_now host_now kernel_now uptime_now cores freq cpu_now memory_now disk_now ipv4_now ipv6_now shell_now arch_now
  user_now="$(id -un 2>/dev/null || echo root)"
  host_now="$(hostname 2>/dev/null || echo VPS)"
  kernel_now="$(uname -sr 2>/dev/null || echo unknown)"
  arch_now="$(uname -m 2>/dev/null || echo unknown)"
  uptime_now="$(uptime -p 2>/dev/null | sed 's/^up //' || true)"
  cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)"
  freq="$(awk '/cpu MHz/ {printf "%.2f GHz", $4/1000; exit}' /proc/cpuinfo 2>/dev/null)"
  [[ -n "$freq" ]] && cpu_now="$cores cores @ $freq" || cpu_now="$cores cores"
  memory_now="$(awk '/MemTotal:/ {t=$2} /MemAvailable:/ {a=$2} END {if(t>0) printf "%.2f GiB / %.2f GiB (%.0f%%)", (t-a)/1048576, t/1048576, ((t-a)*100/t); else print "unknown"}' /proc/meminfo 2>/dev/null)"
  disk_now="$(df -hP / 2>/dev/null | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"
  ipv4_now="$(ip -o -4 addr show scope global 2>/dev/null | awk 'NR==1{print $4}')"
  ipv6_now="$(ip -o -6 addr show scope global 2>/dev/null | awk 'NR==1{print $4}')"
  shell_now="$(basename "${SHELL:-/bin/bash}")"
  [[ -n "$ipv4_now" ]] || ipv4_now="Not configured"
  [[ -n "$ipv6_now" ]] || ipv6_now="Not configured"

  printf '%b%s@%s%b\n' "$WHITE" "$user_now" "$host_now" "$NC"
  printf '%b------------------------------%b\n' "$GREEN" "$NC"

  # Fallback compacto. Na instalação normal, o Fastfetch usa a logo small oficial.
  case "${os_id,,}" in
    ubuntu|pop|linuxmint|elementary|zorin|neon)
      printf '%b        _%b\n' "$RED" "$NC"
      printf '%b    ---(_)%b\n' "$RED" "$NC"
      printf '%b _/  ---  \\%b\n' "$RED" "$NC"
      printf '%b(_) |   |%b\n' "$RED" "$NC"
      printf '%b \\  --- _/%b\n' "$RED" "$NC"
      printf '%b    ---(_)%b\n' "$RED" "$NC"
      ;;
    debian|raspbian|kali|parrot|devuan)
      printf '%b   _____%b\n' "$RED" "$NC"
      printf '%b  /  __ \\%b\n' "$RED" "$NC"
      printf '%b |  /    |%b\n' "$RED" "$NC"
      printf '%b |  \\__ |%b\n' "$RED" "$NC"
      printf '%b  \\____/%b\n' "$RED" "$NC"
      ;;
    arch|manjaro|endeavouros)
      printf '%b      /\\%b\n' "$BLUE" "$NC"
      printf '%b     /  \\%b\n' "$BLUE" "$NC"
      printf '%b    / /\\ \\%b\n' "$BLUE" "$NC"
      printf '%b   /_/  \\_\\%b\n' "$BLUE" "$NC"
      ;;
    *)
      printf '%b    .--.%b\n' "$WHITE" "$NC"
      printf '%b   |o_o |%b\n' "$WHITE" "$NC"
      printf '%b   |:_/ |%b\n' "$WHITE" "$NC"
      printf '%b  /     \\%b\n' "$WHITE" "$NC"
      ;;
  esac

  printf '%bOS:%b %s %s\n' "$RED" "$NC" "$os_pretty" "$arch_now"
  printf '%bKernel:%b %s\n' "$RED" "$NC" "$kernel_now"
  printf '%bUptime:%b %s\n' "$RED" "$NC" "$uptime_now"
  printf '%bCPU:%b %s\n' "$RED" "$NC" "$cpu_now"
  printf '%bMemory:%b %s\n' "$RED" "$NC" "$memory_now"
  printf '%bDisk:%b %s\n' "$RED" "$NC" "$disk_now"
  printf '%bIPv4:%b %s\n' "$RED" "$NC" "$ipv4_now"
  printf '%bIPv6:%b %s\n' "$RED" "$NC" "$ipv6_now"
  printf '%bShell:%b %s\n' "$RED" "$NC" "$shell_now"
  print_fastmob_logo
}

main() {
  local cols cfg base
  cols="$(get_cols)"
  base="${HOME:-/root}/.config/fastfetch"

  if command -v fastfetch >/dev/null 2>&1; then
    if [[ "$cols" -le 90 ]]; then
      cfg="$base/config-mobile.jsonc"
      if [[ -r "$cfg" ]] && fastfetch --config "$cfg" 2>/dev/null; then
        exit 0
      fi
    else
      cfg="$base/config.jsonc"
      if [[ -r "$cfg" ]] && fastfetch --config "$cfg" 2>/dev/null; then
        exit 0
      fi
    fi
  fi

  print_fallback
}

main "$@"
WRAPPER

  chmod 755 "$FASTMOB_WRAPPER"

  # Validação explícita do wrapper para não concluir a instalação com arquivo inválido.
  bash -n "$FASTMOB_WRAPPER"
}

ensure_bashrc_is_loaded_on_login() {
  local login_profile=""

  if [[ -f "${FASTMOB_ROOT_HOME}/.bash_profile" ]]; then
    login_profile="${FASTMOB_ROOT_HOME}/.bash_profile"
  elif [[ -f "${FASTMOB_ROOT_HOME}/.bash_login" ]]; then
    login_profile="${FASTMOB_ROOT_HOME}/.bash_login"
  else
    login_profile="${FASTMOB_ROOT_HOME}/.profile"
    touch "$login_profile"
  fi

  if grep -Eq '^[[:space:]]*(source|\.)[[:space:]].*\.bashrc' "$login_profile" 2>/dev/null; then
    return 0
  fi

  cat >> "$login_profile" <<'PROFILE'

# >>> FASTMOB: carregar .bashrc no login >>>
if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
# <<< FASTMOB: carregar .bashrc no login <<<
PROFILE
}

configure_fastmob_bashrc() {
  touch "$FASTMOB_BASHRC"

  sed -i '/# >>> FASTMOB TERMINAL >>>/,/# <<< FASTMOB TERMINAL <<</d' "$FASTMOB_BASHRC"

  # Desativa chamadas simples pré-existentes ao Fastfetch para evitar tela duplicada.
  sed -i -E '/^[[:space:]]*fastfetch([[:space:]].*)?$/ s/^/# FASTMOB substituiu: /' "$FASTMOB_BASHRC"

  cat >> "$FASTMOB_BASHRC" <<'BASHRC'

# >>> FASTMOB TERMINAL >>>
# Executa somente em Bash interativo de login SSH/console.
if [[ $- == *i* ]] && shopt -q login_shell; then
    if [[ -x /usr/local/bin/fastmob-terminal ]]; then
        /usr/local/bin/fastmob-terminal
    fi
fi
# <<< FASTMOB TERMINAL <<<
BASHRC

  chmod 600 "$FASTMOB_BASHRC"
  ensure_bashrc_is_loaded_on_login
}

configure_fastmob_terminal() {
  write_fastmob_fastfetch_config
  write_fastmob_wrapper

  if install_fastfetch; then
    printf 'Fastfetch instalado e validado com sucesso.\n'
  else
    printf '%b[AVISO]%b Fastfetch não está disponível para esta combinação de sistema/arquitetura.\n' "$YELLOW" "$NC"
    printf 'O terminal Fastmob continuará funcionando pelo modo nativo automático.\n'
  fi

  configure_fastmob_bashrc

  # Valida sintaxe e execução antes de concluir a etapa.
  bash -n "$FASTMOB_WRAPPER" || return 1
  "$FASTMOB_WRAPPER" >/dev/null 2>&1 || return 1
}

# ==========================================================
# DNS
# ==========================================================

configure_dns() {
  if command_exists resolvectl && command_exists systemctl && systemctl is-active --quiet systemd-resolved; then
    mkdir -p /etc/systemd/resolved.conf.d

    cat > /etc/systemd/resolved.conf.d/99-dns-publico.conf <<EOF
[Resolve]
DNS=${DNS_1} ${DNS_2}
FallbackDNS=9.9.9.9 208.67.222.222
EOF

    systemctl restart systemd-resolved || true
    return 0
  fi

  if [[ -L /etc/resolv.conf ]]; then
    printf '%b[AVISO]%b /etc/resolv.conf é um link simbólico. DNS não foi sobrescrito diretamente.\n' "$YELLOW" "$NC"
    return 0
  fi

  cat > /etc/resolv.conf <<EOF
nameserver ${DNS_1}
nameserver ${DNS_2}
EOF
}

# ==========================================================
# SSH ROOT LOGIN
# ==========================================================

ensure_sshd_include() {
  local main_config="/etc/ssh/sshd_config"

  mkdir -p /etc/ssh/sshd_config.d

  if grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$main_config"; then
    return 0
  fi

  if grep -nE '^[[:space:]]*Match[[:space:]]' "$main_config" >/dev/null 2>&1; then
    local first_match
    first_match="$(grep -nE '^[[:space:]]*Match[[:space:]]' "$main_config" | head -n1 | cut -d: -f1)"
    sed -i "${first_match}i Include /etc/ssh/sshd_config.d/*.conf" "$main_config"
  else
    printf '\nInclude /etc/ssh/sshd_config.d/*.conf\n' >> "$main_config"
  fi
}

normalize_existing_ssh_options() {
  local files=()

  [[ -f /etc/ssh/sshd_config ]] && files+=("/etc/ssh/sshd_config")

  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find /etc/ssh/sshd_config.d -maxdepth 1 -type f -name "*.conf" -print0 2>/dev/null || true)

  for file in "${files[@]}"; do
    [[ -f "$file" ]] || continue

    sed -i -E 's/^[#[:space:]]*PermitRootLogin[[:space:]].*/PermitRootLogin yes/g' "$file" || true
    sed -i -E 's/^[#[:space:]]*PasswordAuthentication[[:space:]].*/PasswordAuthentication yes/g' "$file" || true
    sed -i -E 's/^[#[:space:]]*KbdInteractiveAuthentication[[:space:]].*/KbdInteractiveAuthentication yes/g' "$file" || true
    sed -i -E 's/^[#[:space:]]*ChallengeResponseAuthentication[[:space:]].*/ChallengeResponseAuthentication yes/g' "$file" || true
    sed -i -E 's/^[#[:space:]]*UsePAM[[:space:]].*/UsePAM yes/g' "$file" || true
  done
}

configure_ssh_root_login() {
  [[ -f /etc/ssh/sshd_config ]] || die "Arquivo /etc/ssh/sshd_config não encontrado."

  ensure_sshd_include
  normalize_existing_ssh_options

  cat > /etc/ssh/sshd_config.d/01-root-password-login.conf <<'EOF'
# Gerado automaticamente pelo script liberar-vps-root-portas
PermitRootLogin yes
PasswordAuthentication yes
KbdInteractiveAuthentication yes
ChallengeResponseAuthentication yes
UsePAM yes
EOF

  local sshd_bin=""

  if command_exists sshd; then
    sshd_bin="$(command -v sshd)"
  elif [[ -x /usr/sbin/sshd ]]; then
    sshd_bin="/usr/sbin/sshd"
  else
    die "sshd não encontrado. Instale o OpenSSH Server."
  fi

  "$sshd_bin" -t
}

restart_ssh_service() {
  if command_exists systemctl; then
    if systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then
      systemctl restart ssh.service
      systemctl enable ssh.service >/dev/null 2>&1 || true
      return 0
    fi

    if systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service'; then
      systemctl restart sshd.service
      systemctl enable sshd.service >/dev/null 2>&1 || true
      return 0
    fi
  fi

  if command_exists rc-service; then
    if rc-service sshd status >/dev/null 2>&1 || [[ -x /etc/init.d/sshd ]]; then
      rc-service sshd restart
      command_exists rc-update && rc-update add sshd default >/dev/null 2>&1 || true
      return 0
    fi
    if rc-service ssh status >/dev/null 2>&1 || [[ -x /etc/init.d/ssh ]]; then
      rc-service ssh restart
      command_exists rc-update && rc-update add ssh default >/dev/null 2>&1 || true
      return 0
    fi
  fi

  if command_exists sv; then
    if [[ -d /var/service/sshd || -d /etc/sv/sshd ]]; then
      sv restart sshd && return 0
    fi
    if [[ -d /var/service/ssh || -d /etc/sv/ssh ]]; then
      sv restart ssh && return 0
    fi
  fi

  if command_exists service; then
    service ssh restart 2>/dev/null && return 0
    service sshd restart 2>/dev/null && return 0
  fi

  if [[ -x /etc/init.d/ssh ]]; then
    /etc/init.d/ssh restart && return 0
  fi

  if [[ -x /etc/init.d/sshd ]]; then
    /etc/init.d/sshd restart && return 0
  fi

  die "Não foi possível reiniciar o serviço SSH neste sistema de init (${SYSTEM_INIT})."
}

# ==========================================================
# FIREWALL / LIBERAÇÃO DE PORTAS
# ==========================================================

disable_firewall_frontends() {
  if command_exists ufw; then
    ufw --force disable || true
  fi

  if command_exists systemctl; then
    if systemctl list-unit-files | grep -q '^firewalld\.service'; then
      systemctl stop firewalld 2>/dev/null || true
      systemctl disable firewalld 2>/dev/null || true
    fi
  fi
}

flush_nftables() {
  if command_exists nft; then
    nft flush ruleset || true
  fi
}

configure_permissive_nftables() {
  if ! command_exists nft; then
    return 0
  fi

  cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0;
    policy accept;
  }

  chain forward {
    type filter hook forward priority 0;
    policy accept;
  }

  chain output {
    type filter hook output priority 0;
    policy accept;
  }
}
EOF

  nft -f /etc/nftables.conf || true

  if command_exists systemctl; then
    systemctl enable nftables >/dev/null 2>&1 || true
    systemctl restart nftables >/dev/null 2>&1 || true
  fi
}

flush_iptables_family() {
  local bin="$1"

  command_exists "$bin" || return 0

  for table in raw mangle nat filter security; do
    "$bin" -t "$table" -F 2>/dev/null || true
    "$bin" -t "$table" -X 2>/dev/null || true
    "$bin" -t "$table" -Z 2>/dev/null || true
  done

  "$bin" -P INPUT ACCEPT 2>/dev/null || true
  "$bin" -P OUTPUT ACCEPT 2>/dev/null || true
  "$bin" -P FORWARD ACCEPT 2>/dev/null || true
}

open_all_ports_now() {
  disable_firewall_frontends
  flush_nftables
  configure_permissive_nftables

  flush_iptables_family iptables
  flush_iptables_family ip6tables

  mkdir -p /etc/iptables

  if command_exists iptables-save; then
    iptables-save > /etc/iptables/rules.v4 || true
  fi

  if command_exists ip6tables-save; then
    ip6tables-save > /etc/iptables/rules.v6 || true
  fi

  if command_exists netfilter-persistent; then
    netfilter-persistent save || true
    if command_exists systemctl; then
      systemctl enable netfilter-persistent >/dev/null 2>&1 || true
    fi
  fi

  if command_exists service; then
    service iptables save 2>/dev/null || true
    service ip6tables save 2>/dev/null || true
  fi
}

# ==========================================================
# SENHA ROOT VISÍVEL E SEM CONFIRMAÇÃO
# ==========================================================

read_root_password() {
  local pass1=""

  while true; do
    printf '%b' "${YELLOW}DEFINA A SENHA ROOT 🔐: ${NC}"
    read -r pass1

    if [[ -z "$pass1" ]]; then
      printf '%b\n' "${RED}Erro: a senha não pode ser vazia.${NC}"
      continue
    fi

    ROOT_PASSWORD="$pass1"
    break
  done
}

set_root_password() {
  printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd

  passwd -u root >/dev/null 2>&1 || true
  usermod -s /bin/bash root >/dev/null 2>&1 || true
}

# ==========================================================
# FINAL
# ==========================================================

print_summary() {
  local public_ip=""

  if command_exists hostname; then
    public_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi

  echo
  printf '%b\n' "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
  printf '%b\n' "${GREEN}║                     PROCESSO CONCLUÍDO                    ║${NC}"
  printf '%b\n' "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
  printf '%b\n' "${GREEN}[ OK ]${WHITE} Login root por senha habilitado.${NC}"
  printf '%b\n' "${GREEN}[ OK ]${WHITE} Senha root definida com sucesso.${NC}"
  printf '%b\n' "${GREEN}[ OK ]${WHITE} Todas as portas IPv4/IPv6 foram liberadas na VPS.${NC}"
  printf '%b\n' "${GREEN}[ OK ]${WHITE} Regras salvas para persistir após reinicialização.${NC}"

  if [[ "$CONFIGURE_FASTMOB_TERMINAL" == "true" ]]; then
    printf '%b\n' "${GREEN}[ OK ]${WHITE} Terminal Fastmob configurado com logo automática do sistema e fallback nativo.${NC}"
  fi

  if [[ -n "$public_ip" ]]; then
    printf '%b\n' "${BLUE}[ INFO ]${WHITE} IP detectado: ${public_ip}${NC}"
  fi

  printf '%b\n' "${BLUE}[ INFO ]${WHITE} Sistema: ${SYSTEM_OS_PRETTY}${NC}"
  printf '%b\n' "${BLUE}[ INFO ]${WHITE} Arquitetura: ${SYSTEM_ARCH_RAW} -> ${SYSTEM_ARCH}${NC}"
  printf '%b\n' "${BLUE}[ INFO ]${WHITE} Libc: ${SYSTEM_LIBC} ${SYSTEM_LIBC_VERSION:-desconhecida}${NC}"
  printf '%b\n' "${BLUE}[ INFO ]${WHITE} Gerenciador: ${PKG_MANAGER}${NC}"
  printf '%b\n' "${BLUE}[ INFO ]${WHITE} Init: ${SYSTEM_INIT}${NC}"

  printf '%b\n' "${BLUE}[ INFO ]${WHITE} Backup salvo em: ${BACKUP_DIR}${NC}"
  printf '%b\n' "${BLUE}[ INFO ]${WHITE} Log salvo em: ${LOG_FILE}${NC}"
  echo
  printf '%b\n' "${YELLOW}Atenção:${NC} se a provedora tiver firewall externo/security group, libere as portas também no painel da VPS."
}

main() {
  log_init
  print_banner

  is_root || die "Execute como root. Use: sudo -i"

  detect_system
  print_detected_system

  run_step "Criando backup das configurações atuais" make_backup

  if [[ "$INSTALL_DEPENDENCIES" == "true" ]]; then
    run_step "Instalando/verificando dependências" install_dependencies
  fi

  if [[ "$CONFIGURE_FASTMOB_TERMINAL" == "true" ]]; then
    run_step "Instalando/configurando terminal Fastmob" configure_fastmob_terminal
  fi

  if [[ "$CONFIGURE_DNS" == "true" ]]; then
    run_step "Configurando DNS público" configure_dns
  fi

  if [[ "$ENABLE_ROOT_PASSWORD_LOGIN" == "true" ]]; then
    run_step "Configurando SSH para login root por senha" configure_ssh_root_login
  fi

  if [[ "$OPEN_ALL_PORTS" == "true" ]]; then
    run_step "Liberando todas as portas da VPS" open_all_ports_now
  fi

  read_root_password
  run_step "Atualizando senha root" set_root_password

  if [[ "$ENABLE_ROOT_PASSWORD_LOGIN" == "true" ]]; then
    run_step "Reiniciando serviço SSH com segurança" restart_ssh_service
  fi

  unset ROOT_PASSWORD || true

  print_summary
}

main "$@"