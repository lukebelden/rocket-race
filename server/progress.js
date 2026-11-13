// Progression rules (levels, rewards, shop, loadout). Numbers come from ../catalog.json,
// which the game reads too. profile.gd mirrors these rules for guests (device-only play).

const fs = require("fs");
const path = require("path");

const CATALOG_PATH = process.env.CATALOG || path.join(__dirname, "..", "catalog.json");
const catalog = JSON.parse(fs.readFileSync(CATALOG_PATH, "utf8"));
const L = catalog.levels;
const R = catalog.rewards;

const byId = (list) => Object.fromEntries(list.map((x) => [x.id, x]));
const SHIPS = byId(catalog.ships);
const MODS = byId(catalog.mods);
const DESIGNS = byId(catalog.designs);
const CHARACTERS = byId(catalog.characters);

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

function newProfile() {
  return {
    sp: { xp: 0 },
    mp: { xp: 0 },
    credits: 0,
    owned: { ships: ["small"], mods: [], designs: ["classic"] },
    loadout: { character: "duck", ship: "small", design: "classic", mods: [] },
    stats: { sp_runs: 0, sp_best: 0, mp_races: 0, mp_wins: 0 },
  };
}

/** Highest of the two levels: decides what's unlocked in the shop. */
function pilotLevel(p) {
  return Math.max(levelInfo(p.sp.xp).level, levelInfo(p.mp.xp).level);
}

const int = (v, max) => Math.max(0, Math.min(max, Math.floor(Number(v) || 0)));

/** Make any stored/uploaded profile safe and complete (unknown ids dropped, numbers clamped). */
function sanitize(input, { allowMp = true } = {}) {
  const p = newProfile();
  if (!input || typeof input !== "object") return p;
  p.sp.xp = int(input.sp && input.sp.xp, 1e9);
  p.mp.xp = allowMp ? int(input.mp && input.mp.xp, 1e9) : 0;
  p.credits = int(input.credits, 1e9);
  const lvl = pilotLevel(p);
  const owned = input.owned || {};
  const keep = (list, table, base) => {
    const out = new Set(base);
    for (const id of Array.isArray(list) ? list : []) {
      if (table[id] && table[id].level <= lvl) out.add(id);
    }
    return [...out];
  };
  p.owned.ships = keep(owned.ships, SHIPS, ["small"]);
  p.owned.mods = keep(owned.mods, MODS, []);
  p.owned.designs = keep(owned.designs, DESIGNS, ["classic"]);
  const stats = input.stats || {};
  p.stats = {
    sp_runs: int(stats.sp_runs, 1e9),
    sp_best: int(stats.sp_best, 1e9),
    mp_races: allowMp ? int(stats.mp_races, 1e9) : 0,
    mp_wins: allowMp ? int(stats.mp_wins, 1e9) : 0,
  };
  p.loadout = cleanLoadout(p, input.loadout || {});
  return p;
}

/** A loadout limited to things the profile owns, with no more mods than the ship has slots. */
function cleanLoadout(p, want) {
  const ship = p.owned.ships.includes(want.ship) ? want.ship : p.owned.ships.includes(p.loadout.ship) ? p.loadout.ship : "small";
  const mods = [];
  for (const id of Array.isArray(want.mods) ? want.mods : []) {
    if (p.owned.mods.includes(id) && !mods.includes(id) && mods.length < SHIPS[ship].slots) mods.push(id);
  }
  return {
    character: CHARACTERS[want.character] ? want.character : "duck",
    ship,
    design: p.owned.designs.includes(want.design) ? want.design : "classic",
    mods,
  };
}

/** Add XP + credits to one track ("sp" or "mp"); level-ups pay a bonus. Returns a summary. */
function grant(p, track, xp, credits) {
  const before = levelInfo(p[track].xp).level;
  p[track].xp += xp;
  const after = levelInfo(p[track].xp).level;
  let bonus = 0;
  for (let lv = before + 1; lv <= after; lv++) bonus += R.level_up_credits * lv;
  p.credits += credits + bonus;
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
  if (rank === 1 && racers >= 2) p.stats.mp_wins++;
  return grant(p, "mp", xp, credits);
}

/** Buy a ship / mod / design. Returns an error message, or "" on success. */
function buy(p, kind, id) {
  const table = { ships: SHIPS, mods: MODS, designs: DESIGNS }[kind];
  const item = table && table[id];
  if (!item) return "That item doesn't exist.";
  if (p.owned[kind].includes(id)) return "You already own that.";
  const lvl = pilotLevel(p);
  if (lvl < catalog.shop_level) return `The shop opens at level ${catalog.shop_level}.`;
  if (lvl < item.level) return `Unlocks at level ${item.level}.`;
  if (p.credits < item.price) return "Not enough credits.";
  p.credits -= item.price;
  p.owned[kind].push(id);
  return "";
}

module.exports = { catalog, levelInfo, newProfile, sanitize, cleanLoadout, singleReward, raceReward, buy, pilotLevel, SHIPS };
