#!/bin/bash
# By @DuiBR (versão corrigida)
# Pequeno script para permitir autenticação root por senha (USE COM CAUTELA)
set -euo pipefail

# --- AVISO DE SEGURANÇA ---
cat <<EOF
AVISO: este script ativa login root por senha (PermitRootLogin yes + PasswordAuthentication yes).
Isto é inseguro. Considere usar chaves SSH em vez de senha.
EOF

# Verifica root
if [[ "$(id -u)" -ne 0 ]]; then
  echo -e "\033[1;31mEXECUTE COMO USUÁRIO ROOT (ex: sudo -i)\033[0m"
  exit 1
fi

# Atualiza resolv.conf (ATENÇÃO: pode ser sobrescrito por DHCP/systemd-resolved)
if command -v resolvconf >/dev/null 2>&1 || systemctl is-active --quiet systemd-resolved; then
  echo "Observação: /etc/resolv.conf pode ser gerenciado pelo sistema (systemd-resolved/DHCP)."
fi
cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# Atualiza repositórios
apt update -y >/dev/null 2>&1 || true

# Função utilitária para garantir diretiva no sshd_config
ensure_sshd_directive() {
  local file="$1"
  local directive="$2"
  local value="$3"  # ex "yes"
  if [[ -f "$file" ]]; then
    # Se existir a diretiva (comentada ou não), substitui ou descomenta
    if grep -q -E "^[#[:space:]]*${directive}" "$file"; then
      sed -i -r "s|^[#[:space:]]*(${directive}).*|${directive} ${value}|g" "$file"
    else
      # adiciona no final
      echo "${directive} ${value}" >> "$file"
    fi
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
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart sshd.service 2>/dev/null || systemctl restart ssh.service 2>/dev/null || {
    echo "Falha ao reiniciar via systemctl, tentando service..."
    service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true
  }
else
  service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true
fi

# Limpa regras e abre portas selecionadas
iptables -F || true
iptables -P INPUT ACCEPT || true
iptables -P OUTPUT ACCEPT || true

# Regras explícitas (adapte conforme necessário)
for p in 81 80 443 8799 8080 1194; do
  iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport "$p" -j ACCEPT
done

# Salva regras (cria diretório se necessário)
iptables_dir="/etc/iptables"
mkdir -p "$iptables_dir"
if command -v iptables-save >/dev/null 2>&1; then
  iptables-save > "$iptables_dir/rules.v4" 2>/dev/null || echo "Falha ao salvar regras em $iptables_dir/rules.v4"
else
  echo "iptables-save não encontrado; instale iptables-persistent se desejar salvar regras permanentemente."
fi

# Solicita senha de root (oculta)
echo -ne "\033[1;32mDEFINA A SENHA ROOT 🔐\033[1;37m: "
read -s senha
echo
if [[ -z "${senha// /}" ]]; then
  echo -e "\n\033[1;31mSENHA Inválida ! 🚫\033[0m"
  exit 1
fi

# Atualiza senha root
echo "root:$senha" | chpasswd

echo -e "\n\033[1;31m[ \033[1;33mOK ! \033[1;31m]\033[1;37m - \033[1;32mSENHA DEFINIDA ! ✅ \033[0m"
echo -e "\033[1;31m[ \033[1;33mOK ! \033[1;31m]\033[1;37m - \033[1;32mRegras de firewall aplicadas (verifique /etc/iptables/rules.v4). ✅ \033[0m"
