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

// ─── Pulse card endpoints ──────────────────────────────────────────────────
// Phase 0 stub. Cards stored in SQLite; FCM delivery stubbed until
// PULSE_FCM_SERVER_KEY is configured in env.

const crypto = require('crypto');

const PULSE_HMAC_SECRET = process.env.PULSE_HMAC_SECRET || '';
const PULSE_FCM_SERVER_KEY = process.env.PULSE_FCM_SERVER_KEY || '';
const PULSE_ENV = process.env.PULSE_ENV || 'development';

db.exec(`
  CREATE TABLE IF NOT EXISTS pulse_cards (
    id TEXT PRIMARY KEY,
    schema_version TEXT NOT NULL DEFAULT '1.0',
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT,
    card_json TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'created',
    priority TEXT NOT NULL DEFAULT 'normal',
    urgency TEXT NOT NULL DEFAULT 'async',
    source_dispatch_id TEXT,
    source_agent TEXT,
    target_user TEXT NOT NULL DEFAULT 'mike',
    created_at INTEGER NOT NULL,
    expires_at INTEGER,
    responded_at INTEGER,
    fcm_message_id TEXT
  );
  CREATE INDEX IF NOT EXISTS idx_pulse_state ON pulse_cards(state);
  CREATE INDEX IF NOT EXISTS idx_pulse_created ON pulse_cards(created_at DESC);

  CREATE TABLE IF NOT EXISTS pulse_devices (
    user_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    fcm_token TEXT NOT NULL,
    device_auth_token TEXT NOT NULL,
    registered_at TEXT DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, device_id)
  );
`);

function validatePulseSignature(body, sigHeader) {
  if (PULSE_ENV === 'development') return true;
  if (!PULSE_HMAC_SECRET) return false;
  if (!sigHeader || !sigHeader.startsWith('hmac-sha256=')) return false;
  const provided = sigHeader.slice('hmac-sha256='.length);
  const { id, schema_version, type, title, created_at } = body;
  const payload = [id, schema_version, type, title, created_at].join(':');
  const expected = crypto.createHmac('sha256', PULSE_HMAC_SECRET).update(payload).digest('hex');
  return crypto.timingSafeEqual(Buffer.from(provided, 'hex'), Buffer.from(expected, 'hex'));
}

async function deliverVisFCM(card, fcmToken) {
  if (!PULSE_FCM_SERVER_KEY || !fcmToken) return null;
  const payload = JSON.stringify({
    to: fcmToken,
    priority: 'high',
    data: {
      pulse_card_id: card.id,
      card_type: card.type,
      title: card.title,
      priority: card.priority,
      urgency: card.urgency,
    },
    android: { priority: 'HIGH' },
  });
  try {
    const res = await fetch('https://fcm.googleapis.com/fcm/send', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `key=${PULSE_FCM_SERVER_KEY}`,
      },
      body: payload,
    });
    if (!res.ok) { console.error(`FCM error: ${res.status}`); return null; }
    const data = await res.json();
    return data.results?.[0]?.message_id || null;
  } catch (err) {
    console.error('FCM delivery failed:', err.message);
    return null;
  }
}

const insertCard = db.prepare(`
  INSERT INTO pulse_cards (id, schema_version, type, title, body, card_json, state, priority, urgency, source_dispatch_id, source_agent, target_user, created_at, expires_at)
  VALUES (@id, @schema_version, @type, @title, @body, @card_json, 'created', @priority, @urgency, @source_dispatch_id, @source_agent, @target_user, @created_at, @expires_at)
`);
const updateCardState = db.prepare(`UPDATE pulse_cards SET state = @state, fcm_message_id = @fcm_message_id WHERE id = @id`);
const respondCard = db.prepare(`UPDATE pulse_cards SET state = 'responded', responded_at = @responded_at, card_json = @card_json WHERE id = @id`);
const getCard = db.prepare(`SELECT * FROM pulse_cards WHERE id = ?`);
const listCards = db.prepare(`SELECT * FROM pulse_cards WHERE state NOT IN ('responded','dismissed','expired') ORDER BY created_at DESC LIMIT ?`);
const getDevice = db.prepare(`SELECT * FROM pulse_devices WHERE user_id = ? ORDER BY registered_at DESC LIMIT 1`);

app.post('/pulse/cards', async (req, res) => {
  const card = req.body || {};
  const sig = req.headers['x-pulse-signature'] || '';
  if (!validatePulseSignature(card, sig)) return res.status(401).json({ error: 'invalid signature' });

  const required = ['id', 'type', 'title', 'created_at', 'source_dispatch_id', 'target_user'];
  const missing = required.filter(k => !card[k]);
  if (missing.length) return res.status(422).json({ error: 'missing fields', missing });

  const createdMs = new Date(card.created_at).getTime();
  const expiresMs = card.expires_at ? new Date(card.expires_at).getTime() : null;

  insertCard.run({
    id: card.id,
    schema_version: card.schema_version || '1.0',
    type: card.type,
    title: card.title,
    body: card.body || null,
    card_json: JSON.stringify(card),
    priority: card.priority || 'normal',
    urgency: card.urgency || 'async',
    source_dispatch_id: card.source_dispatch_id,
    source_agent: card.source_agent || null,
    target_user: card.target_user,
    created_at: createdMs,
    expires_at: expiresMs,
  });

  const device = getDevice.get(card.target_user);
  const fcmToken = device?.fcm_token || null;
  const fcmMessageId = await deliverVisFCM(card, fcmToken);
  const state = fcmMessageId ? 'delivered' : (fcmToken ? 'failed' : 'created');
  updateCardState.run({ id: card.id, state, fcm_message_id: fcmMessageId });

  res.status(201).json({
    id: card.id,
    state,
    fcm_message_id: fcmMessageId,
    delivered_at: fcmMessageId ? new Date().toISOString() : null,
    stub: !PULSE_FCM_SERVER_KEY,
  });
});

app.get('/pulse/cards', (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 20, 100);
  const rows = listCards.all(limit);
  res.json(rows.map(r => ({ ...r, card_json: JSON.parse(r.card_json) })));
});

app.get('/pulse/cards/:id', (req, res) => {
  const row = getCard.get(req.params.id);
  if (!row) return res.status(404).json({ error: 'not found' });
  res.json({ ...row, card_json: JSON.parse(row.card_json) });
});

app.post('/pulse/cards/:id/respond', (req, res) => {
  const row = getCard.get(req.params.id);
  if (!row) return res.status(404).json({ error: 'not found' });

  const { action_id, value, responded_at, source_surface, checklist_state } = req.body || {};
  if (!action_id) return res.status(422).json({ error: 'missing action_id' });

  const card = JSON.parse(row.card_json);
  card.state = 'responded';
  card.response = { action_id, value, responded_at: responded_at || new Date().toISOString(), source_surface: source_surface || 'pulse_android', checklist_state: checklist_state || null };

  respondCard.run({ id: req.params.id, responded_at: new Date(card.response.responded_at).getTime(), card_json: JSON.stringify(card) });

  // Synthesize a Dispatch message (stub — wire to actual Dispatch channel when ready)
  const dispatchMsg = `[via Pulse] ${card.title}: ${action_id}${value !== undefined ? ` (${value})` : ''}`;
  console.log(`DISPATCH: ${dispatchMsg}`);

  res.json({ id: req.params.id, state: 'responded', dispatch_message: dispatchMsg });
});

app.post('/pulse/register', (req, res) => {
  const { user_id, fcm_token, device_id, device_auth_token } = req.body || {};
  if (!user_id || !fcm_token || !device_id || !device_auth_token) {
    return res.status(422).json({ error: 'missing fields' });
  }
  db.prepare(`INSERT OR REPLACE INTO pulse_devices (user_id, device_id, fcm_token, device_auth_token) VALUES (?, ?, ?, ?)`)
    .run(user_id, device_id, fcm_token, device_auth_token);
  res.json({ ok: true, registered_at: new Date().toISOString() });
});

app.get('/pulse/health', (_req, res) => {
  const cardCount = db.prepare('SELECT COUNT(*) AS n FROM pulse_cards').get().n;
  res.json({ status: 'ok', fcm_connected: Boolean(PULSE_FCM_SERVER_KEY), env: PULSE_ENV, card_count: cardCount });
});
// ─── end Pulse ─────────────────────────────────────────────────────────────

app.listen(PORT, () => console.log(`soma-webhook listening on :${PORT}`));
