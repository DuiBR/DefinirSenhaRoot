#!/usr/bin/env bash
# By DuiBR - Otimizado
# Script para habilitar login root por senha e liberar todas as portas da VPS
# Compatível principalmente com Debian/Ubuntu

set -Eeuo pipefail
IFS=$'\n\t'

# ==========================================================
# CONFIGURAÇÕES
# ==========================================================

INSTALL_DEPENDENCIES="true"
CONFIGURE_DNS="true"
ENABLE_ROOT_PASSWORD_LOGIN="true"
OPEN_ALL_PORTS="true"

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

  printf '%b\n' "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
  printf '%b\n' "${RED}║                 🚨 AVISO DE SEGURANÇA 🚨                  ║${NC}"
  printf '%b\n' "${WHITE}║ Este script habilita login root por senha e libera portas. ║${NC}"
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
      ca-certificates

    return 0
  fi

  if command_exists dnf; then
    dnf install -y \
      openssh-server \
      iptables-services \
      nftables \
      ca-certificates || true
    return 0
  fi

  if command_exists yum; then
    yum install -y \
      openssh-server \
      iptables-services \
      nftables \
      ca-certificates || true
    return 0
  fi

  printf '%b[AVISO]%b Gerenciador de pacotes não detectado. Continuando sem instalar dependências.\n' "$YELLOW" "$NC"
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