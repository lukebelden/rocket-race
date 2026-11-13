// Player accounts: SQLite database (Node's built-in node:sqlite), scrypt-hashed passwords,
// random session tokens. The database file lives in DATA_DIR (default server/data/).

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { DatabaseSync } = require("node:sqlite");
const progress = require("./progress");

const DATA_DIR = path.resolve(process.env.DATA_DIR || path.join(__dirname, "data"));
fs.mkdirSync(DATA_DIR, { recursive: true });
const db = new DatabaseSync(path.join(DATA_DIR, "rocket-race.db"));

db.exec(`
  PRAGMA journal_mode = WAL;
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE COLLATE NOCASE,
    pass_hash TEXT NOT NULL,
    salt TEXT NOT NULL,
    profile TEXT NOT NULL,
    created_at INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS sessions (
    token TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at INTEGER NOT NULL
  );
`);

for (const row of db.prepare("SELECT id, profile FROM users").all()) {
  let data = {};
  try { data = JSON.parse(row.profile); } catch {}
  const clean = JSON.stringify(progress.sanitize(data));
  if (clean !== row.profile) db.prepare("UPDATE users SET profile = ? WHERE id = ?").run(clean, row.id);
}

const SESSION_DAYS = 60;
const USERNAME_RE = /^[A-Za-z0-9_]{3,16}$/;

function hashPassword(password, salt) {
  return crypto.scryptSync(password, salt, 64).toString("hex");
}

function newSession(userId) {
  const token = crypto.randomBytes(32).toString("hex");
  db.prepare("INSERT INTO sessions (token, user_id, created_at) VALUES (?, ?, ?)").run(token, userId, Date.now());
  return token;
}

function loadProfile(row) {
  let data = {};
  try {
    data = JSON.parse(row.profile);
  } catch {}
  return progress.sanitize(data);
}

/** Public view sent to the game: the profile plus the account name and computed levels. */
function view(user) {
  const p = user.profile;
  return { username: user.username, ...p, sp_level: progress.levelInfo(p.sp.xp), mp_level: progress.levelInfo(p.mp.xp) };
}

function signup(username, password, guestProfile) {
  username = String(username || "").trim();
  password = String(password || "");
  if (!USERNAME_RE.test(username)) return { error: "Usernames are 3-16 letters, numbers or _." };
  if (password.length < 6 || password.length > 128) return { error: "Passwords need at least 6 characters." };
  if (db.prepare("SELECT 1 FROM users WHERE username = ?").get(username)) return { error: "That username is taken." };
  // A guest who signs up keeps their single-player progress (guests can't play multiplayer).
  const profile = progress.sanitize(guestProfile, { allowMp: false });
  const salt = crypto.randomBytes(16).toString("hex");
  const info = db
    .prepare("INSERT INTO users (username, pass_hash, salt, profile, created_at) VALUES (?, ?, ?, ?, ?)")
    .run(username, hashPassword(password, salt), salt, JSON.stringify(profile), Date.now());
  const user = { id: Number(info.lastInsertRowid), username, profile };
  return { token: newSession(user.id), user };
}

function login(username, password) {
  const row = db.prepare("SELECT * FROM users WHERE username = ?").get(String(username || "").trim());
  // Same message either way, so it doesn't reveal which usernames exist.
  if (!row) return { error: "Wrong username or password." };
  const hash = hashPassword(String(password || ""), row.salt);
  if (!crypto.timingSafeEqual(Buffer.from(hash, "hex"), Buffer.from(row.pass_hash, "hex"))) {
    return { error: "Wrong username or password." };
  }
  const user = { id: row.id, username: row.username, profile: loadProfile(row) };
  return { token: newSession(user.id), user };
}

function userForToken(token) {
  if (!token || typeof token !== "string") return null;
  const row = db
    .prepare("SELECT u.*, s.created_at AS session_at FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token = ?")
    .get(token);
  if (!row) return null;
  if (Date.now() - row.session_at > SESSION_DAYS * 864e5) {
    logout(token);
    return null;
  }
  return { id: row.id, username: row.username, profile: loadProfile(row) };
}

function logout(token) {
  db.prepare("DELETE FROM sessions WHERE token = ?").run(String(token || ""));
}

function save(user) {
  db.prepare("UPDATE users SET profile = ? WHERE id = ?").run(JSON.stringify(user.profile), user.id);
}

/** Top pilots. sp: best single-player score. mp: win rate (at least MIN_RACES races), then best race score. */
const MIN_RACES = 3;
function leaderboard(mode, limit = 10) {
  if (mode === "mp") {
    return db
      .prepare(`SELECT username AS name, json_extract(profile, '$.character') AS character,
          json_extract(profile, '$.stats.mp_wins') AS wins, json_extract(profile, '$.stats.mp_races') AS races,
          json_extract(profile, '$.stats.mp_best') AS best,
          CAST(json_extract(profile, '$.stats.mp_wins') AS REAL) / json_extract(profile, '$.stats.mp_races') AS rate
        FROM users WHERE json_extract(profile, '$.stats.mp_races') >= ?
        ORDER BY rate DESC, best DESC LIMIT ?`)
      .all(MIN_RACES, limit)
      .map((r) => ({ ...r, rate: Math.round((r.rate || 0) * 100), level: 0 }));
  }
  return db
    .prepare(`SELECT username AS name, json_extract(profile, '$.character') AS character,
        json_extract(profile, '$.stats.sp_best') AS best, json_extract(profile, '$.sp.xp') AS xp
      FROM users WHERE json_extract(profile, '$.stats.sp_best') > 0
      ORDER BY best DESC LIMIT ?`)
    .all(limit)
    .map((r) => ({ name: r.name, character: r.character, best: r.best, level: progress.levelInfo(r.xp).level }));
}

module.exports = { signup, login, logout, userForToken, save, view, leaderboard, MIN_RACES };
