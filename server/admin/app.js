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
    el("span", { class: "name", text: p.username + (p.admin ? " (admin)" : "") }), dl);
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

// --- Start -------------------------------------------------------------------------------

function start(username) {
  $("login").hidden = true;
  $("app").hidden = false;
  $("who").textContent = username;
  loadList();
}

setInterval(() => { if (!$("app").hidden) loadList(); }, 30000);

api("GET", "/api/admin/me").then((me) => start(me.username)).catch(() => showLogin());
