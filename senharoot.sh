#!/bin/bash
# By @DuiBR (versão com barra de progresso "gráfica" + senha visível + não aceita ENTER vazio)
set -euo pipefail

# ---------- Função: barra de progresso animada ----------
# Usa PID do processo em background e um rótulo
progress_bar() {
  local pid=$1
  local label="$2"
  local width=40                # largura da barra
  local chars_fill='█'          # caractere de preenchimento
  local chars_empty='░'         # caractere vazio
  local start=$(date +%s)
  local i=0
  local phase=0

  # Imprime linha inicial do rótulo
  printf "\n\033[1;34m%s...\033[0m\n" "$label"

  # Loop enquanto o processo estiver rodando
  while kill -0 "$pid" 2>/dev/null; do
    # phase sobe de 0..100 e volta, criando sensação de movimento/progresso
    phase=$(( (phase + 7) % 101 ))
    # Preenche a barra proporcional ao phase
    local filled=$(( (phase * width) / 100 ))
    local empty=$(( width - filled ))
    # Monta as partes da barra
    local bar_filled="$(printf "%${filled}s" | tr ' ' "${chars_fill}")"
    local bar_empty="$(printf "%${empty}s" | tr ' ' "${chars_empty}")"
    local elapsed=$(( $(date +%s) - start ))
    # Mostrar porcentagem, barra e tempo
    printf "\r\033[1;33m%3d%%\033[0m |%s%s| \033[1;36m%02dm%02ds\033[0m" \
      "$phase" "$bar_filled" "$bar_empty" $((elapsed/60)) $((elapsed%60))
    sleep 0.12
  done

  # Finaliza com 100% rapidamente
  local elapsed=$(( $(date +%s) - start ))
  local bar_filled="$(printf "%${width}s" | tr ' ' "${chars_fill}")"
  printf "\r\033[1;32m100%%\033[0m |%s| \033[1;36m%02dm%02ds\033[0m\n" "$bar_filled" $((elapsed/60)) $((elapsed%60))
}

# ---------- Mensagem inicial de aviso ----------
cat <<EOF
\033[1;31m⚠ AVISO DE SEGURANÇA ⚠\033[0m
Este script ativa login root por senha (PermitRootLogin yes + PasswordAuthentication yes).
Isto é INSEGURO. Prefira chaves SSH. Use apenas se souber o que está fazendo.
EOF

# ---------- Verifica root ----------
if [[ "$(id -u)" -ne 0 ]]; then
  echo -e "\n\033[1;31mEXECUTE COMO ROOT (ex: sudo -i)\033[0m"
  exit 1
fi

# ---------- Log (opcional) ----------
LOGFILE="/tmp/crazy_vpn_script.log"
: > "$LOGFILE"

# ---------- Função utilitária para garantir diretivas no sshd_config ----------
ensure_sshd_directive() {
  local file="$1"
  local directive="$2"
  local value="$3"
  [[ -f "$file" ]] || return 0
  if grep -q -E "^[#[:space:]]*${directive}" "$file"; then
    sed -i -r "s|^[#[:space:]]*(${directive}).*|${directive} ${value}|g" "$file"
  else
    echo "${directive} ${value}" >> "$file"
  fi
}

# ---------- Etapa: Configurar DNS (resolv.conf) ----------
(
  cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
) & pid=$!; progress_bar $pid "Configurando DNS (resolv.conf)" >> "$LOGFILE" 2>&1 || true

# ---------- Etapa: apt update ----------
(
  apt update -y >/dev/null 2>&1 || true
) & pid=$!; progress_bar $pid "Atualizando pacotes (apt update)" >> "$LOGFILE" 2>&1 || true

# ---------- Etapa: Configurar SSH (permit root + password) ----------
(
  # Faz backup antes de alterar (segurança)
  if [[ -f /etc/ssh/sshd_config ]]; then
    cp -f /etc/ssh/sshd_config /etc/ssh/sshd_config.bak_$(date +%s)
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
) & pid=$!; progress_bar $pid "Aplicando configurações SSH" >> "$LOGFILE" 2>&1 || true

# ---------- Etapa: Reiniciar SSH ----------
(
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart sshd.service 2>/dev/null || systemctl restart ssh.service 2>/dev/null || true
  else
    service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true
  fi
) & pid=$!; progress_bar $pid "Reiniciando serviço SSH" >> "$LOGFILE" 2>&1 || true

# ---------- Etapa: Firewall / iptables ----------
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
) & pid=$!; progress_bar $pid "Aplicando regras de firewall (iptables)" >> "$LOGFILE" 2>&1 || true

# ---------- Solicitar senha root (visível) - não aceita ENTER vazio ----------
echo -e "\n\033[1;32mDefina a senha root 🔐 (visível). Não aperte ENTER vazio.\033[0m"
while true; do
  read -p "Senha: " senha
  # remove espaços em branco
  if [[ -z "${senha// /}" ]]; then
    echo -e "\033[1;31m❌ Senha não pode ser vazia. Digite novamente.\033[0m"
    continue
  fi
  # Aceita senha (sem confirmação)
  break
done

# ---------- Atualiza senha root ----------
echo "root:$senha" | chpasswd

# ---------- Final ----------
echo -e "\n\033[1;32m✅ SENHA ROOT DEFINIDA COM SUCESSO!\033[0m"
echo -e "\033[1;32m✅ Firewall configurado e regras salvas (se iptables-save estiver disponível).\033[0m"
echo -e "\033[1;33mLog de execução: $LOGFILE\033[0m"
