# soma-webhook

SOMA alarm event receiver. Runs on Contabo VPS behind nginx.

## Endpoints

- `POST /alarm-event` — receive alarm events from soma-alarm Android app
- `GET /health` — liveness check
- `GET /events?since=ISO&limit=N` — query recent events

## Deploy

```bash
scp -r . root@217.77.6.197:/opt/soma-webhook/
ssh root@217.77.6.197 'cd /opt/soma-webhook && npm install --production && pm2 start index.js --name soma-webhook && pm2 save'
```

## Environment

Copy `.env.example` to `.env` and fill in:
- `DISCORD_CHANNEL_ID` — enables Discord delivery (without it, messages queue in pending_discord table)
- `DISCORD_BOT_TOKEN` — bot token for posting

## Data

SQLite at `events.db`. Auto-prunes events older than 30 days.
