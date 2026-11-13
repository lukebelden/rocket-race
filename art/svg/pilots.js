// Rocket Race - flat 2D "sticker" astronaut pilots as SVG.
//   node art/svg/pilots.js          -> art/svg/<animal>.svg (viewBox 200x260)
// Flat fills, one crescent shadow per shape, thick ink outlines, simple shines.
// The head sits small inside a glass bubble helmet; the suit is the big shape.
const fs = require("fs");
const path = require("path");

const INK = "#1e2238";
const W = 4; // outline width
const TRIM = { duck: "#f0893c", mouse: "#4fb8a8", dog: "#5aa9e6", cat: "#9a73d6", bear: "#e5683b",
  raccoon: "#7ed6a0", monkey: "#ffc56b", penguin: "#ef6a5a" };

// Shadow tone: base tinted cool and darker.
function shade(hex, k = 0.8) {
  const n = parseInt(hex.slice(1), 16);
  const r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
  const f = (v, t) => Math.round(v * k + t * (1 - k) * 0.55);
  return "#" + [f(r, 70), f(g, 80), f(b, 140)].map((v) => Math.min(255, v).toString(16).padStart(2, "0")).join("");
}

let uid = 0;
// A shape with a crescent shadow on the lower right and an ink outline.
// `el` is an SVG element without fill, e.g. '<ellipse cx="1" cy="2" rx="3" ry="4"/>'.
function part(el, base, { shadow = shade(base), dx = -5, dy = -5, stroke = W, outline = true } = {}) {
  const id = "c" + uid++;
  return `<clipPath id="${id}">${el}</clipPath>` +
    `<g fill="${shadow}">${el}</g>` +
    `<g clip-path="url(#${id})"><g fill="${base}" transform="translate(${dx},${dy})">${el}</g></g>` +
    (outline ? `<g fill="none" stroke="${INK}" stroke-width="${stroke}" stroke-linejoin="round">${el}</g>` : "");
}
const flat = (el, fill, stroke = 0) =>
  `<g fill="${fill}"${stroke ? ` stroke="${INK}" stroke-width="${stroke}" stroke-linejoin="round"` : ""}>${el}</g>`;
const E = (cx, cy, rx, ry, extra = "") => `<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}"${extra}/>`;
const C = (cx, cy, r) => `<circle cx="${cx}" cy="${cy}" r="${r}"/>`;
const R = (x, y, w, h, rx, extra = "") => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${rx}"${extra}/>`;
const P = (d) => `<path d="${d}"/>`;
const mirror = (s) => `<g transform="translate(200,0) scale(-1,1)">${s}</g>`;

// ---- Face pieces ---------------------------------------------------------------------------
const HX = 100, HY = 80; // head centre (inside helmet centred at 100,74)

function eyes(spread = 13, y = HY - 2, size = 6) {
  let s = "";
  for (const k of [-1, 1]) {
    const x = HX + k * spread;
    s += flat(E(x, y, size * 0.8, size), INK);
    s += flat(C(x - size * 0.25, y - size * 0.4, size * 0.38), "#fff");
    s += flat(C(x + size * 0.28, y + size * 0.35, size * 0.17), "#fff");
  }
  return s;
}
const blush = (spread = 21, y = HY + 8) =>
  flat(E(HX - spread, y, 5, 3), "#f4a3ad") + flat(E(HX + spread, y, 5, 3), "#f4a3ad");
const smile = (y, w = 5) => `<path d="M${HX - w} ${y} Q${HX - w / 2} ${y + 4} ${HX} ${y} Q${HX + w / 2} ${y + 4} ${HX + w} ${y}" fill="none" stroke="${INK}" stroke-width="2.4" stroke-linecap="round"/>`;
const nose = (y, w = 4.5, fill = INK) => flat(E(HX, y, w, w * 0.7), fill);

// ---- Species heads (all fit inside the helmet circle r=56 at 100,74) ------------------------
const HEADS = {
  duck() {
    const white = "#f4f1ea";
    return part(P(`M${HX - 6} ${HY - 30} q-4 -12 4 -14 q2 6 2 12 q4 -12 10 -8 q-4 6 -6 11 z`), white, { dx: -2, dy: -2, stroke: 3 }) +
      part(E(HX, HY, 33, 31), white) +
      eyes(13, HY - 4) + blush(22, HY + 6) +
      part(P(`M${HX - 16} ${HY + 8} Q${HX} ${HY + 1} ${HX + 16} ${HY + 8} Q${HX + 15} ${HY + 18} ${HX} ${HY + 19} Q${HX - 15} ${HY + 18} ${HX - 16} ${HY + 8} z`), "#f59a45", { dx: -2, dy: -3, stroke: 3 }) +
      `<path d="M${HX - 12} ${HY + 12} Q${HX} ${HY + 15} ${HX + 12} ${HY + 12}" fill="none" stroke="${INK}" stroke-width="2" stroke-linecap="round"/>`;
  },
  mouse() {
    const grey = "#b9bac6";
    let s = "";
    for (const k of [-1, 1]) s += part(C(HX + k * 26, HY - 24, 15), grey, { stroke: 3.5 }) + flat(C(HX + k * 26, HY - 23, 9), "#f4a3ad");
    return s + part(E(HX, HY + 2, 32, 29), grey) + eyes(12, HY) + blush(20, HY + 10) +
      nose(HY + 9, 3.5, "#ef7a8f") + smile(HY + 13, 4) +
      `<g stroke="${INK}" stroke-width="1.6" stroke-linecap="round">` +
      [-1, 1].map((k) => `<line x1="${HX + k * 9}" y1="${HY + 10}" x2="${HX + k * 22}" y2="${HY + 7}"/><line x1="${HX + k * 9}" y1="${HY + 12}" x2="${HX + k * 22}" y2="${HY + 14}"/>`).join("") + "</g>";
  },
  dog() {
    const tan = "#dba66b", brown = "#7d4c2e";
    let s = part(E(HX, HY, 32, 30), tan);
    for (const k of [-1, 1])
      s += part(P(`M${HX + k * 24} ${HY - 22} Q${HX + k * 42} ${HY - 18} ${HX + k * 38} ${HY + 8} Q${HX + k * 34} ${HY + 14} ${HX + k * 27} ${HY + 4} Z`), brown, { dx: k * -2, dy: -3, stroke: 3.5 });
    return s + flat(E(HX - 13, HY - 3, 10, 9), brown) + part(E(HX, HY + 11, 15, 11), "#f6e4c8", { dx: -2, dy: -3, stroke: 3 }) +
      eyes(13, HY - 3) + nose(HY + 6, 5) + smile(HY + 12, 5) + blush(22, HY + 8);
  },
  cat() {
    const orange = "#f2a052";
    let s = "";
    for (const k of [-1, 1]) {
      s += part(P(`M${HX + k * 12} ${HY - 24} L${HX + k * 30} ${HY - 42} L${HX + k * 32} ${HY - 14} Z`), orange, { dx: k * -2, dy: 0, stroke: 3.5 });
      s += flat(P(`M${HX + k * 18} ${HY - 24} L${HX + k * 28} ${HY - 35} L${HX + k * 29} ${HY - 20} Z`), "#f4a3ad");
    }
    s += part(P(`M${HX - 34} ${HY} Q${HX - 34} ${HY - 28} ${HX} ${HY - 28} Q${HX + 34} ${HY - 28} ${HX + 34} ${HY} Q${HX + 38} ${HY + 14} ${HX + 26} ${HY + 22} Q${HX} ${HY + 32} ${HX - 26} ${HY + 22} Q${HX - 38} ${HY + 14} ${HX - 34} ${HY} Z`), orange);
    for (const dx of [-6, 0, 6]) s += flat(R(HX + dx - 1.5, HY - 26, 3, 9, 1.5), "#c76d2c");
    return s + part(E(HX, HY + 12, 14, 9), "#fbefe2", { dx: -2, dy: -2, stroke: 3 }) + eyes(14, HY - 2) +
      nose(HY + 8, 3, "#ef7a8f") + smile(HY + 12, 4) + blush(23, HY + 8);
  },
  bear() {
    const brown = "#93613b";
    let s = "";
    for (const k of [-1, 1]) s += part(C(HX + k * 24, HY - 24, 11), brown, { stroke: 3.5 }) + flat(C(HX + k * 24, HY - 23, 5.5), "#cf9f6e");
    return s + part(E(HX, HY + 1, 33, 30), brown) + part(E(HX, HY + 12, 15, 11), "#dcb68c", { dx: -2, dy: -3, stroke: 3 }) +
      eyes(14, HY - 4, 5.5) + nose(HY + 8, 5.5) + smile(HY + 14, 4) + blush(23, HY + 8);
  },
  raccoon() {
    const grey = "#9c9ca6";
    let s = "";
    for (const k of [-1, 1]) s += part(P(`M${HX + k * 12} ${HY - 24} L${HX + k * 27} ${HY - 40} L${HX + k * 31} ${HY - 14} Z`), grey, { dx: k * -2, dy: 0, stroke: 3.5 });
    s += part(E(HX, HY, 34, 30), grey);
    s += flat(P(`M${HX - 30} ${HY - 4} Q${HX - 16} ${HY - 14} ${HX - 3} ${HY - 4} Q${HX - 6} ${HY + 8} ${HX - 18} ${HY + 8} Q${HX - 28} ${HY + 6} ${HX - 30} ${HY - 4} Z`), "#2a2f45");
    s += mirror(flat(P(`M${HX - 30} ${HY - 4} Q${HX - 16} ${HY - 14} ${HX - 3} ${HY - 4} Q${HX - 6} ${HY + 8} ${HX - 18} ${HY + 8} Q${HX - 28} ${HY + 6} ${HX - 30} ${HY - 4} Z`), "#2a2f45"));
    s += flat(E(HX - 14, HY - 13, 8, 2.5), "#f3f3f1") + flat(E(HX + 14, HY - 13, 8, 2.5), "#f3f3f1");
    s += part(E(HX, HY + 14, 13, 9), "#f3f3f1", { dx: -2, dy: -2, stroke: 3 });
    // eyes on the mask get a pale ring so they still read
    for (const k of [-1, 1]) s += flat(C(HX + k * 15, HY - 1, 7.5), "#454b66");
    return s + eyes(15, HY - 1, 5.5) + nose(HY + 10, 4) + smile(HY + 15, 4);
  },
  monkey() {
    const brown = "#8a5a3b", face = "#f2cf9f";
    let s = "";
    for (const k of [-1, 1]) s += part(C(HX + k * 33, HY + 2, 11), brown, { stroke: 3.5 }) + flat(C(HX + k * 33, HY + 2, 6), face);
    s += part(E(HX, HY, 31, 30), brown);
    s += part(P(`M${HX} ${HY - 10} Q${HX - 8} ${HY - 20} ${HX - 18} ${HY - 14} Q${HX - 28} ${HY - 4} ${HX - 20} ${HY + 8} Q${HX - 22} ${HY + 24} ${HX} ${HY + 25} Q${HX + 22} ${HY + 24} ${HX + 20} ${HY + 8} Q${HX + 28} ${HY - 4} ${HX + 18} ${HY - 14} Q${HX + 8} ${HY - 20} ${HX} ${HY - 10} Z`), face, { dx: -2, dy: -3, stroke: 3 });
    return s + eyes(10, HY - 3, 5.5) + flat(C(HX - 3, HY + 9, 1.6), "#5a3420") + flat(C(HX + 3, HY + 9, 1.6), "#5a3420") +
      smile(HY + 15, 6) + blush(16, HY + 10);
  },
  penguin() {
    const dark = "#2a3048", white = "#f4f7f9";
    return part(E(HX, HY, 32, 31), dark, { shadow: "#1f2338" }) +
      part(P(`M${HX} ${HY - 8} Q${HX - 8} ${HY - 20} ${HX - 18} ${HY - 14} Q${HX - 28} ${HY - 4} ${HX - 22} ${HY + 10} Q${HX - 16} ${HY + 26} ${HX} ${HY + 27} Q${HX + 16} ${HY + 26} ${HX + 22} ${HY + 10} Q${HX + 28} ${HY - 4} ${HX + 18} ${HY - 14} Q${HX + 8} ${HY - 20} ${HX} ${HY - 8} Z`), white, { dx: -2, dy: -3, stroke: 0, outline: false }) +
      eyes(10, HY - 1, 5.5) + blush(17, HY + 9) +
      part(P(`M${HX - 7} ${HY + 7} Q${HX} ${HY + 3} ${HX + 7} ${HY + 7} L${HX} ${HY + 15} Z`), "#f59a45", { dx: -1, dy: -2, stroke: 2.5 });
  },
};

// ---- Suit + helmet ---------------------------------------------------------------------------
function pilot(animal) {
  uid = 0;
  const trim = TRIM[animal];
  const suit = "#f3f0ea", grey = "#cbd1dc";
  let s = "";
  // backpack peeking out behind the body
  s += part(R(52, 118, 96, 78, 18), grey, { dx: -3, dy: -3 });
  // legs + moon boots
  for (const k of [-1, 1]) {
    s += part(R(100 + k * 16 - 12, 192, 24, 40, 10), suit, { dx: -3, dy: -3 });
    s += part(E(100 + k * 17, 238, 18, 11), grey, { dx: -3, dy: -3 });
  }
  // body
  s += part(R(60, 120, 80, 92, 32), suit, { dx: -6, dy: -5 });
  s += part(R(61, 180, 78, 10, 3), trim, { dx: 0, dy: -2, stroke: 3 });
  s += part(R(83, 142, 34, 22, 5), "#36405f", { dx: 0, dy: 0, stroke: 3 });
  ["#ef6a5a", "#ffc56b", "#4fb8a8"].forEach((c, i) => (s += flat(C(91 + i * 9, 153, 3), c)));
  s += part(C(127, 143, 6), trim, { dx: -1, dy: -1, stroke: 2.5 });
  // arms + mitts
  const arm = `${R(-10, 0, 20, 42, 10)}`;
  for (const k of [-1, 1]) {
    const g = (inner) => `<g transform="translate(${100 + k * 37},132) rotate(${k * -16})">${inner}</g>`;
    s += g(part(arm, suit, { dx: -3, dy: -3 }));
    s += g(part(E(0, 46, 11, 12), trim, { dx: -2, dy: -2, stroke: 3.5 }));
  }
  // helmet: glass back, head, glass front (rim + shines), collar ring
  s += flat(C(100, 74, 56), "#bfe6ee") .replace("<g ", '<g opacity="0.22" ');
  s += HEADS[animal]();
  s += `<circle cx="100" cy="74" r="56" fill="none" stroke="#e8fbff" stroke-width="3" opacity="0.55"/>`;
  s += `<circle cx="100" cy="74" r="58" fill="none" stroke="${INK}" stroke-width="${W}"/>`;
  s += `<path d="M58 66 Q62 34 92 24" fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round" opacity="0.85"/>`;
  s += flat(C(104, 22, 3.2), "#fff");
  s += part(R(62, 121, 76, 15, 7.5), "#aeb9cc", { dx: -3, dy: -3 }); // neck ring band
  s += flat(R(70, 125, 18, 3, 1.5), "#e4ebf5");
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 260" width="200" height="260">${s}</svg>`;
}

const out = __dirname;
for (const a of Object.keys(HEADS)) fs.writeFileSync(path.join(out, a + ".svg"), pilot(a));
console.log("wrote", Object.keys(HEADS).length, "pilots to", out);
