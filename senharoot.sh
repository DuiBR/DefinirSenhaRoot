#!/bin/bash
# By @DuiBR (versão com spinner + senha não aceita ENTER vazio, sem confirmação)
set -euo pipefail

# Spinner: recebe PID do processo a ser monitorado
spinner() {
    local pid=$1
    local delay=0.12
    local spin='|/-\'
    printf " "
    while kill -0 "$pid" 2>/dev/null; do
        for i in 0 1 2 3; do
            printf "\b%s" "${spin:i:1}"
            sleep $delay
        done
    done
    printf "\b\033[1;32m✔\033[0m\n"
}

# --- AVISO ---
cat <<EOF
\033[1;31m⚠ AVISO DE SEGURANÇA ⚠\033[0m
Este script ativa login root por senha (PermitRootLogin yes + PasswordAuthentication yes).
Isto é INSEGURO. Prefira chaves SSH. Use apenas se souber o que está fazendo.
EOF

# Verifica root
if [[ "$(id -u)" -ne 0 ]]; then
  echo -e "\n\033[1;31mEXECUTE COMO ROOT (ex: sudo -i)\033[0m"
  exit 1
fi

# Ajusta resolv.conf (atenção: pode ser sobrescrito por systemd/DHCP)
echo -e "\n\033[1;34mConfigurando DNS...\033[0m"
(
  cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
) & pid=$!; spinner $pid

# Atualiza repositórios
echo -e "\n\033[1;34mAtualizando pacotes (apt update)...\033[0m"
( apt update -y >/dev/null 2>&1 || true ) & pid=$!; spinner $pid

# Função para garantir diretivas no sshd_config
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

echo -e "\n\033[1;34mConfigurando SSH (permit root/password)...\033[0m"
(
  ensure_sshd_directive /etc/ssh/sshd_config PermitRootLogin yes
  ensure_sshd_directive /etc/ssh/sshd_config PasswordAuthentication yes
  if [[ -d /etc/ssh/sshd_config.d ]]; then
    for f in /etc/ssh/sshd_config.d/*.conf; do
      [[ -f "$f" ]] || continue
      ensure_sshd_directive "$f" PermitRootLogin yes
      ensure_sshd_directive "$f" PasswordAuthentication yes
    done
  fi
) & pid=$!; spinner $pid

# Reinicia SSH
echo -e "\n\033[1;34mReiniciando serviço SSH...\033[0m"
(
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart sshd.service 2>/dev/null || systemctl restart ssh.service 2>/dev/null || true
  else
    service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true
  fi
) & pid=$!; spinner $pid

# Configura firewall
echo -e "\n\033[1;34mAplicando regras de firewall (iptables)...\033[0m"
(
  iptables -F || true
  iptables -P INPUT ACCEPT || true
  iptables -P OUTPUT ACCEPT || true
  for p in 81 80 443 8799 8080 1194; do
    iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport "$p" -j ACCEPT
  done
  mkdir -p /etc/iptables
  command -v iptables-save >/dev/null 2>&1 && iptables-save > /etc/iptables/rules.v4 || true
) & pid=$!; spinner $pid

# Solicita senha root (não aceita ENTER vazio, sem confirmação)
echo -e "\n\033[1;32mDefina a senha root 🔐 (não ficará visível). Não aperte ENTER vazio.\033[0m"
while true; do
  # -s oculta, -p mostra o prompt
  read -s -p "Senha: " senha
  echo
  # remove espaços em branco; considera vazia se só houver espaços
  if [[ -z "${senha// /}" ]]; then
    echo -e "\033[1;31m❌ Senha não pode ser vazia. Digite novamente.\033[0m"
    continue
  fi
  # aceita a senha (sem confirmação)
  break
done

# Atualiza senha root
echo "root:$senha" | chpasswd

echo -e "\n\033[1;32m✅ SENHA ROOT DEFINIDA COM SUCESSO!\033[0m"
echo -e "\033[1;32m✅ Firewall configurado e regras salvas (verifique /etc/iptables/rules.v4).\033[0m"
