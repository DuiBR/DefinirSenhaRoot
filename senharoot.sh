#!/bin/bash
# By @DuiBR (versão final: senha VISÍVEL + não aceita ENTER vazio + barra animada)
set -euo pipefail

# Função: barra de progresso animada enquanto PID roda
progress_bar() {
  local pid=$1
  local label="$2"
  local width=36
  local chars_fill='█'
  local chars_empty='░'
  local start=$(date +%s)
  local phase=0

  printf "\n\033[1;34m%s...\033[0m\n" "$label"
  # Enquanto o processo existir, atualiza a barra
  while kill -0 "$pid" 2>/dev/null; do
    phase=$(( (phase + 6) % 101 ))
    local filled=$(( (phase * width) / 100 ))
    local empty=$(( width - filled ))
    local bar_filled="$(printf "%${filled}s" | tr ' ' "${chars_fill}")"
    local bar_empty="$(printf "%${empty}s" | tr ' ' "${chars_empty}")"
    local elapsed=$(( $(date +%s) - start ))
    printf "\r\033[1;33m%3d%%\033[0m |%s%s| \033[1;36m%02dm%02ds\033[0m" \
      "$phase" "$bar_filled" "$bar_empty" $((elapsed/60)) $((elapsed%60))
    sleep 0.12
  done

  # Concluir visualmente
  local elapsed=$(( $(date +%s) - start ))
  local bar_filled="$(printf "%${width}s" | tr ' ' "${chars_fill}")"
  printf "\r\033[1;32m100%%\033[0m |%s| \033[1;36m%02dm%02ds\033[0m\n" "$bar_filled" $((elapsed/60)) $((elapsed%60))
}

# Mensagem inicial
cat <<EOF
\033[1;31m⚠ ATENÇÃO ⚠\033[0m
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

# 1) Configurar DNS (resolv.conf)
(
  cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
) & pid=$!; progress_bar $pid "Configurando DNS (resolv.conf)" >>"$LOGFILE" 2>&1 || true

# 2) apt update
(
  # apt pode demorar; saída silenciada para manter a barra limpa
  apt update -y >/dev/null 2>&1 || true
) & pid=$!; progress_bar $pid "Atualizando pacotes (apt update)" >>"$LOGFILE" 2>&1 || true

# Função utilitária: garante diretiva no sshd_config (cria se não existir)
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

# 3) Configurar SSH (cria backup antes)
(
  if [[ -f /etc/ssh/sshd_config ]]; then
    cp -f /etc/ssh/sshd_config /etc/ssh/sshd_config.bak_"$(date +%s)"
  fi
  ensure_sshd_directive /etc/ssh/sshd_config PermitRootLogin yes
  ensure_sshd_directive /etc/ssh/sshd_config PasswordAuthentication yes

  if [[ -d /etc/ssh/sshd_config.d ]]; then
    for f in /etc/ssh/sshd_config.d/*.conf; do
      [[ -f "$f" ]] || continue
      ensure_sshd_directive "$f" PermitRootLogin yes
      ensure_sshd_directive "$f" PasswordAuthentication yes
    done
  fi
) & pid=$!; progress_bar $pid "Aplicando configurações SSH" >>"$LOGFILE" 2>&1 || true

# 4) Reiniciar SSH
(
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart sshd.service 2>/dev/null || systemctl restart ssh.service 2>/dev/null || true
  else
    service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true
  fi
) & pid=$!; progress_bar $pid "Reiniciando serviço SSH" >>"$LOGFILE" 2>&1 || true

# 5) Firewall / iptables
(
  iptables -F || true
  iptables -P INPUT ACCEPT || true
  iptables -P OUTPUT ACCEPT || true
  for p in 81 80 443 8799 8080 1194; do
    iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport "$p" -j ACCEPT
  done
  mkdir -p /etc/iptables
  if command -v iptables-save >/dev/null 2>&1; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
  fi
) & pid=$!; progress_bar $pid "Aplicando regras de firewall (iptables)" >>"$LOGFILE" 2>&1 || true

# Solicitar senha root (VISÍVEL) — não aceita ENTER vazio (repete até digitar algo)
echo -e "\n\033[1;32mDefina a senha root 🔐 (VISÍVEL). Não aperte ENTER vazio.\033[0m"
while true; do
  read -p "Senha: " senha
  if [[ -z "${senha// /}" ]]; then
    echo -e "\033[1;31m❌ Senha não pode ser vazia. Digite novamente.\033[0m"
    continue
  fi
  break
done

# Atualiza senha root
echo "root:$senha" | chpasswd

# Final
echo -e "\n\033[1;32m✅ SENHA ROOT DEFINIDA COM SUCESSO!\033[0m"
echo -e "\033[1;32m✅ Firewall configurado e regras salvas (se iptables-save disponível).\033[0m"
echo -e "\033[1;33mLog em: $LOGFILE\033[0m"
