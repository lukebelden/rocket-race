// Progression rules (levels, rewards, shop, loadout). Numbers come from ../catalog.json,
// which the game reads too. profile.gd mirrors these rules for guests (device-only play).
//
// Single player and multiplayer are separate tracks, each with its own XP/level, credits,
// owned items and hangar loadout: what you earn in one mode is spent in that mode's shop,
// and unlocks follow that mode's level. The animal pilot is shared.

const fs = require("fs");
const path = require("path");

const CATALOG_PATH = process.env.CATALOG || path.join(__dirname, "..", "catalog.json");
const catalog = JSON.parse(fs.readFileSync(CATALOG_PATH, "utf8"));
const L = catalog.levels;
const R = catalog.rewards;
const TRACKS = ["sp", "mp"];

const byId = (list) => Object.fromEntries(list.map((x) => [x.id, x]));
const SHIPS = byId(catalog.ships);
const MODS = byId(catalog.mods);
const DESIGNS = byId(catalog.designs);
const CHARACTERS = byId(catalog.characters);
const TABLES = { ships: SHIPS, mods: MODS, designs: DESIGNS };

/** XP needed to go from `level` to the next one. */
function xpToNext(level) {
  return L.first + L.step * (level - 1);
}

/** Total XP -> { level, into (XP into this level), need (XP for the next level, 0 at max) } */
function levelInfo(xp) {
  let level = 1;
  let rem = Math.max(0, Math.floor(xp || 0));
  while (level < L.max && rem >= xpToNext(level)) {
    rem -= xpToNext(level);
    level++;
  }
  return { level, into: rem, need: level >= L.max ? 0 : xpToNext(level) };
}

function newTrack() {
  return {
    xp: 0,
    credits: 0,
    owned: { ships: ["small"], mods: [], designs: ["classic"] },
    loadout: { ship: "small", design: "classic", mods: [] },
  };
}

function newProfile() {
  return {
    character: "duck",
    sp: newTrack(),
    mp: newTrack(),
    stats: { sp_runs: 0, sp_best: 0, mp_races: 0, mp_wins: 0, mp_best: 0 },
  };
}

const int = (v, max) => Math.max(0, Math.min(max, Math.floor(Number(v) || 0)));

function cleanTrack(input, checkLevels = false) {
  const t = newTrack();
  if (!input || typeof input !== "object") return t;
  t.xp = int(input.xp, 1e9);
  t.credits = int(input.credits, 1e9);
  const lvl = levelInfo(t.xp).level;
  const owned = input.owned || {};
  for (const kind of ["ships", "mods", "designs"]) {
    const out = new Set(t.owned[kind]);
    for (const id of Array.isArray(owned[kind]) ? owned[kind] : []) {
      if (TABLES[kind][id] && (!checkLevels || TABLES[kind][id].level <= lvl)) out.add(id);
    }
    t.owned[kind] = [...out];
  }
  t.loadout = cleanLoadout(t, input.loadout || {});
  return t;
}

/** Make any stored/uploaded profile safe and complete (unknown ids dropped, numbers clamped).
 *  Also upgrades the older single-wallet profile shape (credits/owned/loadout at the top). */
function sanitize(input, { allowMp = true, checkLevels = false } = {}) {
  const p = newProfile();
  if (!input || typeof input !== "object") return p;
  const legacy = input.owned && !(input.sp && input.sp.owned);
  if (legacy) {
    input = {
      character: input.loadout && input.loadout.character,
      sp: { xp: input.sp && input.sp.xp, credits: input.credits, owned: input.owned, loadout: input.loadout },
      mp: { xp: input.mp && input.mp.xp },
      stats: input.stats,
    };
  }
  p.character = CHARACTERS[input.character] ? input.character : "duck";
  p.sp = cleanTrack(input.sp, checkLevels);
  p.mp = allowMp ? cleanTrack(input.mp, checkLevels) : newTrack();
  const stats = input.stats || {};
  p.stats = {
    sp_runs: int(stats.sp_runs, 1e9),
    sp_best: int(stats.sp_best, 1e9),
    mp_races: allowMp ? int(stats.mp_races, 1e9) : 0,
    mp_wins: allowMp ? int(stats.mp_wins, 1e9) : 0,
    mp_best: allowMp ? int(stats.mp_best, 1e9) : 0,
  };
  return p;
}

/** A loadout limited to what this track owns, with no more mods than the ship has slots. */
function cleanLoadout(track, want) {
  const owned = track.owned;
  const ship = owned.ships.includes(want.ship) ? want.ship : owned.ships.includes(track.loadout && track.loadout.ship) ? track.loadout.ship : "small";
  const mods = [];
  for (const id of Array.isArray(want.mods) ? want.mods : []) {
    if (owned.mods.includes(id) && !mods.includes(id) && mods.length < SHIPS[ship].slots) mods.push(id);
  }
  return { ship, design: owned.designs.includes(want.design) ? want.design : "classic", mods };
}

/** Add XP + credits to one track; level-ups pay a bonus. Returns a summary. */
function grant(p, track, xp, credits) {
  const t = p[track];
  const before = levelInfo(t.xp).level;
  t.xp += xp;
  const after = levelInfo(t.xp).level;
  let bonus = 0;
  for (let lv = before + 1; lv <= after; lv++) bonus += R.level_up_credits * lv;
  t.credits += credits + bonus;
  return { track, xp, credits: credits + bonus, level_up_credits: bonus, level_before: before, level_after: after };
}

/** Single-player run finished. */
function singleReward(p, score, levelReached) {
  score = int(score, 500000);
  levelReached = Math.max(1, int(levelReached, 500));
  p.stats.sp_runs++;
  p.stats.sp_best = Math.max(p.stats.sp_best, score);
  const xp = score + R.xp_per_level_reached * levelReached;
  const credits = Math.floor(score / R.score_per_credit) + R.credits_per_level_reached * levelReached;
  return grant(p, "sp", xp, credits);
}

/** Race over. rank is 1-based; place bonuses only count when you actually raced someone. */
function raceReward(p, { score, levelReached, rank, finished, racers }) {
  score = int(score, 500000);
  levelReached = Math.max(1, int(levelReached, 500));
  let xp = score + R.xp_per_level_reached * levelReached;
  let credits = Math.floor(score / R.score_per_credit) + R.credits_per_level_reached * levelReached;
  if (racers >= 2) {
    xp += R.race_place_xp[rank - 1] || 0;
    credits += R.race_place_credits[rank - 1] || 0;
  }
  if (finished) xp += R.race_finish_xp;
  p.stats.mp_races++;
  p.stats.mp_best = Math.max(p.stats.mp_best, score);
  if (rank === 1 && racers >= 2) p.stats.mp_wins++;
  return grant(p, "mp", xp, credits);
}

/** Buy a ship / mod / design in one mode's shop. Returns an error message, or "" on success. */
function buy(p, track, kind, id) {
  if (!TRACKS.includes(track)) return "Unknown shop.";
  const item = TABLES[kind] && TABLES[kind][id];
  if (!item) return "That item doesn't exist.";
  const t = p[track];
  if (t.owned[kind].includes(id)) return "You already own that.";
  const lvl = levelInfo(t.xp).level;
  const mode = track === "sp" ? "Single Player" : "Multiplayer";
  if (lvl < catalog.shop_level) return `The ${mode} shop opens at ${mode} level ${catalog.shop_level}.`;
  if (lvl < item.level) return `Unlocks at ${mode} level ${item.level}.`;
  if (t.credits < item.price) return "Not enough credits.";
  t.credits -= item.price;
  t.owned[kind].push(id);
  return "";
}

function setLoadout(p, track, want) {
  if (!TRACKS.includes(track)) return;
  p[track].loadout = cleanLoadout(p[track], want || {});
}

function setCharacter(p, id) {
  if (CHARACTERS[id]) p.character = id;
}

module.exports = { catalog, levelInfo, newProfile, sanitize, singleReward, raceReward, buy, setLoadout, setCharacter, SHIPS };
