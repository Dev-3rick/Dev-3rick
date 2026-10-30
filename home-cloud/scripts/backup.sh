#!/usr/bin/env bash
# Backup do Nextcloud: banco de dados + arquivos, com retenção de 7 dias.
# Uso: sudo bash scripts/backup.sh /caminho/do/hd-externo
# Agendar (todo dia às 3h): sudo crontab -e
#   0 3 * * * /bin/bash /caminho/home-cloud/scripts/backup.sh /mnt/backup >> /var/log/nuvem-backup.log 2>&1
set -euo pipefail

DESTINO="${1:?Informe a pasta de destino do backup}"
PASTA="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PASTA"

set -a; source .env; set +a

DATA="$(date +%F)"
ALVO="$DESTINO/nuvem-$DATA"
mkdir -p "$ALVO"

occ() { docker compose exec -T -u www-data nextcloud php occ "$@"; }

echo "==> Ativando modo de manutenção"
occ maintenance:mode --on
trap 'occ maintenance:mode --off' EXIT

echo "==> Exportando banco de dados"
docker compose exec -T db mariadb-dump --single-transaction \
  -u root -p"$DB_ROOT_PASSWORD" nextcloud | gzip > "$ALVO/banco.sql.gz"

echo "==> Copiando arquivos"
# Reaproveita o backup anterior via hard links: só o que mudou ocupa espaço novo
ANTERIOR="$(find "$DESTINO" -maxdepth 1 -name 'nuvem-*' -type d ! -path "$ALVO" | sort | tail -n 1)"
rsync -a --delete ${ANTERIOR:+--link-dest="$ANTERIOR/nextcloud"} \
  "$DATA_DIR/nextcloud/" "$ALVO/nextcloud/"
cp .env "$ALVO/env.backup"

echo "==> Removendo backups com mais de 7 dias"
find "$DESTINO" -maxdepth 1 -name 'nuvem-*' -type d -mtime +7 -exec rm -rf {} +

echo "==> Backup concluído em $ALVO"
