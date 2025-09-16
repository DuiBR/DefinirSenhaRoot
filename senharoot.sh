#!/bin/bash
# By @DuiBR (versão corrigida)
# Pequeno script para permitir autenticação root por senha (USE COM CAUTELA)
set -euo pipefail

# Verifica se o terminal suporta cores
if tput colors >/dev/null 2>&1 && [[ -t 1 ]]; then
  RED='\033[1;31m'
  GREEN='\033[1;32m'
  YELLOW='\033[1;33m'
  WHITE='\033[1;37m'
  NC='\033[0m' # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  WHITE=''
  NC=''
fi

# Função de spinner de loading
spinner() {
    local pid=$!
    local delay=0.15
    local spin='|/-\'
    while ps -p $pid > /dev/null 2>&1; do
        for i in $(seq 0 3); do
            printf "\r\033[1;33m[AGUARDE]\033[0m %s" "${spin:$i:1}"
            sleep $delay
        done
    done
    printf "\r\033[1;32m✔ Concluído\033[0m\n"
}

# --- AVISO DE SEGURANÇA ---
cat <<EOF
${RED}╔════════════════════════════════════════════════════╗${NC}
${RED}║          🚨 AVISO DE SEGURANÇA 🚨                  ║${NC}
${WHITE}║ Este script ativa login root por senha.            ║${NC}
${WHITE}║ Isso é inseguro. Considere usar chaves SSH em vez de senha. ${NC}
${RED}╚════════════════════════════════════════════════════╝${NC}
EOF
sleep 2

# Verifica root
if [[ "$(id -u)" -ne 0 ]]; then
  echo -e "${RED}🚫 EXECUTE COMO USUÁRIO ROOT (ex: sudo -i)${NC}"
  exit 1
fi

# Atualiza resolv.conf (ATENÇÃO: pode ser sobrescrito por DHCP/systemd-resolved)
{
  if command -v resolvconf >/dev/null 2>&1 || systemctl is-active --quiet systemd-resolved; then
    echo -e "${YELLOW}Observação: /etc/resolv.conf pode ser gerenciado pelo sistema (systemd-resolved/DHCP).${NC}"
  fi
  cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
} & spinner "Configurando servidores DNS"

# Atualiza repositórios
{
  apt update -y >/dev/null 2>&1 || true
} & spinner "Atualizando repositórios"

# Função utilitária para garantir diretiva no sshd_config
ensure_sshd_directive() {
  local file="$1"
  local directive="$2"
  local value="$3"  # ex "yes"
  if [[ -f "$file" ]]; then
    {
      # Se existir a diretiva (comentada ou não), substitui ou descomenta
      if grep -q -E "^[#[:space:]]*${directive}" "$file"; then
        sed -i -r "s|^[#[:space:]]*(${directive}).*|${directive} ${value}|g" "$file"
      else
        # adiciona no final
        echo "${directive} ${value}" >> "$file"
      fi
    } & spinner "Configurando ${directive} em ${file}"
  fi
}

# Aplica nas configurações possíveis
ensure_sshd_directive /etc/ssh/sshd_config PermitRootLogin yes
ensure_sshd_directive /etc/ssh/sshd_config PasswordAuthentication yes

# Também verifica diretórios de drop-in (ex: cloud images)
if [[ -d /etc/ssh/sshd_config.d ]]; then
  for f in /etc/ssh/sshd_config.d/*.conf; do
    [[ -f "$f" ]] || continue
    ensure_sshd_directive "$f" PermitRootLogin yes
    ensure_sshd_directive "$f" PasswordAuthentication yes
  done
fi

# Reinicia serviço ssh/sshd
{
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart sshd.service 2>/dev/null || systemctl restart ssh.service 2>/dev/null || {
      echo -e "${YELLOW}Falha ao reiniciar via systemctl, tentando service...${NC}"
      service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true
    }
  else
    service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true
  fi
} & spinner "Reiniciando serviço SSH"

# Limpa regras e abre portas selecionadas
{
  iptables -F || true
  iptables -P INPUT ACCEPT || true
  iptables -P OUTPUT ACCEPT || true
  for p in 81 80 443 8799 8080 1194; do
    iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport "$p" -j ACCEPT
  done
} & spinner "Configurando regras de firewall"

# Salva regras (cria diretório se necessário)
{
  iptables_dir="/etc/iptables"
  mkdir -p "$iptables_dir"
  if command -v iptables-save >/dev/null 2>&1; then
    iptables-save > "$iptables_dir/rules.v4" 2>/dev/null || echo -e "${RED}Falha ao salvar regras em $iptables_dir/rules.v4${NC}"
  else
    echo -e "${YELLOW}iptables-save não encontrado; instale iptables-persistent se desejar salvar regras permanentemente.${NC}"
  fi
} & spinner "Salvando regras de firewall"

# Solicita senha de root (visível)
while true; do
  if [ -n "$YELLOW" ]; then
    echo -n "${YELLOW}DEFINA A SENHA ROOT 🔐: ${NC}"
  else
    echo -n "DEFINA A SENHA ROOT 🔐: "
  fi
  read -r senha
  if [[ -z "${senha// /}" ]]; then
    echo -e "${RED}Erro: A senha não pode ser vazia! 🚫${NC}"
    continue
  fi
  break
done

# Atualiza senha root
{
  echo "root:$senha" | chpasswd
} & spinner "Atualizando senha root"

# Mensagem final
echo -e "\n${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}[ OK ! ]${WHITE} - SENHA DEFINIDA! ✅${NC}"
echo -e "${GREEN}[ OK ! ]${WHITE} - Regras de firewall aplicadas (verifique /etc/iptables/rules.v4). ✅${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"