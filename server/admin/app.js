// Rocket Race admin ticket page. Talks to /api/admin/* on the same server.
// Everything players wrote is inserted with textContent (never as HTML).
"use strict";

const STATUSES = [
  ["all", "All"], ["new", "New"], ["open", "Open"], ["in_progress", "In progress"], ["resolved", "Resolved"],
];
const CATEGORY_NAMES = { bug: "Bug", player: "Player", suggestion: "Idea", other: "Other" };
const $ = (id) => document.getElementById(id);

const state = { status: "new", category: "all", q: "", selected: 0, tickets: [] };

async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: { "Content-Type": "application/json", "X-Admin": "1" },
    body: body ? JSON.stringify(body) : undefined,
    credentials: "same-origin",
  });
  const data = await res.json().catch(() => ({}));
  if (res.status === 401 && path !== "/api/admin/login") {
    showLogin();
    throw new Error(data.error || "Please log in.");
  }
  if (!res.ok) throw new Error(data.error || "Something went wrong.");
  return data;
}

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") node.className = v;
    else if (k === "text") node.textContent = v;
    else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v);
  }
  for (const c of children) if (c != null) node.append(c);
  return node;
}

function ago(ms) {
  const s = Math.max(0, (Date.now() - ms) / 1000);
  if (s < 60) return "just now";
  if (s < 3600) return Math.floor(s / 60) + " min ago";
  if (s < 86400) return Math.floor(s / 3600) + " h ago";
  if (s < 86400 * 30) return Math.floor(s / 86400) + " d ago";
  return new Date(ms).toLocaleDateString();
}
const fullDate = (ms) => new Date(ms).toLocaleString();
const statusLabel = (s) => (STATUSES.find(([k]) => k === s) || [s, s])[1];

// --- Login -----------------------------------------------------------------------------

function showLogin() {
  $("app").hidden = true;
  $("login").hidden = false;
  $("login-user").focus();
}

$("login-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  $("login-error").textContent = "";
  try {
    const me = await api("POST", "/api/admin/login", { username: $("login-user").value, password: $("login-pass").value });
    $("login-pass").value = "";
    start(me.username);
  } catch (err) {
    $("login-error").textContent = err.message;
  }
});

$("logout").addEventListener("click", async () => {
  await api("POST", "/api/admin/logout").catch(() => {});
  showLogin();
});

// --- List --------------------------------------------------------------------------------

function renderTabs(counts) {
  const nav = $("status-tabs");
  nav.replaceChildren(...STATUSES.map(([key, label]) =>
    el("button", { class: "tab", "aria-pressed": String(state.status === key), onclick: () => { state.status = key; loadList(); } },
      label, el("span", { class: "count", text: String(counts[key] || 0) }))));
}

async function loadList() {
  const params = new URLSearchParams({ status: state.status, category: state.category, q: state.q });
  let data;
  try {
    data = await api("GET", "/api/admin/tickets?" + params);
  } catch {
    return;
  }
  state.tickets = data.rows;
  renderTabs(data.counts);
  const tpl = $("ticket-row");
  $("tickets").replaceChildren(...data.rows.map((t) => {
    const li = tpl.content.firstElementChild.cloneNode(true);
    const btn = li.querySelector(".row");
    btn.setAttribute("aria-current", String(t.id === state.selected));
    btn.addEventListener("click", () => openTicket(t.id));
    li.querySelector(".id").textContent = "#" + t.id;
    li.querySelector(".cat").replaceChildren(el("span", { class: "chip cat-" + t.category, text: CATEGORY_NAMES[t.category] || t.category }));
    li.querySelector(".status").replaceChildren(el("span", { class: "chip status-" + t.status, text: statusLabel(t.status) }));
    li.querySelector(".when").textContent = ago(t.created_at);
    li.querySelector(".preview").textContent = t.preview;
    li.querySelector(".from").textContent = "from " + t.username + (t.target ? " · about " + t.target : "");
    li.querySelector(".notes").textContent = t.notes ? t.notes + (t.notes === 1 ? " note" : " notes") : "";
    return li;
  }));
  $("empty").hidden = data.rows.length > 0;
  $("refreshed").textContent = "Updated " + new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

$("category").addEventListener("change", (e) => { state.category = e.target.value; loadList(); });
let searchTimer = 0;
$("search").addEventListener("input", (e) => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => { state.q = e.target.value.trim(); loadList(); }, 250);
});

// --- Detail ------------------------------------------------------------------------------

function personCard(title, p) {
  if (!p) return el("div", { class: "person" }, el("h3", { text: title }), el("span", { class: "muted", text: "Guest (no account)" }));
  if (!p.exists) {
    return el("div", { class: "person" }, el("h3", { text: title }), el("span", { class: "name", text: p.username }),
      el("div", { class: "muted", text: "No account with this name (deleted, or typed wrong)." }));
  }
  const rows = [
    ["Email", p.email || "none"], ["Joined", new Date(p.created_at).toLocaleDateString()],
    ["Levels", `SP ${p.sp_level} · MP ${p.mp_level}`], ["Races", String(p.races)],
    ["Reports sent", String(p.reports_sent)], ["Reported", `${p.reported_times} time${p.reported_times === 1 ? "" : "s"}`],
  ];
  const dl = el("dl");
  for (const [k, v] of rows) dl.append(el("dt", { text: k }), el("dd", { text: v }));
  return el("div", { class: "person" }, el("h3", { text: title }),
    el("span", { class: "name", text: p.username + (p.admin ? " (admin)" : "") }), dl,
    el("button", { class: "ghost open-player", text: "Open player", onclick: () => openPlayer(p.username) }));
}

async function openTicket(id) {
  state.selected = id;
  document.querySelectorAll(".row").forEach((b) => b.setAttribute("aria-current", "false"));
  let t;
  try {
    t = await api("GET", "/api/admin/tickets/" + id);
  } catch (err) {
    $("detail").replaceChildren(el("p", { class: "error", text: err.message }));
    return;
  }
  renderTicket(t);
  loadList();
  if (window.matchMedia("(max-width: 760px)").matches) $("detail").scrollIntoView({ behavior: "smooth" });
}

function renderTicket(t) {
  const statusButtons = el("div", { class: "status-set", role: "group", "aria-label": "Set status" },
    ...STATUSES.slice(1).map(([key, label]) => el("button", {
      class: "status-" + key, "aria-pressed": String(t.status === key), text: label,
      onclick: async () => {
        try { renderTicket(await api("POST", `/api/admin/tickets/${t.id}/status`, { status: key })); loadList(); }
        catch (err) { alert(err.message); }
      },
    })));

  const notes = el("ul", { class: "notes-list" }, ...t.notes.map((n) =>
    el("li", { class: "note" + (n.author === "system" ? " system" : "") },
      el("span", { class: "by", text: (n.author === "system" ? "" : n.author + " · ") + fullDate(n.created_at) }),
      el("p", { text: n.text }))));
  const text = el("textarea", { placeholder: "Private note (only admins see this)", maxlength: "2000", "aria-label": "New note" });
  const err = el("span", { class: "error" });
  const form = el("form", { class: "note-form", onsubmit: async (e) => {
    e.preventDefault();
    try { renderTicket(await api("POST", `/api/admin/tickets/${t.id}/notes`, { text: text.value })); loadList(); }
    catch (e2) { err.textContent = e2.message; }
  } }, text, el("div", {}, el("button", { class: "primary", type: "submit", text: "Add note" }), err));

  $("detail").replaceChildren(
    el("h2", { text: `#${t.id} · ${CATEGORY_NAMES[t.category] || t.category}` }),
    el("div", { class: "meta" },
      el("span", { class: "chip status-" + t.status, text: statusLabel(t.status) }),
      el("span", { text: "Sent " + fullDate(t.created_at) }),
      t.platform ? el("span", { text: "· " + t.platform }) : null),
    el("div", { class: "message", text: t.message }),
    el("p", { class: "section-title", text: "Status" }), statusButtons,
    el("div", { class: "people" }, personCard("Reported by", t.reporter),
      t.target ? personCard("Reported player", t.target_account) : null),
    el("p", { class: "section-title", text: "Notes" }), notes, form);
}

// --- Players: search, view and edit accounts ----------------------------------------------

const MODES = [["sp", "Single Player"], ["mp", "Multiplayer"]];
const KIND_NAMES = { ships: "Ships", mods: "Mods", designs: "Paint" };
let currentPlayer = "";

function showView(name) {
  $("tickets-view").hidden = name !== "tickets";
  $("players-view").hidden = name !== "players";
  $("nav-tickets").setAttribute("aria-pressed", String(name === "tickets"));
  $("nav-players").setAttribute("aria-pressed", String(name === "players"));
  if (name === "players") loadPlayers();
}
$("nav-tickets").addEventListener("click", () => showView("tickets"));
$("nav-players").addEventListener("click", () => showView("players"));

async function loadPlayers() {
  let data;
  try {
    data = await api("GET", "/api/admin/players?" + new URLSearchParams({ q: $("player-search").value.trim() }));
  } catch {
    return;
  }
  $("players").replaceChildren(...data.rows.map((p) => el("li", {},
    el("button", { class: "row", "aria-current": String(p.username === currentPlayer), onclick: () => openPlayer(p.username) },
      el("span", { class: "row-top" }, el("span", { class: "id", text: p.username + (p.admin ? " (admin)" : "") }, p.test ? el("span", { class: "test-tag", text: "TEST" }) : null),
        el("span", { class: "when muted", text: "joined " + ago(p.created_at) })),
      el("span", { class: "row-bottom muted" },
        el("span", { text: `SP Lvl ${p.sp_level} · ${p.sp_credits} cr   ·   MP Lvl ${p.mp_level} · ${p.mp_credits} cr` }))))));
  $("players-empty").hidden = data.rows.length > 0;
}
$("new-test").addEventListener("submit", async (e) => {
  e.preventDefault();
  $("nt-msg").className = "error";
  $("nt-msg").textContent = "";
  try {
    const p = await api("POST", "/api/admin/players", { username: $("nt-user").value.trim(), password: $("nt-pass").value, email: $("nt-mail").value.trim() });
    $("nt-user").value = ""; $("nt-pass").value = ""; $("nt-mail").value = "";
    $("nt-msg").className = "ok";
    $("nt-msg").textContent = `Created ${p.username}. Log in to the game with it.`;
    currentPlayer = p.username;
    renderPlayer(p, "Test account created.");
    loadPlayers();
  } catch (err) {
    $("nt-msg").textContent = err.message;
  }
});

let playerTimer = 0;
$("player-search").addEventListener("input", () => {
  clearTimeout(playerTimer);
  playerTimer = setTimeout(loadPlayers, 250);
});

async function openPlayer(name) {
  showView("players");
  currentPlayer = name;
  try {
    renderPlayer(await api("GET", "/api/admin/players/" + encodeURIComponent(name)));
  } catch (err) {
    $("player-detail").replaceChildren(el("p", { class: "error", text: err.message }));
  }
  loadPlayers();
  if (window.matchMedia("(max-width: 760px)").matches) $("player-detail").scrollIntoView({ behavior: "smooth" });
}

function renderPlayer(p, message = "", isError = false) {
  const status = el("p", { class: isError ? "error" : "ok", text: message });
  const send = async (path, body, done) => {
    try {
      renderPlayer(await api("POST", `/api/admin/players/${encodeURIComponent(p.username)}/${path}`, body), done);
      loadPlayers();
    } catch (err) {
      status.className = "error";
      status.textContent = err.message;
    }
  };

  const modeCard = (track, title) => {
    const t = p[track];
    const lvl = p[track + "_level"];
    const xp = el("input", { type: "number", step: "100", placeholder: "e.g. 1000 or -500", "aria-label": title + " XP" });
    const cr = el("input", { type: "number", step: "50", placeholder: "e.g. 500 or -200", "aria-label": title + " credits" });
    const form = el("form", { class: "adjust", onsubmit: (e) => {
      e.preventDefault();
      send("adjust", { track, xp: Number(xp.value) || 0, credits: Number(cr.value) || 0 }, `${title} updated.`);
    } }, el("label", {}, "XP (+/-)", xp), el("label", {}, "Credits (+/-)", cr),
      el("button", { class: "primary", type: "submit", text: "Apply" }));
    const groups = Object.entries(KIND_NAMES).map(([kind, label]) => el("div", { class: "item-group" },
      el("span", { text: label }),
      el("div", { class: "items" }, ...p.catalog[kind].map((id) => {
        const owned = t.owned[kind].includes(id);
        const starter = id === "small" || id === "classic";
        return el("button", {
          class: "item", "aria-pressed": String(owned), text: id,
          title: starter ? "Starter item" : (owned ? "Click to remove" : "Click to unlock"),
          onclick: () => { if (!starter) send("item", { track, kind, id, owned: !owned }, `${title}: ${owned ? "removed" : "unlocked"} ${id}.`); },
        });
      }))));
    return el("div", { class: "mode-card" }, el("h3", { text: title }),
      el("div", { class: "nums" },
        el("span", { class: "muted" }, el("b", { text: "Lvl " + lvl.level }), lvl.need ? `${lvl.into} / ${lvl.need} XP` : "MAX"),
        el("span", { class: "muted" }, el("b", { text: String(t.credits) }), "credits"),
        el("span", { class: "muted" }, el("b", { text: String(t.xp) }), "total XP")),
      form, ...groups);
  };

  const st = p.stats;
  const history = el("ul", { class: "history" }, ...(p.history.length ? p.history.map((h) =>
    el("li", {}, new Date(h.created_at).toLocaleString() + " · ", el("b", { text: h.admin }), ": " + h.action))
    : [el("li", { text: "No admin changes yet." })]));

  $("player-detail").replaceChildren(
    el("h2", { text: p.username + (p.admin ? " (admin)" : "") }, p.test ? el("span", { class: "test-tag", text: "TEST" }) : null),
    el("div", { class: "meta" }, el("span", { text: p.email || "no email" }), el("span", { text: "· pilot: " + p.character }),
      el("span", { text: "· joined " + new Date(p.created_at).toLocaleDateString() })),
    el("p", { class: "muted", text: `Runs ${st.sp_runs} · best ${st.sp_best}   ·   Races ${st.mp_races} · wins ${st.mp_wins} · best race ${st.mp_best}` }),
    status,
    el("div", { class: "mode-grid" }, ...MODES.map(([track, title]) => modeCard(track, title))),
    el("p", { class: "section-title", text: "Change history" }), history,
    p.test ? el("button", { class: "danger", text: "Delete test account", onclick: async () => {
      if (!confirm(`Delete the test account "${p.username}"? This can't be undone.`)) return;
      try {
        await api("POST", `/api/admin/players/${encodeURIComponent(p.username)}/delete`);
        currentPlayer = "";
        $("player-detail").replaceChildren(el("p", { class: "ok placeholder", text: `Deleted test account ${p.username}.` }));
        loadPlayers();
      } catch (err) { status.className = "error"; status.textContent = err.message; }
    } }) : null);
}

// --- Start -------------------------------------------------------------------------------

function start(username) {
  $("login").hidden = true;
  $("app").hidden = false;
  $("who").textContent = username;
  loadList();
}

setInterval(() => { if (!$("app").hidden) loadList(); }, 30000);

api("GET", "/api/admin/me").then((me) => start(me.username)).catch(() => showLogin());
