// Player accounts: SQLite database (Node's built-in node:sqlite), scrypt-hashed passwords,
// random session tokens, emailed password-reset codes, and problem reports.
// The database file lives in DATA_DIR (default server/data/).
//
// Security notes:
//  - Passwords: scrypt with a per-user salt; compared in constant time.
//  - Logins: an account locks for 15 minutes after 10 wrong passwords (per account, so it
//    can't be dodged by switching IP); index.js also rate-limits per IP.
//  - Reset codes: 6 digits, stored only as a hash, valid 15 minutes, 5 tries, one at a time.
//    Resetting or changing the password signs out every other session.
//  - Messages never reveal whether a username/email exists.

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
  CREATE TABLE IF NOT EXISTS reset_codes (
    user_id INTEGER PRIMARY KEY,
    code_hash TEXT NOT NULL,
    expires_at INTEGER NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0
  );
  CREATE TABLE IF NOT EXISTS reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at INTEGER NOT NULL,
    user_id INTEGER,
    username TEXT,
    category TEXT NOT NULL,
    target TEXT,
    message TEXT NOT NULL,
    platform TEXT,
    status TEXT NOT NULL DEFAULT 'new'
  );
`);
// Older databases: add the email column (one email per account, unique, case-insensitive).
if (!db.prepare("PRAGMA table_info(users)").all().some((c) => c.name === "email")) {
  db.exec("ALTER TABLE users ADD COLUMN email TEXT COLLATE NOCASE");
}
db.exec("CREATE UNIQUE INDEX IF NOT EXISTS users_email ON users(email) WHERE email IS NOT NULL");

for (const row of db.prepare("SELECT id, profile FROM users").all()) {
  let data = {};
  try { data = JSON.parse(row.profile); } catch {}
  const clean = JSON.stringify(progress.sanitize(data));
  if (clean !== row.profile) db.prepare("UPDATE users SET profile = ? WHERE id = ?").run(clean, row.id);
}

const SESSION_DAYS = 60;
const USERNAME_RE = /^[A-Za-z0-9_]{3,16}$/;
const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,24}$/;
const MIN_PASSWORD = 8;
const LOCK_AFTER = 10;
const LOCK_MS = 15 * 60 * 1000;
const CODE_MS = 15 * 60 * 1000;
const CODE_TRIES = 5;

const failedLogins = new Map(); // user id -> {count, since}

function hashPassword(password, salt) {
  return crypto.scryptSync(password, salt, 64).toString("hex");
}

function passwordMatches(row, password) {
  const hash = hashPassword(String(password || ""), row.salt);
  return crypto.timingSafeEqual(Buffer.from(hash, "hex"), Buffer.from(row.pass_hash, "hex"));
}

function checkPassword(password) {
  password = String(password || "");
  if (password.length < MIN_PASSWORD || password.length > 128) return `Passwords need at least ${MIN_PASSWORD} characters.`;
  return "";
}

function cleanEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function checkEmail(email, exceptUserId = 0) {
  if (!EMAIL_RE.test(email)) return "That email address doesn't look right.";
  const other = db.prepare("SELECT id FROM users WHERE email = ?").get(email);
  if (other && other.id !== exceptUserId) return "That email is already used by another account.";
  return "";
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

function toUser(row) {
  return { id: row.id, username: row.username, email: row.email || "", profile: loadProfile(row) };
}

/** Public view sent to the game: the profile plus account name/email and computed levels. */
function view(user) {
  const p = user.profile;
  return { username: user.username, email: user.email || "", ...p,
    sp_level: progress.levelInfo(p.sp.xp), mp_level: progress.levelInfo(p.mp.xp) };
}

function signup(username, password, email, guestProfile) {
  username = String(username || "").trim();
  email = cleanEmail(email);
  if (!USERNAME_RE.test(username)) return { error: "Usernames are 3-16 letters, numbers or _." };
  const bad = checkPassword(password) || checkEmail(email);
  if (bad) return { error: bad };
  if (db.prepare("SELECT 1 FROM users WHERE username = ?").get(username)) return { error: "That username is taken." };
  // A guest who signs up keeps their single-player progress (guests can't play multiplayer).
  const profile = progress.sanitize(guestProfile, { allowMp: false });
  const salt = crypto.randomBytes(16).toString("hex");
  const info = db
    .prepare("INSERT INTO users (username, email, pass_hash, salt, profile, created_at) VALUES (?, ?, ?, ?, ?, ?)")
    .run(username, email, hashPassword(String(password), salt), salt, JSON.stringify(profile), Date.now());
  const user = { id: Number(info.lastInsertRowid), username, email, profile };
  return { token: newSession(user.id), user };
}

function locked(userId) {
  const f = failedLogins.get(userId);
  return f && f.count >= LOCK_AFTER && Date.now() - f.since < LOCK_MS;
}

function noteFailure(userId) {
  const f = failedLogins.get(userId);
  if (!f || Date.now() - f.since > LOCK_MS) failedLogins.set(userId, { count: 1, since: Date.now() });
  else f.count++;
}

/** Log in with a username or the account's email. */
function login(name, password) {
  name = String(name || "").trim();
  const row = db.prepare("SELECT * FROM users WHERE username = ? OR email = ?").get(name, name.toLowerCase());
  // Same message either way, so it doesn't reveal which usernames exist.
  if (!row) return { error: "Wrong username or password." };
  if (locked(row.id)) return { error: "Too many wrong passwords. This account is locked for 15 minutes." };
  if (!passwordMatches(row, password)) {
    noteFailure(row.id);
    return { error: "Wrong username or password." };
  }
  failedLogins.delete(row.id);
  return { token: newSession(row.id), user: toUser(row) };
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
  return toUser(row);
}

function logout(token) {
  db.prepare("DELETE FROM sessions WHERE token = ?").run(String(token || ""));
}

function save(user) {
  db.prepare("UPDATE users SET profile = ? WHERE id = ?").run(JSON.stringify(user.profile), user.id);
}

function rowFor(user) {
  return db.prepare("SELECT * FROM users WHERE id = ?").get(user.id);
}

function setPassword(userId, password) {
  const salt = crypto.randomBytes(16).toString("hex");
  db.prepare("UPDATE users SET pass_hash = ?, salt = ? WHERE id = ?").run(hashPassword(String(password), salt), salt, userId);
  db.prepare("DELETE FROM sessions WHERE user_id = ?").run(userId);  // sign out everywhere
  db.prepare("DELETE FROM reset_codes WHERE user_id = ?").run(userId);
  failedLogins.delete(userId);
}

/** Change password (needs the current one). Returns {token} for this device, or {error}. */
function changePassword(user, current, next) {
  if (!passwordMatches(rowFor(user), current)) return { error: "Your current password is wrong." };
  const bad = checkPassword(next);
  if (bad) return { error: bad };
  setPassword(user.id, next);
  return { token: newSession(user.id) };
}

/** Change email (needs the password). */
function changeEmail(user, password, email) {
  if (!passwordMatches(rowFor(user), password)) return { error: "Wrong password." };
  email = cleanEmail(email);
  const bad = checkEmail(email, user.id);
  if (bad) return { error: bad };
  db.prepare("UPDATE users SET email = ? WHERE id = ?").run(email, user.id);
  user.email = email;
  return {};
}

/** Delete the account and everything tied to it (needs the password). */
function deleteAccount(user, password) {
  if (!passwordMatches(rowFor(user), password)) return { error: "Wrong password." };
  db.prepare("DELETE FROM sessions WHERE user_id = ?").run(user.id);
  db.prepare("DELETE FROM reset_codes WHERE user_id = ?").run(user.id);
  db.prepare("UPDATE reports SET user_id = NULL WHERE user_id = ?").run(user.id);
  db.prepare("DELETE FROM users WHERE id = ?").run(user.id);
  failedLogins.delete(user.id);
  return {};
}

const hashCode = (code) => crypto.createHash("sha256").update(String(code)).digest("hex");

/** Start a password reset. Returns {email, username, code} to send, or null (no account /
 *  no email on file / asked too recently). The caller always tells the player the same thing. */
function startReset(name) {
  name = String(name || "").trim();
  const row = db.prepare("SELECT * FROM users WHERE username = ? OR email = ?").get(name, name.toLowerCase());
  if (!row || !row.email) return null;
  const old = db.prepare("SELECT expires_at FROM reset_codes WHERE user_id = ?").get(row.id);
  if (old && old.expires_at - CODE_MS > Date.now() - 60 * 1000) return null;  // one email a minute
  const code = String(crypto.randomInt(0, 1000000)).padStart(6, "0");
  db.prepare("INSERT OR REPLACE INTO reset_codes (user_id, code_hash, expires_at, attempts) VALUES (?, ?, ?, 0)")
    .run(row.id, hashCode(code), Date.now() + CODE_MS);
  return { email: row.email, username: row.username, code };
}

/** Finish a reset with the emailed code. Returns {token, user} or {error}. */
function finishReset(name, code, password) {
  name = String(name || "").trim();
  const row = db.prepare("SELECT * FROM users WHERE username = ? OR email = ?").get(name, name.toLowerCase());
  const rc = row && db.prepare("SELECT * FROM reset_codes WHERE user_id = ?").get(row.id);
  const generic = { error: "That code is wrong or has expired. Ask for a new one." };
  if (!rc || rc.expires_at < Date.now() || rc.attempts >= CODE_TRIES) return generic;
  const given = Buffer.from(hashCode(String(code || "").trim()), "hex");
  if (!crypto.timingSafeEqual(given, Buffer.from(rc.code_hash, "hex"))) {
    db.prepare("UPDATE reset_codes SET attempts = attempts + 1 WHERE user_id = ?").run(row.id);
    return generic;
  }
  const bad = checkPassword(password);
  if (bad) return { error: bad };
  setPassword(row.id, password);
  return { token: newSession(row.id), user: toUser(db.prepare("SELECT * FROM users WHERE id = ?").get(row.id)) };
}

// --- Reports ----------------------------------------------------------------------------

const REPORT_CATEGORIES = ["bug", "player", "suggestion", "other"];

function addReport({ user, category, target, message, platform }) {
  category = REPORT_CATEGORIES.includes(category) ? category : "other";
  message = String(message || "").trim().slice(0, 2000);
  if (message.length < 5) return { error: "Please describe the problem (at least a few words)." };
  const info = db.prepare(`INSERT INTO reports (created_at, user_id, username, category, target, message, platform)
      VALUES (?, ?, ?, ?, ?, ?, ?)`)
    .run(Date.now(), user ? user.id : null, user ? user.username : "guest", category,
      String(target || "").trim().slice(0, 40), message, String(platform || "").slice(0, 80));
  return { id: Number(info.lastInsertRowid), category };
}

function listReports(status = "new", limit = 100) {
  return db.prepare("SELECT * FROM reports WHERE (? = 'all' OR status = ?) ORDER BY id DESC LIMIT ?").all(status, status, limit);
}

function setReportStatus(id, status) {
  db.prepare("UPDATE reports SET status = ? WHERE id = ?").run(String(status), Number(id));
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

module.exports = {
  signup, login, logout, userForToken, save, view, leaderboard, MIN_RACES,
  changePassword, changeEmail, deleteAccount, startReset, finishReset,
  addReport, listReports, setReportStatus, REPORT_CATEGORIES,
};
