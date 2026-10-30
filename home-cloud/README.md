# Nuvem local com computador antigo

Transforma um PC/notebook antigo em um servidor de nuvem pessoal (estilo Google Drive), acessível em casa e de qualquer lugar.

## Arquitetura

```
 Celular / Notebook (fora de casa)
          │  Tailscale (VPN criptografada, sem abrir portas no roteador)
          ▼
 ┌──────────────── PC antigo (Ubuntu Server) ────────────────┐
 │  Docker                                                   │
 │   ├─ Nextcloud  :8080  → arquivos, fotos, agenda, contatos │
 │   ├─ MariaDB           → banco de dados                   │
 │   ├─ Redis             → cache (deixa mais rápido)        │
 │   ├─ Cron              → tarefas em segundo plano         │
 │   └─ Portainer  :9443  → painel para gerenciar containers │
 │                                                           │
 │  /srv/nuvem  → todos os dados                             │
 └───────────────────────────────────────────────────────────┘
          │  backup diário
          ▼
     HD externo
```

| Escolha | Motivo |
|---|---|
| **Ubuntu Server** (sem interface gráfica) | Leve, sobra RAM para os serviços |
| **Docker Compose** | Tudo em um arquivo; fácil atualizar, mover ou refazer |
| **Nextcloud** | Substitui Drive/Fotos/Agenda; tem app para Android, iOS e PC |
| **Tailscale** | Acesso remoto seguro sem expor o servidor na internet; funciona mesmo com CGNAT (comum em operadoras brasileiras) |

## Requisitos mínimos

| Item | Mínimo | Recomendado |
|---|---|---|
| CPU | 64 bits, 2 núcleos | 4 núcleos |
| RAM | 4 GB | 8 GB |
| Disco do sistema | 32 GB | SSD (maior ganho de desempenho em PC antigo) |
| Disco de dados | o HD que tiver | HD separado do sistema |
| Rede | Wi-Fi | **Cabo** ligado ao roteador |

> Com 2 GB de RAM funciona, mas troque o Nextcloud por algo mais leve (ex.: Syncthing ou File Browser).

---

## Etapa 1 — Instalar o sistema

1. Baixe o **Ubuntu Server LTS** em <https://ubuntu.com/download/server>.
2. Grave em um pendrive com o **Balena Etcher** ou **Rufus**.
3. Dê boot pelo pendrive no PC antigo e instale. Durante a instalação:
   - Marque **Install OpenSSH server**.
   - Anote o usuário e a senha.
4. Após reiniciar, veja o IP: `ip a` (algo como `192.168.0.100`).
5. **No roteador**, reserve esse IP para o servidor (DHCP reservation / IP fixo), para ele não mudar.

A partir daqui, use o servidor pelo seu computador principal:

```bash
ssh seu-usuario@192.168.0.100
```

## Etapa 2 — (Opcional) Montar o HD de dados

Se tiver um segundo HD para os arquivos:

```bash
lsblk                                   # identifique o disco, ex.: /dev/sdb
sudo mkfs.ext4 /dev/sdb1                # ATENÇÃO: apaga o conteúdo do disco
sudo mkdir -p /srv/nuvem
echo "UUID=$(sudo blkid -s UUID -o value /dev/sdb1) /srv/nuvem ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
sudo mount -a
```

## Etapa 3 — Preparar o servidor

Copie esta pasta para o servidor e rode o script de preparação (instala Docker, Tailscale, firewall e atualizações automáticas):

```bash
git clone https://github.com/dev-3rick/dev-3rick.git
cd dev-3rick/home-cloud
sudo bash scripts/01-preparar-servidor.sh
```

Depois conecte o Tailscale e saia do SSH para recarregar as permissões:

```bash
sudo tailscale up
exit
```

Instale o Tailscale também no celular e no seu computador (<https://tailscale.com/download>) com a **mesma conta**. Veja o IP do servidor na rede Tailscale com `tailscale ip -4` (começa com `100.`).

## Etapa 4 — Configurar e subir a nuvem

```bash
cd dev-3rick/home-cloud
cp .env.example .env
nano .env
```

No `.env`:
- Troque **todas** as senhas (gere com `openssl rand -base64 24`).
- Em `NC_TRUSTED_DOMAINS`, coloque o IP local e o IP do Tailscale do servidor.

Suba os serviços:

```bash
docker compose up -d
docker compose ps
```

A primeira inicialização leva alguns minutos.

## Etapa 5 — Acessar

| Serviço | Em casa | De fora (Tailscale ligado) |
|---|---|---|
| Nextcloud | `http://192.168.0.100:8080` | `http://100.x.x.x:8080` |
| Portainer | `https://192.168.0.100:9443` | `https://100.x.x.x:9443` |

- **Nextcloud:** entre com `NC_ADMIN_USER` / `NC_ADMIN_PASSWORD`. Crie um usuário comum para o dia a dia.
- **Portainer:** crie a senha de admin no primeiro acesso (em até 5 min após subir).
- **Celular:** instale o app Nextcloud e ative o upload automático de fotos.

## Etapa 6 — Backup

Sem backup não é nuvem, é risco. Conecte um HD externo e agende o script:

```bash
sudo crontab -e
```

Adicione a linha (ajuste os caminhos):

```
0 3 * * * /bin/bash /home/seu-usuario/dev-3rick/home-cloud/scripts/backup.sh /mnt/backup >> /var/log/nuvem-backup.log 2>&1
```

O backup guarda 7 dias; cópias diárias reaproveitam arquivos não alterados (hard links), então ocupam pouco espaço extra.

---

## Manutenção

| Tarefa | Comando |
|---|---|
| Ver status | `docker compose ps` |
| Ver logs | `docker compose logs -f nextcloud` |
| Atualizar serviços | `docker compose pull && docker compose up -d` |
| Atualizar o sistema | automático (unattended-upgrades) |
| Comando do Nextcloud | `docker compose exec -u www-data nextcloud php occ status` |
| Uso de recursos | `docker stats` |

## Problemas comuns

| Sintoma | Solução |
|---|---|
| "Acesso por domínio não confiável" | Adicione o endereço em `NC_TRUSTED_DOMAINS` **e** rode `docker compose exec -u www-data nextcloud php occ config:system:set trusted_domains 3 --value=ENDERECO` (a variável só vale na 1ª instalação) |
| Notebook desliga ao fechar a tampa | O script já trata; confira `HandleLidSwitch=ignore` em `/etc/systemd/logind.conf` |
| Lento | Use SSD para o sistema, cabo de rede e reduza apps ativos no Nextcloud |
| Não acessa de fora | Confirme que o Tailscale está ligado nos dois aparelhos: `tailscale status` |

## Próximos passos (opcional)

- **HTTPS com domínio próprio:** `tailscale serve` ou Cloudflare Tunnel.
- **Mais serviços:** Jellyfin (filmes), Immich (fotos), Vaultwarden (senhas), Home Assistant.
- **Energia:** configure o BIOS para ligar sozinho após queda de energia (*Restore on AC Power Loss*).
