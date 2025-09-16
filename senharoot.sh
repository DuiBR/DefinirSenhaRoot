#!/bin/bash
# By @DuiBR (versão revisada: aviso amarelo + animação antiga + senha visível)
set -euo pipefail

# Função: animação simples de carregamento (de 0 a 100%)
loading() {
    local label="$1"
    local width=30
    local progress=0

    echo -e "\n\033[1;34m${label}...\033[0m"
    while [ $progress -le 100 ]; do
        local filled=$((progress * width / 100))
        local empty=$((width - filled))
        local bar="$(printf "%${filled}s" | tr ' ' '█')"
        bar="$bar$(printf "%${empty}s" | tr ' ' '░')"
        printf "\r\033[1;32m%3d%%\033[0m |%s|" "$progress" "$bar"
        sleep 0.05
        progress=$((progress+2))
    done
    echo
}

# Mensagem inicial em amarelo
cat <<EOF
\033[1;33m⚠ ATENÇÃO ⚠\033[0m
Este script ativa login root por senha (PermitRootLogin yes + PasswordAuthentication yes).
Isto é inseguro. Prefira chaves SSH. Use com cautela.
EOF

# Verifica root
if [[ "$(id -u)" -ne 0 ]]; then
  echo -e "\n\033[1;31mEXECUTE COMO ROOT (ex: sudo -i)\033[0m"
  exit 1
fi

LOGFILE="/tmp/crazy_vpn_script.log"
: > "$LOGFILE"

# 1) Configurar DNS
( 
  cat > /etc/resolv.conf <<EOT
nameserver 1.1.1.1
nameserver 8.8.8.8
EOT
) >>"$LOGFILE" 2>&1
loading "Configurando DNS (resolv.conf)"

# 2) apt update
(
  apt update -y >/dev/null 2>&1 || true
) >>"$LOGFILE" 2>&1
loading "Atualizando pacotes (apt update)"

# Função utilitária
ensure_sshd_directive() {
  local file="$1"
  local directive="$2"
  local value="$3"
  [[ -f "$file" ]] || return 0
  if grep -q -E "^[#[:space:]]*${directive}" "$file"; then
    sed -i -r "s|^[#[:space:]]*(${directive}).*|${directive} ${value}|g" "$file"
  else
    echo "${directive} ${value}" >>"$file"
  fi
}

# 3) Configurar SSH
(
  [[ -f /etc/ssh/sshd_config ]] && cp -f /etc/ssh/sshd_config /etc/ssh/sshd_config.bak_"$(date +%s)"
  ensure_sshd_directive /etc/ssh/sshd_config PermitRootLogin yes
  ensure_sshd_directive /etc/ssh/sshd_config PasswordAuthentication yes
  if [[ -d /etc/ssh/sshd_config.d ]]; then
    for f in /etc/ssh/sshd_config.d/*.conf; do
      [[ -f "$f" ]] || continue
      ensure_sshd_directive "$f" PermitRootLogin yes
      ensure_sshd_directive "$f" PasswordAuthentication yes
    done
  fi
) >>"$LOGFILE" 2>&1
loading "Aplicando configurações SSH"

# 4) Reiniciar SSH
(
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart sshd.service 2>/dev/null || systemctl restart ssh.service 2>/dev/null || true
  else
    service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true
  fi
) >>"$LOGFILE" 2>&1
loading "Reiniciando serviço SSH"

# 5) Firewall
(
  iptables -F || true
  iptables -P INPUT ACCEPT || true
  iptables -P OUTPUT ACCEPT || true
  for p in 81 80 443 8799 8080 1194; do
    iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport "$p" -j ACCEPT
  done
  mkdir -p /etc/iptables
  command -v iptables-save >/dev/null 2>&1 && iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
) >>"$LOGFILE" 2>&1
loading "Aplicando regras de firewall (iptables)"

# 6) Definir senha root (VISÍVEL, não aceita vazio)
echo -e "\n\033[1;32mDefina a senha root 🔐 (visível, não pode ser vazia):\033[0m"
while true; do
  read -p "Senha: " senha
  if [[ -z "${senha// /}" ]]; then
    echo -e "\033[1;31m❌ Senha não pode ser vazia. Digite novamente.\033[0m"
  else
    break
  fi
done
echo "root:$senha" | chpasswd

# Final
echo -e "\n\033[1;32m✅ SENHA ROOT DEFINIDA COM SUCESSO!\033[0m"
echo -e "\033[1;32m✅ Firewall configurado e regras salvas.\033[0m"
echo -e "\033[1;33mLog em: $LOGFILE\033[0m"
