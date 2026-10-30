#!/usr/bin/env bash
# Prepara um Ubuntu Server / Debian recém-instalado para rodar a nuvem local.
# Uso: sudo bash scripts/01-preparar-servidor.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Execute como root: sudo bash $0" >&2
  exit 1
fi

USUARIO="${SUDO_USER:-$USER}"

echo "==> [1/5] Atualizando o sistema"
apt-get update
apt-get -y upgrade
apt-get -y install curl ca-certificates ufw unattended-upgrades rsync

echo "==> [2/5] Ativando atualizações automáticas de segurança"
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "==> [3/5] Instalando Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
usermod -aG docker "$USUARIO"
systemctl enable --now docker

echo "==> [4/5] Instalando Tailscale (acesso remoto seguro)"
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

echo "==> [5/5] Configurando firewall"
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow from 192.168.0.0/16 to any port 8080 proto tcp   # Nextcloud na rede local
ufw allow from 192.168.0.0/16 to any port 9443 proto tcp   # Portainer na rede local
ufw allow in on tailscale0                                 # tudo via Tailscale
ufw --force enable

# Impede o notebook de suspender ao fechar a tampa
sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
systemctl restart systemd-logind

cat <<EOF

Pronto. Próximos passos:
  1. sudo tailscale up          (abra o link exibido e faça login)
  2. Saia e entre de novo no SSH (para o grupo docker valer)
  3. cp .env.example .env && nano .env
  4. docker compose up -d
EOF
