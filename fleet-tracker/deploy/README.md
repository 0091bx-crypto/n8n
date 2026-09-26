# Run n8n for the fleet tracker with Docker

This sets up n8n on your own server with automatic HTTPS, so the rental
laptops can reach it over the internet. It uses Docker and Caddy.

## What you need

- A server or VPS you can reach with SSH (1 vCPU and 1 GB RAM is enough for a
  small fleet). Ubuntu is a good choice.
- A domain name, for example `n8n.yourcompany.com`, with a DNS **A record**
  that points to the server's public IP.
- Ports **80** and **443** open to the internet on the server.

## Steps

1. Install Docker on the server:
   ```sh
   curl -fsSL https://get.docker.com | sh
   ```

2. Copy the `fleet-tracker/deploy` folder to the server, then go into it:
   ```sh
   cd deploy
   ```

3. Make your config file:
   ```sh
   cp .env.example .env
   openssl rand -hex 24   # copy the output for the next step
   ```
   Edit `.env` and set `DOMAIN`, `ACME_EMAIL`, `TZ`, and paste the random
   value into `N8N_ENCRYPTION_KEY`.

4. Start n8n:
   ```sh
   docker compose up -d
   ```
   Caddy gets a certificate for your domain in about a minute. Watch progress
   with `docker compose logs -f caddy`.

5. Open `https://<your-domain>` in a browser. Create the n8n owner account
   (email and password). This login protects the editor.

You now have n8n running. Next, import the tracker workflows: see the main
[README](../README.md), section "Set up n8n". Your check-in URL will be
`https://<your-domain>/webhook/fleet/checkin`.

## Everyday commands

```sh
docker compose logs -f n8n      # view logs
docker compose pull && docker compose up -d   # update to the latest n8n
docker compose down             # stop (data is kept in the volumes)
```

## Back up

Your data lives in the `n8n_data` Docker volume: the workflows, the data
tables (device and event history), and the credentials. Back it up regularly:

```sh
docker run --rm -v deploy_n8n_data:/data -v "$PWD":/backup alpine \
  tar czf /backup/n8n-backup-$(date +%F).tar.gz -C /data .
```

Keep `.env` safe too. If you lose `N8N_ENCRYPTION_KEY`, the saved credentials
can no longer be read.

## Larger fleets

SQLite (the default here) is fine for a few hundred laptops. For more, add a
PostgreSQL service and point n8n at it with the `DB_*` environment variables.
Ask if you want a compose file with PostgreSQL included.
