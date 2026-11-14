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
// Admins (for the /admin ticket page) and ticket tracking.
const hasColumn = (table, col) => db.prepare(`PRAGMA table_info(${table})`).all().some((c) => c.name === col);
if (!hasColumn("users", "is_admin")) db.exec("ALTER TABLE users ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0");
// Test accounts (made from the admin page): no email needed, hidden from the scoreboards.
if (!hasColumn("users", "is_test")) db.exec("ALTER TABLE users ADD COLUMN is_test INTEGER NOT NULL DEFAULT 0");
if (!hasColumn("reports", "updated_at")) db.exec("ALTER TABLE reports ADD COLUMN updated_at INTEGER");
db.exec(`
  UPDATE reports SET status = 'resolved' WHERE status = 'done';
  UPDATE reports SET updated_at = created_at WHERE updated_at IS NULL;
  CREATE TABLE IF NOT EXISTS report_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    report_id INTEGER NOT NULL,
    author TEXT NOT NULL,
    text TEXT NOT NULL,
    created_at INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS admin_sessions (
    token_hash TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL,
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

// Names that look like staff, so players can't pretend to be admins in lobbies/scoreboards.
// Checked on a "flattened" name: lowercase, _ removed, look-alike digits turned into letters
// (Adm1n, 4dmin, adm_in, M0d...). Existing accounts (like the real Admin) aren't affected.
const RESERVED_PARTS = ["admin", "administrator", "moderator", "staff", "official", "support",
  "rocketrace", "owner", "developer", "gamemaster", "system", "server", "helpdesk"];
const RESERVED_EXACT = ["mod", "mods", "dev", "devs", "gm", "root", "sysop", "op", "team", "help"];

function flattenName(name) {
  return String(name).toLowerCase().replace(/_/g, "")
    .replace(/0/g, "o").replace(/[1!|]/g, "i").replace(/3/g, "e").replace(/4/g, "a")
    .replace(/5/g, "s").replace(/7/g, "t").replace(/8/g, "b").replace(/9/g, "g");
}

// Real words that happen to contain a reserved word.
const RESERVED_OK = ["badminton"];

function reservedName(name) {
  const flat = flattenName(name);
  if (RESERVED_OK.some((w) => flat.includes(w))) return false;
  const lettersOnly = flat.replace(/[^a-z]/g, "");
  const variants = [flat, flat.replace(/i/g, "l"), lettersOnly];  // 1 can stand for i or l
  return variants.some((v) => RESERVED_EXACT.includes(v) || RESERVED_PARTS.some((p) => v.includes(p)));
}
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
  const user = { id: row.id, username: row.username, email: row.email || "", admin: !!row.is_admin, profile: loadProfile(row) };
  // A restricted pilot (e.g. Titan) the player no longer has access to falls back to Falcon.
  if (!progress.canFly(user.profile, user.profile.character, user.admin)) user.profile.character = "falcon";
  return user;
}

/** Public view sent to the game: the profile plus account name/email and computed levels. */
function view(user) {
  const p = user.profile;
  return { username: user.username, email: user.email || "", admin: !!user.admin, ...p,
    sp_level: progress.levelInfo(p.sp.xp), mp_level: progress.levelInfo(p.mp.xp) };
}

function signup(username, password, email, guestProfile) {
  username = String(username || "").trim();
  email = cleanEmail(email);
  if (!USERNAME_RE.test(username)) return { error: "Usernames are 3-16 letters, numbers or _." };
  if (reservedName(username)) return { error: "That name is reserved for the Rocket Race team. Please pick another." };
  const bad = checkPassword(password) || checkEmail(email);
  if (bad) return { error: bad };
  if (db.prepare("SELECT 1 FROM users WHERE username = ?").get(username)) return { error: "That username is taken." };
  // A guest who signs up keeps their single-player progress (guests can't play multiplayer).
  // checkLevels: a guest can't bring items above their level (stored accounts keep admin grants).
  const profile = progress.sanitize(guestProfile, { allowMp: false, checkLevels: true });
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
  db.prepare("DELETE FROM admin_sessions WHERE user_id = ?").run(userId);
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
  db.prepare("DELETE FROM admin_sessions WHERE user_id = ?").run(user.id);
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

// --- Tickets (admin page) --------------------------------------------------------------

const TICKET_STATUSES = ["new", "open", "in_progress", "resolved"];

function listReports(status = "new", limit = 100) {
  return db.prepare("SELECT * FROM reports WHERE (? = 'all' OR status = ?) ORDER BY id DESC LIMIT ?").all(status, status, limit);
}

/** Tickets for the admin list, newest first, with filters and per-status counts. */
function listTickets({ status = "all", category = "all", q = "", limit = 200 } = {}) {
  const where = [];
  const args = [];
  if (TICKET_STATUSES.includes(status)) { where.push("status = ?"); args.push(status); }
  if (REPORT_CATEGORIES.includes(category)) { where.push("category = ?"); args.push(category); }
  if (q) {
    where.push("(message LIKE ? OR username LIKE ? OR target LIKE ? OR CAST(id AS TEXT) = ?)");
    const like = "%" + String(q).slice(0, 80) + "%";
    args.push(like, like, like, String(q).replace(/^#/, ""));
  }
  const sql = "SELECT id, created_at, updated_at, username, category, target, status, substr(message, 1, 140) AS preview," +
    " (SELECT COUNT(*) FROM report_notes n WHERE n.report_id = reports.id) AS notes FROM reports" +
    (where.length ? " WHERE " + where.join(" AND ") : "") + " ORDER BY id DESC LIMIT ?";
  const rows = db.prepare(sql).all(...args, Math.min(Number(limit) || 200, 500));
  const counts = { all: 0 };
  for (const st of TICKET_STATUSES) counts[st] = 0;
  for (const r of db.prepare("SELECT status, COUNT(*) AS n FROM reports GROUP BY status").all()) {
    counts[r.status] = r.n;
    counts.all += r.n;
  }
  return { rows, counts };
}

function accountSummary(name) {
  if (!name) return null;
  const u = db.prepare("SELECT id, username, email, created_at, is_admin, profile FROM users WHERE username = ?").get(name);
  if (!u) return { username: name, exists: false };
  const p = loadProfile(u);
  return {
    username: u.username, exists: true, email: u.email || "", created_at: u.created_at, admin: !!u.is_admin,
    sp_level: progress.levelInfo(p.sp.xp).level, mp_level: progress.levelInfo(p.mp.xp).level, races: p.stats.mp_races,
    reports_sent: db.prepare("SELECT COUNT(*) AS n FROM reports WHERE username = ?").get(u.username).n,
    reported_times: db.prepare("SELECT COUNT(*) AS n FROM reports WHERE target = ? COLLATE NOCASE").get(u.username).n,
  };
}

/** One ticket with its notes, plus info on the reporter and (player reports) the reported player. */
function getTicket(id) {
  const t = db.prepare("SELECT * FROM reports WHERE id = ?").get(Number(id));
  if (!t) return null;
  t.notes = db.prepare("SELECT author, text, created_at FROM report_notes WHERE report_id = ? ORDER BY id").all(t.id);
  t.reporter = t.username === "guest" ? null : accountSummary(t.username);
  t.target_account = t.target ? accountSummary(t.target) : null;
  return t;
}

function setTicketStatus(id, status, author) {
  if (!TICKET_STATUSES.includes(status)) return { error: "Unknown status." };
  const t = db.prepare("SELECT status FROM reports WHERE id = ?").get(Number(id));
  if (!t) return { error: "No such ticket." };
  if (t.status === status) return {};
  db.prepare("UPDATE reports SET status = ?, updated_at = ? WHERE id = ?").run(status, Date.now(), Number(id));
  addTicketNote(id, author, `Status: ${t.status.replace("_", " ")} → ${status.replace("_", " ")}`, true);
  return {};
}

/** Private note on a ticket (only admins see these). system = automatic status-change note. */
function addTicketNote(id, author, text, system = false) {
  text = String(text || "").trim().slice(0, 2000);
  if (!text) return { error: "Write a note first." };
  if (!db.prepare("SELECT 1 FROM reports WHERE id = ?").get(Number(id))) return { error: "No such ticket." };
  db.prepare("INSERT INTO report_notes (report_id, author, text, created_at) VALUES (?, ?, ?, ?)")
    .run(Number(id), system ? "system" : String(author), system ? `${text} (by ${author})` : text, Date.now());
  db.prepare("UPDATE reports SET updated_at = ? WHERE id = ?").run(Date.now(), Number(id));
  return {};
}

/** Used by the reports.js command. */
function setReportStatus(id, status) {
  return setTicketStatus(id, status === "done" ? "resolved" : status, "console");
}

// --- Admins ------------------------------------------------------------------------------

const ADMIN_SESSION_MS = 12 * 3600 * 1000;
const sha = (v) => crypto.createHash("sha256").update(String(v)).digest("hex");

function setAdmin(username, on) {
  const r = db.prepare("UPDATE users SET is_admin = ? WHERE username = ?").run(on ? 1 : 0, String(username));
  if (!on) {
    const u = db.prepare("SELECT id FROM users WHERE username = ?").get(String(username));
    if (u) db.prepare("DELETE FROM admin_sessions WHERE user_id = ?").run(u.id);
  }
  return r.changes > 0;
}

function listAdmins() {
  return db.prepare("SELECT username, email FROM users WHERE is_admin = 1 ORDER BY username").all();
}

/** Admin page login (a game account with the admin flag). Same lockout as the game. */
function adminLogin(name, password) {
  name = String(name || "").trim();
  const row = db.prepare("SELECT * FROM users WHERE username = ? OR email = ?").get(name, name.toLowerCase());
  const generic = { error: "Wrong username or password, or not an admin." };
  if (!row) return generic;
  if (locked(row.id)) return { error: "Too many wrong passwords. This account is locked for 15 minutes." };
  if (!passwordMatches(row, password)) {
    noteFailure(row.id);
    return generic;
  }
  if (!row.is_admin) return generic;
  failedLogins.delete(row.id);
  const token = crypto.randomBytes(32).toString("hex");
  // Only a hash of the cookie is stored, so a copy of the database can't be used to log in.
  db.prepare("INSERT INTO admin_sessions (token_hash, user_id, created_at) VALUES (?, ?, ?)").run(sha(token), row.id, Date.now());
  return { token, username: row.username };
}

function adminForToken(token) {
  if (!token) return null;
  const row = db.prepare(`SELECT u.id, u.username, u.is_admin, s.created_at FROM admin_sessions s
      JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?`).get(sha(token));
  if (!row || !row.is_admin || Date.now() - row.created_at > ADMIN_SESSION_MS) {
    if (row) db.prepare("DELETE FROM admin_sessions WHERE token_hash = ?").run(sha(token));
    return null;
  }
  return { id: row.id, username: row.username };
}

function adminLogout(token) {
  db.prepare("DELETE FROM admin_sessions WHERE token_hash = ?").run(sha(token || ""));
}

// --- Player management (admin page) ------------------------------------------------------

db.exec(`CREATE TABLE IF NOT EXISTS admin_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at INTEGER NOT NULL,
  admin TEXT NOT NULL,
  target TEXT NOT NULL,
  action TEXT NOT NULL
)`);

function logAdmin(admin, target, action) {
  db.prepare("INSERT INTO admin_log (created_at, admin, target, action) VALUES (?, ?, ?, ?)").run(Date.now(), admin, target, action);
}

function searchPlayers(q = "", limit = 50) {
  const like = "%" + String(q).slice(0, 60) + "%";
  return db.prepare(`SELECT username, email, created_at, is_admin, is_test, profile FROM users
      WHERE username LIKE ? OR email LIKE ? ORDER BY username COLLATE NOCASE LIMIT ?`)
    .all(like, like, limit)
    .map((u) => {
      const p = loadProfile(u);
      return { username: u.username, email: u.email || "", created_at: u.created_at, admin: !!u.is_admin, test: !!u.is_test,
        sp_level: progress.levelInfo(p.sp.xp).level, mp_level: progress.levelInfo(p.mp.xp).level,
        sp_credits: p.sp.credits, mp_credits: p.mp.credits };
    });
}

/** Full account for the admin page: profile, levels, stats, owned items, recent admin changes. */
/** Admin page: make a test account. Email is optional; same name/password rules as sign-up. */
function createTestAccount(adminName, username, password, email) {
  username = String(username || "").trim();
  email = cleanEmail(email);
  if (!USERNAME_RE.test(username)) return { error: "Usernames are 3-16 letters, numbers or _." };
  if (reservedName(username)) return { error: "That name is reserved for the Rocket Race team." };
  const bad = checkPassword(password) || (email ? checkEmail(email) : "");
  if (bad) return { error: bad };
  if (db.prepare("SELECT 1 FROM users WHERE username = ?").get(username)) return { error: "That username is taken." };
  const salt = crypto.randomBytes(16).toString("hex");
  db.prepare("INSERT INTO users (username, email, pass_hash, salt, profile, created_at, is_test) VALUES (?, ?, ?, ?, ?, ?, 1)")
    .run(username, email || null, hashPassword(String(password), salt), salt, JSON.stringify(progress.newProfile()), Date.now());
  logAdmin(adminName, username, "created test account" + (email ? "" : " (no email)"));
  return { username };
}

/** Admin page: delete a TEST account (real players' accounts can't be deleted from here). */
function deleteTestAccount(adminName, name) {
  const u = db.prepare("SELECT id, username, is_test FROM users WHERE username = ?").get(String(name));
  if (!u) return { error: "No such player." };
  if (!u.is_test) return { error: "Only test accounts can be deleted from the admin page." };
  for (const t of ["sessions", "reset_codes", "admin_sessions"]) db.prepare(`DELETE FROM ${t} WHERE user_id = ?`).run(u.id);
  db.prepare("UPDATE reports SET user_id = NULL WHERE user_id = ?").run(u.id);
  db.prepare("DELETE FROM users WHERE id = ?").run(u.id);
  logAdmin(adminName, u.username, "deleted test account");
  return {};
}

function getPlayer(name) {
  const u = db.prepare("SELECT * FROM users WHERE username = ?").get(String(name));
  if (!u) return null;
  const user = toUser(u);
  const view_ = view(user);
  view_.created_at = u.created_at;
  view_.admin = !!u.is_admin;
  view_.test = !!u.is_test;
  view_.history = db.prepare("SELECT created_at, admin, action FROM admin_log WHERE target = ? ORDER BY id DESC LIMIT 30").all(u.username);
  view_.catalog = { ships: progress.catalog.ships.map((s) => s.id), mods: progress.catalog.mods.map((m) => m.id),
    designs: progress.catalog.designs.map((d) => d.id),
    finishes: (progress.catalog.finishes || []).map((f) => f.id),
    decor: (progress.catalog.decor || []).map((d) => d.id),
    pilots: progress.catalog.characters.filter((c) => c.dev).map((c) => ({ id: c.id, name: c.name })) };
  return view_;
}

const clampInt = (v, lo, hi) => Math.max(lo, Math.min(hi, Math.trunc(Number(v) || 0)));

/** Add (or take away, with negative numbers) XP and credits in one mode. */
function adjustPlayer(adminName, name, track, xp, credits) {
  if (!["sp", "mp"].includes(track)) return { error: "Pick Single Player or Multiplayer." };
  xp = clampInt(xp, -1e9, 1e9);
  credits = clampInt(credits, -1e9, 1e9);
  if (!xp && !credits) return { error: "Enter an amount of XP or credits." };
  const u = db.prepare("SELECT * FROM users WHERE username = ?").get(String(name));
  if (!u) return { error: "No such player." };
  const user = toUser(u);
  const t = user.profile[track];
  const before = progress.levelInfo(t.xp).level;
  t.xp = Math.max(0, t.xp + xp);
  t.credits = Math.max(0, t.credits + credits);
  save(user);
  const after = progress.levelInfo(t.xp).level;
  const mode = track === "sp" ? "Single Player" : "Multiplayer";
  const parts = [];
  if (xp) parts.push(`${xp > 0 ? "+" : ""}${xp} XP`);
  if (credits) parts.push(`${credits > 0 ? "+" : ""}${credits} credits`);
  logAdmin(adminName, user.username, `${mode}: ${parts.join(", ")}` + (after !== before ? ` (level ${before} → ${after})` : ""));
  return {};
}

/** Unlock (or remove) a ship / mod / paint in one mode. The free starter items can't be removed. */
function setPlayerItem(adminName, name, track, kind, id, owned) {
  if (!["sp", "mp"].includes(track)) return { error: "Pick Single Player or Multiplayer." };
  const table = { ships: progress.catalog.ships, mods: progress.catalog.mods, designs: progress.catalog.designs,
    finishes: progress.catalog.finishes || [], decor: progress.catalog.decor || [] }[kind];
  if (!table || !table.some((x) => x.id === id)) return { error: "Unknown item." };
  if (!owned && (id === "small" || id === "classic" || (kind === "finishes" && id === "none"))) {
    return { error: "Starter items can't be removed." };
  }
  const u = db.prepare("SELECT * FROM users WHERE username = ?").get(String(name));
  if (!u) return { error: "No such player." };
  const user = toUser(u);
  const t = user.profile[track];
  const list = t.owned[kind];
  const has = list.includes(id);
  if (owned && !has) list.push(id);
  if (!owned && has) {
    t.owned[kind] = list.filter((x) => x !== id);
    // Take it off the hangar loadout too.
    if (kind === "ships" && t.loadout.ship === id) t.loadout.ship = "small";
    if (kind === "designs" && t.loadout.design === id) t.loadout.design = "classic";
    if (kind === "mods") t.loadout.mods = t.loadout.mods.filter((x) => x !== id);
    if (kind === "finishes" && t.loadout.finish === id) t.loadout.finish = "none";
    if (kind === "decor") t.loadout.decor = (t.loadout.decor || []).filter((x) => x !== id);
  }
  // Ship change can lower the slot count: trim fitted mods to fit.
  const slots = (progress.catalog.ships.find((s) => s.id === t.loadout.ship) || { slots: 1 }).slots;
  t.loadout.mods = t.loadout.mods.slice(0, slots);
  save(user);
  const mode = track === "sp" ? "Single Player" : "Multiplayer";
  logAdmin(adminName, user.username, `${mode}: ${owned ? "unlocked" : "removed"} ${kind.slice(0, -1)} "${id}"`);
  return {};
}

/** Give (or take away) a player's access to a restricted pilot, e.g. the DEV pilot Titan. */
function setPlayerPilot(adminName, name, id, granted) {
  const c = progress.catalog.characters.find((x) => x.id === id);
  if (!c || !c.dev) return { error: "That pilot isn't restricted." };
  const u = db.prepare("SELECT * FROM users WHERE username = ?").get(String(name));
  if (!u) return { error: "No such player." };
  const user = toUser(u);
  const list = user.profile.pilots || [];
  user.profile.pilots = granted ? [...new Set([...list, id])] : list.filter((x) => x !== id);
  if (!progress.canFly(user.profile, user.profile.character, user.admin)) user.profile.character = "falcon";
  save(user);
  logAdmin(adminName, user.username, `${granted ? "gave" : "removed"} access to pilot "${c.name}"`);
  return {};
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
        FROM users WHERE is_test = 0 AND json_extract(profile, '$.stats.mp_races') >= ?
        ORDER BY rate DESC, best DESC LIMIT ?`)
      .all(MIN_RACES, limit)
      .map((r) => ({ ...r, rate: Math.round((r.rate || 0) * 100), level: 0 }));
  }
  return db
    .prepare(`SELECT username AS name, json_extract(profile, '$.character') AS character,
        json_extract(profile, '$.stats.sp_best') AS best, json_extract(profile, '$.sp.xp') AS xp
      FROM users WHERE is_test = 0 AND json_extract(profile, '$.stats.sp_best') > 0
      ORDER BY best DESC LIMIT ?`)
    .all(limit)
    .map((r) => ({ name: r.name, character: r.character, best: r.best, level: progress.levelInfo(r.xp).level }));
}

module.exports = {
  signup, login, logout, userForToken, save, view, leaderboard, MIN_RACES,
  changePassword, changeEmail, deleteAccount, startReset, finishReset,
  addReport, listReports, setReportStatus, REPORT_CATEGORIES,
  TICKET_STATUSES, listTickets, getTicket, setTicketStatus, addTicketNote,
  setAdmin, listAdmins, adminLogin, adminForToken, adminLogout, ADMIN_SESSION_MS,
  searchPlayers, getPlayer, adjustPlayer, setPlayerItem, setPlayerPilot, createTestAccount, deleteTestAccount,
};
