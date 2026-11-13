// Rocket Race server.
//  - Serves the exported web build (build/web) over HTTP.
//  - Runs multiplayer race rooms over WebSockets at /ws.
//
// Every racer flies the same asteroid course (the server hands out one random seed per race);
// each game simulates its own flight and reports position/distance ~10 times a second, which
// the server relays to the rest of the room. The server decides finishing order.
//
// Run locally:   cd server && npm install && npm start   ->  http://localhost:8080
// Environment:   PORT (default 8080), STATIC_DIR (default ../build/web), MIN_PLAYERS (default 2),
//                DATA_DIR (default server/data: the accounts database lives here - keep it backed up)

const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { WebSocketServer } = require("ws");
const accounts = require("./accounts");
const progress = require("./progress");

const PORT = Number(process.env.PORT) || 8080;
const STATIC_DIR = path.resolve(process.env.STATIC_DIR || path.join(__dirname, "..", "build", "web"));
const MIN_PLAYERS = Math.max(1, Number(process.env.MIN_PLAYERS) || 2);
const MAX_PLAYERS = 4;
const COUNTDOWN_MS = 3000;
// Game's launch intro (game.gd INTRO_DURATION): the race clock starts after liftoff.
const INTRO_MS = 3600;
const CODE_LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ"; // no I / O (look like 1 / 0)
const COLORS = ["#4fc3ff", "#ff6b5e", "#7dff8a", "#ffd34d"];
// Must match game.gd: LEVEL_DURATION (distance per level) and RACE_LEVELS.
const LEVEL_DURATION = 26;
const RACE_LEVELS = 5;

// --- Static files ------------------------------------------------------------------------

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".json": "application/json",
};

function serveStatic(req, res) {
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.writeHead(405).end();
    return;
  }
  const url = new URL(req.url, "http://localhost");
  if (url.pathname.startsWith("/api/")) return; // handled by handleApi
  if (url.pathname === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ok: true, rooms: rooms.size }));
    return;
  }
  let rel = decodeURIComponent(url.pathname);
  if (rel.endsWith("/")) rel += "index.html";
  const file = path.resolve(STATIC_DIR, "." + rel);
  if (!file.startsWith(STATIC_DIR + path.sep)) {
    res.writeHead(403).end();
    return;
  }
  fs.stat(file, (err, stat) => {
    if (err || !stat.isFile()) {
      res.writeHead(404, { "Content-Type": "text/plain" }).end("Not found");
      return;
    }
    const ext = path.extname(file).toLowerCase();
    res.writeHead(200, {
      "Content-Type": MIME[ext] || "application/octet-stream",
      "Content-Length": stat.size,
      // Game files change with every export: always revalidate so players get the new build.
      "Cache-Control": "public, max-age=0, must-revalidate",
    });
    if (req.method === "HEAD") return res.end();
    fs.createReadStream(file).pipe(res);
  });
}

// --- Account API (JSON) ------------------------------------------------------------------
//   POST /api/signup  {username, password, guest?}   -> {token, profile}
//   POST /api/login   {username, password}           -> {token, profile}
//   POST /api/logout                                  (Authorization: Bearer <token>)
//   GET  /api/me                                      -> {profile}
//   POST /api/run     {score, level}                  -> {profile, reward}   single-player run
//   POST /api/buy     {kind: ships|mods|designs, id}  -> {profile}
//   POST /api/loadout {character, ship, design, mods} -> {profile}

const loginAttempts = new Map(); // ip -> {count, since}

function tooManyAttempts(ip) {
  const now = Date.now();
  const a = loginAttempts.get(ip);
  if (!a || now - a.since > 10 * 60 * 1000) {
    loginAttempts.set(ip, { count: 1, since: now });
    return false;
  }
  a.count++;
  return a.count > 20;
}

function readJson(req) {
  return new Promise((resolve) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 16384) req.destroy();
    });
    req.on("end", () => {
      try {
        resolve(JSON.parse(body || "{}"));
      } catch {
        resolve({});
      }
    });
    req.on("error", () => resolve({}));
  });
}

function json(res, status, data) {
  res.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store" });
  res.end(JSON.stringify(data));
}

async function handleApi(req, res, url) {
  const route = req.method + " " + url.pathname;
  const token = String(req.headers.authorization || "").replace(/^Bearer /, "");
  try {
    if (route === "POST /api/signup" || route === "POST /api/login") {
      const ip = req.socket.remoteAddress || "?";
      if (tooManyAttempts(ip)) return json(res, 429, { error: "Too many tries. Wait a few minutes." });
      const body = await readJson(req);
      const result = route === "POST /api/signup"
        ? accounts.signup(body.username, body.password, body.guest)
        : accounts.login(body.username, body.password);
      if (result.error) return json(res, 400, { error: result.error });
      return json(res, 200, { token: result.token, profile: accounts.view(result.user) });
    }
    const user = accounts.userForToken(token);
    if (!user) return json(res, 401, { error: "Please log in again." });
    if (route === "POST /api/logout") {
      accounts.logout(token);
      return json(res, 200, { ok: true });
    }
    if (route === "GET /api/me") return json(res, 200, { profile: accounts.view(user) });
    const body = await readJson(req);
    if (route === "POST /api/run") {
      const reward = progress.singleReward(user.profile, body.score, body.level);
      accounts.save(user);
      return json(res, 200, { profile: accounts.view(user), reward });
    }
    if (route === "POST /api/buy") {
      const error = progress.buy(user.profile, String(body.kind), String(body.id));
      if (error) return json(res, 400, { error });
      accounts.save(user);
      return json(res, 200, { profile: accounts.view(user) });
    }
    if (route === "POST /api/loadout") {
      user.profile.loadout = progress.cleanLoadout(user.profile, body);
      accounts.save(user);
      return json(res, 200, { profile: accounts.view(user) });
    }
    return json(res, 404, { error: "Unknown request." });
  } catch (err) {
    console.error(err);
    return json(res, 500, { error: "Server error." });
  }
}

// --- Rooms -------------------------------------------------------------------------------

/** code -> { code, hostId, phase: "lobby"|"countdown"|"racing", players: Map<id, player>, raceStart, finishCount } */
const rooms = new Map();
let nextId = 1;

function newCode() {
  for (;;) {
    let code = "";
    for (let i = 0; i < 4; i++) code += CODE_LETTERS[crypto.randomInt(CODE_LETTERS.length)];
    if (!rooms.has(code)) return code;
  }
}

function cleanName(name) {
  const s = String(name || "").replace(/[^A-Za-z0-9 _-]/g, "").trim().slice(0, 12);
  return s || "Pilot";
}

function send(ws, msg) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
}

function broadcast(room, msg, exceptId) {
  const data = JSON.stringify(msg);
  for (const p of room.players.values()) {
    if (p.id !== exceptId && p.ws.readyState === p.ws.OPEN) p.ws.send(data);
  }
}

function publicPlayer(p) {
  return { id: p.id, name: p.name, color: p.color };
}

function sendRoom(room) {
  const players = [...room.players.values()].map(publicPlayer);
  for (const p of room.players.values()) {
    send(p.ws, {
      t: "room",
      code: room.code,
      you: p.id,
      host: room.hostId,
      phase: room.phase,
      min: MIN_PLAYERS,
      max: MAX_PLAYERS,
      players,
    });
  }
}

function freeColor(room) {
  const used = new Set([...room.players.values()].map((p) => p.color));
  return COLORS.find((c) => !used.has(c)) || COLORS[0];
}

function addPlayer(room, client) {
  const player = {
    id: client.id,
    ws: client.ws,
    client,
    name: cleanName(client.username),
    color: freeColor(room),
    status: "lobby",
    d: 0,
    score: 0,
    timeMs: 0,
    place: 0,
  };
  room.players.set(player.id, player);
  client.room = room;
  sendRoom(room);
}

function leaveRoom(client) {
  const room = client.room;
  if (!room) return;
  client.room = null;
  room.players.delete(client.id);
  if (room.players.size === 0) {
    rooms.delete(room.code);
    return;
  }
  if (room.hostId === client.id) room.hostId = room.players.keys().next().value;
  broadcast(room, { t: "left", id: client.id });
  if (room.phase !== "lobby") checkRaceOver(room);
  sendRoom(room);
}

function startRace(room) {
  room.phase = "countdown";
  room.finishCount = 0;
  room.raceStart = Date.now() + COUNTDOWN_MS + INTRO_MS;
  for (const p of room.players.values()) {
    Object.assign(p, { status: "racing", d: 0, score: 0, timeMs: 0, place: 0 });
  }
  const seed = crypto.randomInt(1, 2 ** 31 - 1);
  broadcast(room, { t: "start", seed, countdown: COUNTDOWN_MS / 1000 });
  sendRoom(room);
  setTimeout(() => {
    if (room.phase === "countdown") room.phase = "racing";
  }, COUNTDOWN_MS);
}

function checkRaceOver(room) {
  const players = [...room.players.values()];
  if (players.some((p) => p.status === "racing")) return;
  // Finishers by finishing order, then everyone else by how far they got.
  const ranking = players
    .slice()
    .sort((a, b) => {
      const af = a.status === "finished", bf = b.status === "finished";
      if (af !== bf) return af ? -1 : 1;
      if (af) return a.place - b.place;
      return b.d - a.d;
    })
    .map((p, i) => ({ ...publicPlayer(p), rank: i + 1, status: p.status, d: p.d, score: p.score, timeMs: p.timeMs }));
  broadcast(room, { t: "results", ranking });
  giveRaceRewards(room, ranking);
  room.phase = "lobby";
  for (const p of players) p.status = "lobby";
  sendRoom(room);
}

/** XP and credits for everyone in the race, saved to their accounts. */
function giveRaceRewards(room, ranking) {
  for (const row of ranking) {
    const p = room.players.get(row.id);
    if (!p || !p.client.token) continue;
    const user = accounts.userForToken(p.client.token); // fresh copy (they may have shopped meanwhile)
    if (!user) continue;
    const reward = progress.raceReward(user.profile, {
      score: row.score,
      levelReached: Math.min(Math.floor(row.d / LEVEL_DURATION) + 1, RACE_LEVELS),
      rank: row.rank,
      finished: row.status === "finished",
      racers: ranking.length,
    });
    accounts.save(user);
    send(p.ws, { t: "reward", reward, profile: accounts.view(user) });
  }
}

function num(v, min, max) {
  const n = Number(v);
  if (!Number.isFinite(n)) return min;
  return Math.min(max, Math.max(min, n));
}

function handle(client, msg) {
  const room = client.room;
  switch (msg.t) {
    case "auth": {
      // Multiplayer needs an account: the game sends its login token first.
      const user = accounts.userForToken(msg.token);
      if (!user) return send(client.ws, { t: "auth_failed", msg: "Log in to play multiplayer." });
      client.token = msg.token;
      client.username = user.username;
      send(client.ws, { t: "auth_ok", username: user.username });
      break;
    }
    case "create": {
      if (!client.token) return send(client.ws, { t: "error", msg: "Log in to play multiplayer." });
      if (room) leaveRoom(client);
      const code = newCode();
      const created = { code, hostId: client.id, phase: "lobby", players: new Map(), raceStart: 0, finishCount: 0 };
      rooms.set(code, created);
      addPlayer(created, client);
      break;
    }
    case "join": {
      if (!client.token) return send(client.ws, { t: "error", msg: "Log in to play multiplayer." });
      const code = String(msg.code || "").toUpperCase().trim();
      const target = rooms.get(code);
      if (!target) return send(client.ws, { t: "error", msg: `No room called ${code || "?"}. Check the code.` });
      if (target === room) return sendRoom(room);
      if (target.players.size >= MAX_PLAYERS) return send(client.ws, { t: "error", msg: "That room is full." });
      if (target.phase !== "lobby") return send(client.ws, { t: "error", msg: "That race has already started. Try again when it ends." });
      if (room) leaveRoom(client);
      addPlayer(target, client);
      break;
    }
    case "leave":
      leaveRoom(client);
      send(client.ws, { t: "left_room" });
      break;
    case "start": {
      if (!room) return;
      if (room.hostId !== client.id) return send(client.ws, { t: "error", msg: "Only the host can start the race." });
      if (room.phase !== "lobby") return;
      if (room.players.size < MIN_PLAYERS) {
        return send(client.ws, { t: "error", msg: `Need at least ${MIN_PLAYERS} pilots to race.` });
      }
      startRace(room);
      break;
    }
    case "state": {
      // Live flight data: x = 0..1 across the screen, d = distance flown, h = hull, b = boosting.
      if (!room || room.phase === "lobby") return;
      const p = room.players.get(client.id);
      if (!p || p.status !== "racing") return;
      p.d = num(msg.d, 0, 1e7);
      broadcast(room, { t: "state", id: p.id, x: num(msg.x, 0, 1), d: p.d, h: num(msg.h, 0, 2), b: !!msg.b, k: !!msg.k }, p.id);
      break;
    }
    case "crashed":
    case "finished": {
      if (!room || room.phase === "lobby") return;
      const p = room.players.get(client.id);
      if (!p || p.status !== "racing") return;
      p.d = num(msg.d, 0, 1e7);
      p.score = Math.round(num(msg.score, 0, 1e9));
      if (msg.t === "finished") {
        p.status = "finished";
        p.place = ++room.finishCount;
        p.timeMs = Math.max(0, Date.now() - room.raceStart);
      } else {
        p.status = "crashed";
      }
      broadcast(room, { t: msg.t, id: p.id, d: p.d, score: p.score, place: p.place, timeMs: p.timeMs });
      checkRaceOver(room);
      break;
    }
    case "ping":
      send(client.ws, { t: "pong" });
      break;
  }
}

// --- Server ------------------------------------------------------------------------------

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");
  if (url.pathname.startsWith("/api/")) return handleApi(req, res, url);
  serveStatic(req, res);
});
const wss = new WebSocketServer({ server, path: "/ws", maxPayload: 4096 });

wss.on("connection", (ws) => {
  const client = { id: nextId++, ws, room: null, alive: true };
  ws.on("pong", () => (client.alive = true));
  ws.on("message", (data) => {
    let msg;
    try {
      msg = JSON.parse(data.toString());
    } catch {
      return;
    }
    if (msg && typeof msg.t === "string") handle(client, msg);
  });
  ws.on("close", () => leaveRoom(client));
  ws.on("error", () => {});
  client.ws._client = client;
  send(ws, { t: "hello", id: client.id });
});

// Drop connections that stopped answering (closed laptop, lost signal).
setInterval(() => {
  for (const ws of wss.clients) {
    const client = ws._client;
    if (!client) continue;
    if (!client.alive) {
      ws.terminate();
      continue;
    }
    client.alive = false;
    ws.ping();
  }
}, 15000);

server.listen(PORT, () => {
  console.log(`Rocket Race server on http://localhost:${PORT}  (game files: ${STATIC_DIR})`);
});
