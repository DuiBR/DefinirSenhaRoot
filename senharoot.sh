#!/bin/bash
# By DuiBR
# Pequeno script para permissao de autenticacao root
set -euo pipefail

# Define as cores
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

# Função de spinner de loading
spinner() {
    local pid=$!
    local delay=0.15
    local spin='|/-\'
    while ps -p $pid > /dev/null 2>&1; do
        for i in $(seq 0 3); do
            printf "\r${YELLOW}[AGUARDE]${RED} %s" "${spin:$i:1}"
            sleep $delay
        done
    done
    printf "\r${GREEN}✔ Concluído${NC}\n"
}

# --- AVISO DE SEGURANÇA ---
echo -e "${RED}╔════════════════════════════════════════════════════╗"
echo -e "${RED}║          🚨 AVISO DE SEGURANÇA 🚨                  ║"
echo -e "${WHITE}║ Este script ativa login root por senha.            ║"
echo -e "${WHITE}║ Isso é inseguro. Considere usar chaves SSH em vez de senha. ║"
echo -e "${RED}╚════════════════════════════════════════════════════╝"
sleep 2

# Verifica root
if [[ "$(whoami)" != "root" ]]; then
  echo -e "${RED}🚫 EXECUTE COMO USUÁRIO ROOT (${YELLOW}sudo -i${NC})${NC}"
  exit 1
fi

# Limpa regras iptables
{
  iptables -F
} & spinner "Limpando regras iptables"

# Atualiza resolv.conf
{
  echo 'nameserver 1.1.1.1' > /etc/resolv.conf
  echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
} & spinner "Configurando servidores DNS"

# Atualiza repositórios
{
  apt update -y >/dev/null 2>&1 || true
} & spinner "Atualizando repositórios"

# Configura sshd_config
{
  [[ $(grep -c "prohibit-password" /etc/ssh/sshd_config) != '0' ]] && {
    sed -i "s/prohibit-password/yes/g" /etc/ssh/sshd_config
  }
  [[ $(grep -c "without-password" /etc/ssh/sshd_config) != '0' ]] && {
    sed -i "s/without-password/yes/g" /etc/ssh/sshd_config
  }
  [[ $(grep -c "#PermitRootLogin" /etc/ssh/sshd_config) != '0' ]] && {
    sed -i "s/#PermitRootLogin/PermitRootLogin/g" /etc/ssh/sshd_config
  }
  [[ $(grep -c "PasswordAuthentication" /etc/ssh/sshd_config) = '0' ]] && {
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
  }
  [[ $(grep -c "PasswordAuthentication no" /etc/ssh/sshd_config) != '0' ]] && {
    sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config
  }
  [[ $(grep -c "#PasswordAuthentication no" /etc/ssh/sshd_config) != '0' ]] && {
    sed -i "s/#PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config
  }
  sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
} & spinner "Configurando autenticação SSH"

# Reinicia serviço SSH
{
  service ssh restart >/dev/null
} & spinner "Reiniciando serviço SSH"

# Configura regras iptables
{
  iptables -F
  iptables -P INPUT ACCEPT
  iptables -P OUTPUT ACCEPT
  iptables -A INPUT -p tcp --dport 81 -j ACCEPT
  iptables -A INPUT -p tcp --dport 80 -j ACCEPT
  iptables -A INPUT -p tcp --dport 443 -j ACCEPT
  iptables -A INPUT -p tcp --dport 8799 -j ACCEPT
  iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
  iptables -A INPUT -p tcp --dport 1194 -j ACCEPT
  iptables-save > /etc/iptables/rules.v4
} & spinner "Configurando regras de firewall"

# Solicita senha de root (visível)
while true; do
  echo -n "${YELLOW}DEFINA A SENHA ROOT 🔐: ${NC}"
  read -r senha
  if [[ -z "$senha" ]]; then
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
echo -e "\n${GREEN}════════════════════════════════════════════════════"
echo -e "${GREEN}[ OK ! ]${WHITE} - SENHA DEFINIDA! ✅${NC}"
echo -e "${GREEN}[ OK ! ]${WHITE} - Todas as portas liberadas com sucesso. Tráfego permitido em todas as portas de entrada e saída. ✅${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"