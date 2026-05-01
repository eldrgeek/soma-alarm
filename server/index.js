const express = require('express');
const Database = require('better-sqlite3');
const path = require('path');

const PORT = process.env.PORT || 4243;
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'events.db');
const DISCORD_CHANNEL_ID = process.env.DISCORD_CHANNEL_ID || '';
const DISCORD_BOT_TOKEN = process.env.DISCORD_BOT_TOKEN || '';
const RETENTION_DAYS = 30;
const VERSION = require('./package.json').version;

const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

db.exec(`
  CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT NOT NULL,
    title TEXT NOT NULL,
    action TEXT NOT NULL,
    scheduled_time TEXT,
    fired_time TEXT,
    location TEXT,
    source TEXT NOT NULL,
    received_at TEXT DEFAULT (datetime('now'))
  );
  CREATE TABLE IF NOT EXISTS pending_discord (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_ref INTEGER REFERENCES events(id),
    payload TEXT NOT NULL,
    queued_at TEXT DEFAULT (datetime('now')),
    sent_at TEXT
  );
  CREATE TABLE IF NOT EXISTS installs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL,
    app_version TEXT NOT NULL,
    build_sha TEXT NOT NULL,
    installed_at TEXT,
    received_at TEXT DEFAULT (datetime('now')),
    verify_code TEXT NOT NULL,
    ip TEXT
  );
`);

const insertEvent = db.prepare(`
  INSERT INTO events (event_id, title, action, scheduled_time, fired_time, location, source)
  VALUES (@event_id, @title, @action, @scheduled_time, @fired_time, @location, @source)
`);
const insertDiscord = db.prepare(`
  INSERT INTO pending_discord (event_ref, payload) VALUES (@event_ref, @payload)
`);
const pruneOld = db.prepare(
  `DELETE FROM events WHERE received_at < datetime('now', '-' || ? || ' days')`
);
const countEvents = db.prepare('SELECT COUNT(*) AS n FROM events');
const queryEvents = db.prepare(`
  SELECT * FROM events WHERE received_at >= @since ORDER BY received_at DESC LIMIT @limit
`);

function prune() {
  const info = pruneOld.run(RETENTION_DAYS);
  if (info.changes > 0) console.log(`Pruned ${info.changes} events older than ${RETENTION_DAYS} days`);
}

function sendDiscord(eventRow) {
  const msg = `soma-alarm: ${eventRow.title} — ${eventRow.action}`;
  const payload = JSON.stringify({ content: msg });
  insertDiscord.run({ event_ref: eventRow.id, payload });

  if (!DISCORD_CHANNEL_ID || !DISCORD_BOT_TOKEN) return;

  fetch(`https://discord.com/api/v10/channels/${DISCORD_CHANNEL_ID}/messages`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bot ${DISCORD_BOT_TOKEN}`,
    },
    body: payload,
  }).then(res => {
    if (res.ok) {
      db.prepare('UPDATE pending_discord SET sent_at = datetime(\'now\') WHERE event_ref = ?')
        .run(eventRow.id);
    } else {
      console.error(`Discord POST failed: ${res.status}`);
    }
  }).catch(err => console.error('Discord error:', err.message));
}

prune();
setInterval(prune, 24 * 60 * 60 * 1000);

const app = express();
app.use(express.json());

const UNAMBIGUOUS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
function generateVerifyCode(len = 8) {
  let code = '';
  const bytes = require('crypto').randomBytes(len);
  for (let i = 0; i < len; i++) code += UNAMBIGUOUS[bytes[i] % UNAMBIGUOUS.length];
  return code;
}

const insertInstall = db.prepare(`
  INSERT INTO installs (device_id, app_version, build_sha, installed_at, verify_code, ip)
  VALUES (@device_id, @app_version, @build_sha, @installed_at, @verify_code, @ip)
`);

const INSTALL_REQUIRED = ['device_id', 'app_version', 'build_sha'];

app.post('/install', (req, res) => {
  const body = req.body || {};
  const missing = INSTALL_REQUIRED.filter(k => !body[k]);
  if (missing.length) return res.status(400).json({ error: 'missing fields', missing });

  const verifyCode = generateVerifyCode();
  const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress || '';

  insertInstall.run({
    device_id: body.device_id,
    app_version: body.app_version,
    build_sha: body.build_sha,
    installed_at: body.installed_at || null,
    verify_code: verifyCode,
    ip: String(ip).split(',')[0].trim(),
  });

  insertEvent.run({
    event_id: `install-${body.device_id}`,
    title: `Install: ${body.device_id}`,
    action: 'install',
    scheduled_time: body.installed_at || null,
    fired_time: null,
    location: null,
    source: 'soma-alarm-android',
  });

  res.status(201).json({
    ok: true,
    verify_code: verifyCode,
    server_time: new Date().toISOString(),
    message: 'soma-webhook reachable',
  });
});

const REQUIRED = ['event_id', 'title', 'action', 'source'];

app.post('/alarm-event', (req, res) => {
  const body = req.body || {};
  const missing = REQUIRED.filter(k => !body[k]);
  if (missing.length) return res.status(400).json({ error: 'missing fields', missing });

  const info = insertEvent.run({
    event_id: body.event_id,
    title: body.title,
    action: body.action,
    scheduled_time: body.scheduled_time || null,
    fired_time: body.fired_time || null,
    location: body.location || null,
    source: body.source,
  });

  const row = { id: info.lastInsertRowid, ...body };
  if (body.action === 'fire' || body.action === 'morning') {
    sendDiscord(row);
  }

  res.status(201).json({ ok: true, id: Number(info.lastInsertRowid) });
});

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    version: VERSION,
    uptime: Math.floor(process.uptime()),
    event_count: countEvents.get().n,
  });
});

app.get('/events', (req, res) => {
  const since = req.query.since || new Date(Date.now() - 86400000).toISOString();
  const limit = Math.min(parseInt(req.query.limit) || 100, 1000);
  const rows = queryEvents.all({ since, limit });
  res.json(rows);
});

app.listen(PORT, () => console.log(`soma-webhook listening on :${PORT}`));
