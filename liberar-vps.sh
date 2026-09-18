#!/usr/bin/env bash
# By DuiBR - Otimizado
# Script para habilitar login root por senha, liberar portas e personalizar o terminal Fastmob
# Compatível principalmente com Debian/Ubuntu e com suporte ao Fastfetch em outras distribuições

set -Eeuo pipefail
IFS=$'\n\t'

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
FASTMOB_BASHRC="${FASTMOB_ROOT_HOME}/.bashrc"

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

  (
    "$@"
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
# DEPENDÊNCIAS
# ==========================================================

install_dependencies() {
  if command_exists apt-get; then
    export DEBIAN_FRONTEND=noninteractive

    if command_exists debconf-set-selections; then
      echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections || true
      echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections || true
    fi

    apt-get update -y
    apt-get install -y \
      openssh-server \
      iptables \
      iptables-persistent \
      netfilter-persistent \
      nftables \
      ca-certificates \
      curl \
      iproute2 \
      procps

    return 0
  fi

  if command_exists dnf; then
    dnf install -y \
      openssh-server \
      iptables-services \
      nftables \
      ca-certificates \
      curl \
      iproute \
      procps-ng || true
    return 0
  fi

  if command_exists yum; then
    yum install -y \
      openssh-server \
      iptables-services \
      nftables \
      ca-certificates \
      curl \
      iproute \
      procps-ng || true
    return 0
  fi

  printf '%b[AVISO]%b Gerenciador de pacotes não detectado. Continuando sem instalar dependências.\n' "$YELLOW" "$NC"
}

# ==========================================================
# TERMINAL FASTMOB / FASTFETCH
# ==========================================================

fastfetch_asset_arch() {
  local arch=""

  if command_exists dpkg; then
    arch="$(dpkg --print-architecture 2>/dev/null || true)"
  fi

  if [[ -z "$arch" ]]; then
    arch="$(uname -m 2>/dev/null || true)"
  fi

  case "$arch" in
    amd64|x86_64)
      printf '%s\n' "amd64"
      ;;
    arm64|aarch64)
      printf '%s\n' "aarch64"
      ;;
    armhf|armv7l|armv7*)
      printf '%s\n' "armv7l"
      ;;
    i386|i486|i586|i686)
      printf '%s\n' "i686"
      ;;
    s390x)
      printf '%s\n' "s390x"
      ;;
    *)
      return 1
      ;;
  esac
}

install_fastfetch() {
  if command_exists fastfetch; then
    return 0
  fi

  command_exists curl || die "curl não encontrado. Ative INSTALL_DEPENDENCIES ou instale curl."

  local ff_arch=""
  ff_arch="$(fastfetch_asset_arch)" || die "Arquitetura não suportada automaticamente para instalar o Fastfetch: $(uname -m)."

  local base_url="https://github.com/fastfetch-cli/fastfetch/releases/latest/download"
  local tmp_pkg=""

  if command_exists apt-get && command_exists dpkg; then
    tmp_pkg="$(mktemp --suffix=.deb)"
    curl -fL --retry 3 --connect-timeout 15 \
      "${base_url}/fastfetch-linux-${ff_arch}.deb" \
      -o "$tmp_pkg"

    apt-get install -y "$tmp_pkg"
    rm -f "$tmp_pkg"
    command_exists fastfetch || die "Fastfetch foi instalado, mas o comando não foi encontrado."
    return 0
  fi

  if command_exists dnf; then
    dnf install -y fastfetch >/dev/null 2>&1 || {
      tmp_pkg="$(mktemp --suffix=.rpm)"
      curl -fL --retry 3 --connect-timeout 15 \
        "${base_url}/fastfetch-linux-${ff_arch}.rpm" \
        -o "$tmp_pkg"
      dnf install -y "$tmp_pkg"
      rm -f "$tmp_pkg"
    }
    command_exists fastfetch || die "Não foi possível instalar o Fastfetch com dnf."
    return 0
  fi

  if command_exists yum; then
    yum install -y fastfetch >/dev/null 2>&1 || {
      tmp_pkg="$(mktemp --suffix=.rpm)"
      curl -fL --retry 3 --connect-timeout 15 \
        "${base_url}/fastfetch-linux-${ff_arch}.rpm" \
        -o "$tmp_pkg"
      yum install -y "$tmp_pkg"
      rm -f "$tmp_pkg"
    }
    command_exists fastfetch || die "Não foi possível instalar o Fastfetch com yum."
    return 0
  fi

  if command_exists apk; then
    apk add --no-cache fastfetch
    command_exists fastfetch || die "Não foi possível instalar o Fastfetch com apk."
    return 0
  fi

  if command_exists pacman; then
    pacman -Sy --noconfirm fastfetch
    command_exists fastfetch || die "Não foi possível instalar o Fastfetch com pacman."
    return 0
  fi

  die "Gerenciador compatível para instalar o Fastfetch não encontrado."
}

write_fastmob_fastfetch_config() {
  mkdir -p "$FASTMOB_CONFIG_DIR"

  cat > "$FASTMOB_CONFIG_FILE" <<'FASTFETCH'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "auto"
    },
    "display": {
        "separator": ": "
    },
    "modules": [
        {
            "type": "title",
            "format": "{user-name}@{host-name}"
        },
        {
            "type": "separator",
            "string": "----"
        },
        {
            "type": "os",
            "key": "OS"
        },
        {
            "type": "kernel",
            "key": "Kernel"
        },
        {
            "type": "uptime",
            "key": "Uptime"
        },
        {
            "type": "processes",
            "key": "Processes"
        },
        {
            "type": "packages",
            "key": "Packages"
        },
        {
            "type": "shell",
            "key": "Shell"
        },
        {
            "type": "separator",
            "string": "----"
        },
        {
            "type": "command",
            "key": "CPU",
            "text": "cores=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1); freq=$(awk '/cpu MHz/ {printf \"%.2f GHz\", $4/1000; exit}' /proc/cpuinfo 2>/dev/null); if [ -n \"$freq\" ]; then [ \"$cores\" -eq 1 ] && echo \"$cores core @ $freq\" || echo \"$cores cores @ $freq\"; else [ \"$cores\" -eq 1 ] && echo \"$cores core\" || echo \"$cores cores\"; fi"
        },
        {
            "type": "memory",
            "key": "Memory"
        },
        {
            "type": "disk",
            "key": "Disk (/)",
            "folders": "/"
        },
        {
            "type": "localip",
            "key": "IPv4",
            "format": "{ipv4}"
        },
        {
            "type": "command",
            "key": "IPv6",
            "text": "ipv6=$(ip -6 addr show scope global 2>/dev/null | awk '/inet6/ {print $2; exit}'); [ -n \"$ipv6\" ] && echo \"$ipv6\" || echo \"Not configured\""
        },
        {
            "type": "command",
            "key": " ",
            "text": "pgrep -x 'apt|apt-get|dpkg|pacman|yum|dnf|zypper' >/dev/null 2>&1 && printf '\\033[1;33m(!) Warning: System update running in background\\033[0m\\n' || true"
        },
        "break",
        {
            "type": "custom",
            "format": "{#red} ______        _   {#white} __  __       _"
        },
        {
            "type": "custom",
            "format": "{#red}|  ____|      | |  {#white}|  \\/  |     | |"
        },
        {
            "type": "custom",
            "format": "{#red}| |__ __ _ ___| |_ {#white}| \\  / | ___ | |__"
        },
        {
            "type": "custom",
            "format": "{#red}|  __/ _` / __| __|{#white}| |\\/| |/ _ \\| '_ \\"
        },
        {
            "type": "custom",
            "format": "{#red}| | | (_| \\__ \\ |_ {#white}| |  | | (_) | |_) |"
        },
        {
            "type": "custom",
            "format": "{#red}|_|  \\__,_|___/\\__|{#white}|_|  |_|\\___/|_.__/"
        }
    ]
}
FASTFETCH

  chmod 600 "$FASTMOB_CONFIG_FILE"
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

  # Remove apenas blocos Fastmob criados por versões anteriores deste instalador.
  sed -i '/# >>> FASTMOB TERMINAL >>>/,/# <<< FASTMOB TERMINAL <<</d' "$FASTMOB_BASHRC"

  # Evita duas telas quando a imagem da provedora já possuía um "fastfetch" simples.
  sed -i -E 's/^([[:space:]]*)fastfetch[[:space:]]*$/\1# fastfetch substituído pelo terminal Fastmob/' "$FASTMOB_BASHRC"

  cat >> "$FASTMOB_BASHRC" <<'BASHRC'

# >>> FASTMOB TERMINAL >>>
# Exibe a identidade da distribuição + informações do servidor + logo Fastmob
# somente em shells Bash interativos de login.
if [[ $- == *i* ]] && shopt -q login_shell; then
    if command -v fastfetch >/dev/null 2>&1; then
        fastfetch
    fi
fi
# <<< FASTMOB TERMINAL <<<
BASHRC

  chmod 600 "$FASTMOB_BASHRC"
  ensure_bashrc_is_loaded_on_login
}

configure_fastmob_terminal() {
  install_fastfetch
  write_fastmob_fastfetch_config
  configure_fastmob_bashrc
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
    if systemctl list-unit-files | grep -q '^ssh\.service'; then
      systemctl restart ssh.service
      systemctl enable ssh.service >/dev/null 2>&1 || true
      return 0
    fi

    if systemctl list-unit-files | grep -q '^sshd\.service'; then
      systemctl restart sshd.service
      systemctl enable sshd.service >/dev/null 2>&1 || true
      return 0
    fi
  fi

  service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || die "Não foi possível reiniciar o serviço SSH."
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
    printf '%b\n' "${GREEN}[ OK ]${WHITE} Terminal Fastmob configurado com Fastfetch e logo automática do sistema.${NC}"
  fi

  if [[ -n "$public_ip" ]]; then
    printf '%b\n' "${BLUE}[ INFO ]${WHITE} IP detectado: ${public_ip}${NC}"
  fi

  printf '%b\n' "${BLUE}[ INFO ]${WHITE} Backup salvo em: ${BACKUP_DIR}${NC}"
  printf '%b\n' "${BLUE}[ INFO ]${WHITE} Log salvo em: ${LOG_FILE}${NC}"
  echo
  printf '%b\n' "${YELLOW}Atenção:${NC} se a provedora tiver firewall externo/security group, libere as portas também no painel da VPS."
}

main() {
  log_init
  print_banner

  is_root || die "Execute como root. Use: sudo -i"

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