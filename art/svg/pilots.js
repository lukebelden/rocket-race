// Rocket Race - 2D "sticker" astronaut pilots as SVG.
//   node art/svg/pilots.js          -> art/svg/<animal>.svg (viewBox 200x260)
// Cartoon-sticker look with depth: gradient fills, a crescent shadow per shape, gloss
// highlights, thick ink outlines. The head fills the bubble helmet and sits on a neck
// that goes down into the suit collar.
const fs = require("fs");
const path = require("path");

const INK = "#1e2238";
const W = 4; // outline width (suit); heads use thinner lines because they are scaled up
const TRIM = { duck: "#f0893c", mouse: "#4fb8a8", dog: "#5aa9e6", cat: "#9a73d6", bear: "#e5683b",
  raccoon: "#7ed6a0", monkey: "#ffc56b", penguin: "#ef6a5a" };

// ---- colour helpers --------------------------------------------------------------------------
const rgb = (h) => { const n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; };
const hex = (a) => "#" + a.map((v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, "0")).join("");
const lighten = (h, k = 0.22) => hex(rgb(h).map((v) => v + (255 - v) * k));
const shade = (h, k = 0.8) => { const [r, g, b] = rgb(h); return hex([r * k + 70 * (1 - k) * 0.55, g * k + 80 * (1 - k) * 0.55, b * k + 140 * (1 - k) * 0.55]); };

let uid = 0, defs = "";
function grad(base) { // soft top-left light to base colour
  const id = "g" + uid++;
  defs += `<linearGradient id="${id}" x1="0.2" y1="0" x2="0.7" y2="1"><stop offset="0" stop-color="${lighten(base)}"/><stop offset="0.65" stop-color="${base}"/></linearGradient>`;
  return `url(#${id})`;
}

// A shape: shadow tone underneath, gradient fill shifted up-left (leaves a crescent of shadow
// on the lower right), optional gloss, ink outline. `el` is an SVG element without fill.
function part(el, base, { shadow = shade(base), dx = -5, dy = -5, stroke = W, outline = true, gloss = 0 } = {}) {
  const id = "c" + uid++;
  defs += `<clipPath id="${id}">${el}</clipPath>`;
  let s = `<g fill="${shadow}">${el}</g>` +
    `<g clip-path="url(#${id})"><g fill="${grad(base)}" transform="translate(${dx},${dy})">${el}</g>`;
  if (gloss) s += `<g fill="#fff" opacity="${gloss}" transform="translate(${dx * 2.2},${dy * 2.6}) ">${el}</g>`
    .replace("<g fill=\"#fff\"", `<g fill="#fff"`);
  s += "</g>";
  if (outline) s += `<g fill="none" stroke="${INK}" stroke-width="${stroke}" stroke-linejoin="round">${el}</g>`;
  return s;
}
const flat = (el, fill, extra = "") => `<g fill="${fill}"${extra}>${el}</g>`;
const line = (d, w = 2, color = INK, extra = "") =>
  `<path d="${d}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"${extra}/>`;
const E = (cx, cy, rx, ry, extra = "") => `<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}"${extra}/>`;
const C = (cx, cy, r) => `<circle cx="${cx}" cy="${cy}" r="${r}"/>`;
const R = (x, y, w, h, rx, extra = "") => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${rx}"${extra}/>`;
const P = (d) => `<path d="${d}"/>`;
const both = (f) => f(-1) + f(1);
// Soft gloss spot (no outline).
const shine = (cx, cy, rx, ry, op = 0.55, rot = -30) =>
  `<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="#fff" opacity="${op}" transform="rotate(${rot} ${cx} ${cy})"/>`;

// ---- face kit (head space: centre 100,80, head radius ~30, drawn then scaled up) -----------
const X = 100, Y = 80, HS = 3; // head stroke
const hp = (o = {}) => Object.assign({ stroke: HS, dx: -4, dy: -4 }, o);

function eyes(spread, y, size, iris, { slit = false, lid = false } = {}) {
  return both((k) => {
    const x = X + k * spread;
    let s = flat(E(x, y, size * 0.82, size), INK);
    s += flat(E(x, y + size * 0.18, size * 0.6, size * 0.72), iris);
    s += flat(E(x, y + size * 0.3, size * 0.6, size * 0.42), lighten(iris, 0.3), ' opacity="0.6"');
    s += slit ? flat(E(x, y + size * 0.15, size * 0.16, size * 0.62), INK) : flat(E(x, y + size * 0.2, size * 0.34, size * 0.42), INK);
    s += flat(C(x - size * 0.28, y - size * 0.38, size * 0.33), "#fff");
    s += flat(C(x + size * 0.3, y + size * 0.42, size * 0.14), "#fff");
    if (lid) s += line(`M${x - size * 0.9} ${y - size * 0.95} Q${x} ${y - size * 1.35} ${x + size * 0.9} ${y - size * 0.95}`, 1.6);
    return s;
  });
}
const blush = (spread, y, rx = 4.5) => both((k) => flat(E(X + k * spread, y, rx, rx * 0.55), "#f49aa8", ' opacity="0.8"'));
const whiskers = (y, from = 9, len = 15) => both((k) =>
  line(`M${X + k * from} ${y - 1} L${X + k * (from + len)} ${y - 4}`, 1.1) + line(`M${X + k * from} ${y + 2} L${X + k * (from + len)} ${y + 3}`, 1.1));
// Tuft of fur: little zigzag along an arc.
function tuft(cx, cy, w, h, n = 3) {
  let d = `M${cx - w / 2} ${cy}`;
  for (let i = 0; i < n; i++) {
    const x0 = cx - w / 2 + (w / n) * i;
    d += ` Q${x0 + w / n * 0.2} ${cy - h} ${x0 + w / n * 0.6} ${cy - h * 0.9} Q${x0 + w / n * 0.7} ${cy - h * 0.4} ${x0 + w / n} ${cy}`;
  }
  return d + " Z";
}
// Head outline with fluffy cheeks (zigzag on the lower sides).
function fluffyHead(rx, ry, fluff = 4) {
  const pts = [];
  for (let i = 0; i <= 48; i++) {
    const a = (i / 48) * Math.PI * 2;
    const lower = Math.sin(a) > 0.05 && Math.abs(Math.cos(a)) > 0.45; // cheek zone
    const r = lower && i % 2 ? 1 + fluff / rx : 1;
    pts.push([X + Math.cos(a) * rx * r, Y + Math.sin(a) * ry * r]);
  }
  return P("M" + pts.map((p) => p.map((v) => v.toFixed(1)).join(" ")).join(" L") + " Z");
}

// ---- species ---------------------------------------------------------------------------------
const HEADS = {
  duck: { fur: "#f4f1ea", draw() {
    const w = "#f6f3ec", bill = "#f59a3c";
    // three curled head feathers
    let s = [[-6, -0.5], [0, 0], [6, 0.5]].map(([dx, lean]) => part(P(
      `M${X + dx - 3} ${Y - 26} C${X + dx - 4 + lean * 6} ${Y - 34} ${X + dx + lean * 10} ${Y - 40} ${X + dx + 2 + lean * 8} ${Y - 37} C${X + dx + 4} ${Y - 33} ${X + dx + 3} ${Y - 30} ${X + dx + 3} ${Y - 26} Z`), w, hp({ dx: -1, dy: -1, stroke: 2.4 }))).join("");
    s += part(P(`M${X - 30} ${Y + 2} C${X - 30} ${Y - 22} ${X - 16} ${Y - 30} ${X} ${Y - 30} C${X + 16} ${Y - 30} ${X + 30} ${Y - 22} ${X + 30} ${Y + 2} C${X + 30} ${Y + 22} ${X + 16} ${Y + 29} ${X} ${Y + 29} C${X - 16} ${Y + 29} ${X - 30} ${Y + 22} ${X - 30} ${Y + 2} Z`), w, hp({ shadow: "#c9cbd8" }));
    s += line(`M${X - 26} ${Y + 6} q3 3 6 1 M${X + 20} ${Y + 7} q3 2 6 -1`, 1.2, "#b9bccb");
    s += eyes(12, Y - 5, 6.4, "#3a7fa6") + blush(19, Y + 7);
    // bill: lower mandible, upper mandible with nostrils
    s += part(P(`M${X - 11} ${Y + 14} Q${X} ${Y + 22} ${X + 11} ${Y + 14} Z`), "#e8812f", hp({ dx: 0, dy: -1, shadow: "#c9682a" }));
    s += part(P(`M${X - 9} ${Y + 4} C${X - 6} ${Y + 1} ${X + 6} ${Y + 1} ${X + 9} ${Y + 4} C${X + 17} ${Y + 6} ${X + 19} ${Y + 15} ${X + 10} ${Y + 16} C${X + 4} ${Y + 17} ${X - 4} ${Y + 17} ${X - 10} ${Y + 16} C${X - 19} ${Y + 15} ${X - 17} ${Y + 6} ${X - 9} ${Y + 4} Z`), bill, hp({ dx: -1, dy: -2, shadow: "#e07e2e" }));
    s += flat(E(X - 4, Y + 7, 1.5, 0.9) + E(X + 4, Y + 7, 1.5, 0.9), "#a55a1e") + shine(X - 9, Y + 8, 4.5, 1.5, 0.7, -15);
    return s;
  } },
  mouse: { fur: "#b9bac6", draw() {
    const g = "#bcbdc9";
    let s = both((k) => part(C(X + k * 25, Y - 22, 17), g, hp()) +
      flat(C(X + k * 25, Y - 21, 11.5), "#f3a4b2") + flat(E(X + k * 23, Y - 25, 4, 6), "#f8c3cc", ' opacity="0.7"'));
    s += part(P(`M${X} ${Y - 26} C${X + 22} ${Y - 26} ${X + 30} ${Y - 10} ${X + 28} ${Y + 4} C${X + 26} ${Y + 18} ${X + 14} ${Y + 28} ${X} ${Y + 28} C${X - 14} ${Y + 28} ${X - 26} ${Y + 18} ${X - 28} ${Y + 4} C${X - 30} ${Y - 10} ${X - 22} ${Y - 26} ${X} ${Y - 26} Z`), g, hp());
    s += part(P(tuft(X, Y - 24, 10, 6, 2).slice(0)), g, hp({ dx: -1, dy: -1, stroke: 2 }));
    s += part(E(X, Y + 13, 12, 9), "#e6e3ea", hp({ dx: -2, dy: -2 }));
    s += eyes(11, Y - 3, 6, "#2b2f45");
    s += part(E(X, Y + 8, 4, 3), "#ef7a8f", hp({ dx: -1, dy: -1, stroke: 1.6 })) + line(`M${X} ${Y + 11} L${X} ${Y + 14} M${X - 4} ${Y + 15} Q${X} ${Y + 18} ${X + 4} ${Y + 15}`, 1.5);
    s += part(R(X - 3, Y + 16, 6, 5, 1), "#fff", hp({ dx: 0, dy: 0, stroke: 1.4 })) + line(`M${X} ${Y + 16} L${X} ${Y + 21}`, 1);
    s += whiskers(Y + 11, 10, 16) + blush(18, Y + 7);
    return s;
  } },
  dog: { fur: "#d39a5c", draw() {
    const tan = "#d8a062", brown = "#7a4a2c", white = "#f7ecdc";
    let s = part(P(`M${X - 28} ${Y} C${X - 30} ${Y - 22} ${X - 14} ${Y - 29} ${X} ${Y - 29} C${X + 14} ${Y - 29} ${X + 30} ${Y - 22} ${X + 28} ${Y} C${X + 28} ${Y + 20} ${X + 16} ${Y + 28} ${X} ${Y + 28} C${X - 16} ${Y + 28} ${X - 28} ${Y + 20} ${X - 28} ${Y} Z`), tan, hp());
    s += flat(P(`M${X - 4} ${Y - 29} Q${X} ${Y - 31} ${X + 4} ${Y - 29} L${X + 6} ${Y - 6} L${X - 6} ${Y - 6} Z`), white); // blaze
    s += part(P(`M${X - 16} ${Y + 10} C${X - 16} ${Y - 2} ${X + 16} ${Y - 2} ${X + 16} ${Y + 10} C${X + 16} ${Y + 24} ${X - 16} ${Y + 24} ${X - 16} ${Y + 10} Z`), white, hp({ dx: -2, dy: -2 }));
    s += both((k) => part(P(`M${X + k * 20} ${Y - 24} C${X + k * 38} ${Y - 26} ${X + k * 42} ${Y - 4} ${X + k * 38} ${Y + 14} C${X + k * 36} ${Y + 22} ${X + k * 28} ${Y + 20} ${X + k * 26} ${Y + 8} C${X + k * 24} ${Y - 4} ${X + k * 22} ${Y - 14} ${X + k * 20} ${Y - 24} Z`), brown, hp({ dx: k * -2, dy: -3 })) +
      line(`M${X + k * 26} ${Y - 16} Q${X + k * 32} ${Y - 2} ${X + k * 31} ${Y + 12}`, 1.4, "#5a341e"));
    s += both((k) => flat(E(X + k * 10, Y - 15, 3, 2), "#f0c58e")); // eyebrow dots
    s += eyes(12, Y - 4, 6.2, "#7a4a22");
    s += part(P(`M${X - 6} ${Y + 4} Q${X} ${Y + 1} ${X + 6} ${Y + 4} Q${X + 6} ${Y + 9} ${X} ${Y + 11} Q${X - 6} ${Y + 9} ${X - 6} ${Y + 4} Z`), "#2a2230", hp({ dx: -1, dy: -1, stroke: 1.6 })) + shine(X - 2, Y + 4, 2.5, 1.2, 0.8, 0);
    s += line(`M${X} ${Y + 11} L${X} ${Y + 15} M${X - 6} ${Y + 15} Q${X - 3} ${Y + 18} ${X} ${Y + 15} Q${X + 3} ${Y + 18} ${X + 6} ${Y + 15}`, 1.6);
    s += part(P(`M${X - 3} ${Y + 17} Q${X} ${Y + 24} ${X + 3} ${Y + 17} Z`), "#ef7a8f", hp({ dx: 0, dy: -1, stroke: 1.3 }));
    s += blush(19, Y + 8);
    return s;
  } },
  cat: { fur: "#f0a050", draw() {
    const o = "#f2a252", stripe = "#c76a26", white = "#fbf0e4";
    let s = both((k) => part(P(`M${X + k * 10} ${Y - 22} L${X + k * 26} ${Y - 40} Q${X + k * 30} ${Y - 40} ${X + k * 31} ${Y - 35} L${X + k * 30} ${Y - 10} Z`), o, hp({ dx: k * -2, dy: 0 })) +
      flat(P(`M${X + k * 15} ${Y - 21} L${X + k * 25} ${Y - 33} L${X + k * 27} ${Y - 16} Z`), "#f3a4b2") +
      line(`M${X + k * 19} ${Y - 21} l${k * 3} -6 M${X + k * 22} ${Y - 20} l${k * 2} -7`, 1, "#fff"));
    s += part(fluffyHead(32, 27, 4), o, hp());
    s += line(`M${X - 7} ${Y - 26} L${X - 6} ${Y - 18} M${X} ${Y - 27} L${X} ${Y - 17} M${X + 7} ${Y - 26} L${X + 6} ${Y - 18}`, 2.6, stripe); // tabby M
    s += both((k) => line(`M${X + k * 31} ${Y - 2} L${X + k * 22} ${Y} M${X + k * 31} ${Y + 5} L${X + k * 23} ${Y + 6}`, 2.2, stripe));
    s += part(P(`M${X} ${Y + 3} C${X - 6} ${Y + 1} ${X - 15} ${Y + 4} ${X - 15} ${Y + 12} C${X - 15} ${Y + 20} ${X - 4} ${Y + 21} ${X} ${Y + 17} C${X + 4} ${Y + 21} ${X + 15} ${Y + 20} ${X + 15} ${Y + 12} C${X + 15} ${Y + 4} ${X + 6} ${Y + 1} ${X} ${Y + 3} Z`), white, hp({ dx: -2, dy: -2 }));
    s += eyes(13, Y - 4, 6.6, "#69b34c", { slit: true });
    s += part(P(`M${X - 4} ${Y + 7} L${X + 4} ${Y + 7} L${X} ${Y + 11} Z`), "#ef7a8f", hp({ dx: 0, dy: -1, stroke: 1.5 }));
    s += line(`M${X} ${Y + 11} L${X} ${Y + 13} M${X - 5} ${Y + 14} Q${X - 2.5} ${Y + 17} ${X} ${Y + 13} Q${X + 2.5} ${Y + 17} ${X + 5} ${Y + 14}`, 1.5);
    s += both((k) => [0, 1, 2].map((i) => flat(C(X + k * (6 + i * 2.5), Y + 12 + (i % 2) * 2.5, 0.8), "#c9a58a")).join(""));
    s += whiskers(Y + 12, 13, 18) + blush(21, Y + 7);
    return s;
  } },
  bear: { fur: "#8e5d38", draw() {
    const b = "#91603a", m = "#d9b386";
    let s = both((k) => part(C(X + k * 23, Y - 24, 11), b, hp()) + flat(C(X + k * 23, Y - 23, 6), "#c99a6a"));
    s += part(P(`M${X - 31} ${Y + 2} C${X - 32} ${Y - 20} ${X - 16} ${Y - 29} ${X} ${Y - 29} C${X + 16} ${Y - 29} ${X + 32} ${Y - 20} ${X + 31} ${Y + 2} C${X + 30} ${Y + 22} ${X + 16} ${Y + 29} ${X} ${Y + 29} C${X - 16} ${Y + 29} ${X - 30} ${Y + 22} ${X - 31} ${Y + 2} Z`), b, hp());
    s += part(P(tuft(X, Y - 27, 12, 6, 3)), b, hp({ dx: -1, dy: -1, stroke: 2 }));
    s += part(E(X, Y + 12, 15, 11.5), m, hp({ dx: -2, dy: -3 }));
    s += eyes(13, Y - 5, 5.8, "#5a3a22");
    s += both((k) => line(`M${X + k * 9} ${Y - 14} Q${X + k * 13} ${Y - 16} ${X + k * 17} ${Y - 14}`, 1.6, "#5e3b22"));
    s += part(E(X, Y + 6, 6.5, 4.5), "#2a2230", hp({ dx: -1, dy: -1, stroke: 1.6 })) + shine(X - 2.5, Y + 4.5, 2.6, 1.2, 0.8, 0);
    s += line(`M${X} ${Y + 10} L${X} ${Y + 14} M${X - 6} ${Y + 14} Q${X - 3} ${Y + 18} ${X} ${Y + 14} Q${X + 3} ${Y + 18} ${X + 6} ${Y + 14}`, 1.6);
    s += blush(21, Y + 8);
    return s;
  } },
  raccoon: { fur: "#9a9aa4", draw() {
    const g = "#9d9da8", dark = "#2a2f45", w = "#f3f3f1";
    let s = both((k) => part(P(`M${X + k * 10} ${Y - 22} L${X + k * 24} ${Y - 39} Q${X + k * 29} ${Y - 40} ${X + k * 30} ${Y - 34} L${X + k * 30} ${Y - 12} Z`), w, hp({ dx: 0, dy: 0 })) +
      flat(P(`M${X + k * 14} ${Y - 21} L${X + k * 24} ${Y - 34} L${X + k * 27} ${Y - 16} Z`), "#3d4258"));
    s += part(fluffyHead(33, 27, 5), g, hp());
    s += flat(P(`M${X - 3} ${Y - 27} L${X + 3} ${Y - 27} L${X + 4} ${Y + 4} L${X - 4} ${Y + 4} Z`), "#6f7080"); // nose stripe
    s += both((k) => flat(E(X + k * 14, Y - 14, 8, 3), w));
    const mask = (k) => `M${X + k * 2} ${Y - 5} C${X + k * 8} ${Y - 11} ${X + k * 22} ${Y - 12} ${X + k * 31} ${Y - 3} C${X + k * 30} ${Y + 6} ${X + k * 22} ${Y + 9} ${X + k * 14} ${Y + 7} C${X + k * 8} ${Y + 5} ${X + k * 4} ${Y + 1} ${X + k * 2} ${Y - 5} Z`;
    s += both((k) => flat(P(mask(k)), dark));
    s += part(P(`M${X - 13} ${Y + 12} C${X - 13} ${Y + 3} ${X + 13} ${Y + 3} ${X + 13} ${Y + 12} C${X + 13} ${Y + 22} ${X - 13} ${Y + 22} ${X - 13} ${Y + 12} Z`), w, hp({ dx: -2, dy: -2 }));
    s += eyes(14, Y - 2, 5.8, "#4a3a2a");
    s += part(E(X, Y + 7, 5, 3.4), INK, hp({ dx: -1, dy: -1, stroke: 1.4 })) + shine(X - 2, Y + 6, 2, 1, 0.8, 0);
    s += line(`M${X} ${Y + 10} L${X} ${Y + 13} M${X - 5} ${Y + 14} Q${X - 2.5} ${Y + 17} ${X} ${Y + 13} Q${X + 2.5} ${Y + 17} ${X + 5} ${Y + 14}`, 1.5);
    s += whiskers(Y + 12, 11, 14);
    return s;
  } },
  monkey: { fur: "#86573a", draw() {
    const b = "#8a5a3b", f = "#f0cc9c";
    let s = both((k) => part(E(X + k * 31, Y + 1, 10, 12), b, hp()) + flat(E(X + k * 31, Y + 1, 5.5, 7.5), f));
    s += part(P(`M${X - 28} ${Y} C${X - 29} ${Y - 20} ${X - 15} ${Y - 29} ${X} ${Y - 29} C${X + 15} ${Y - 29} ${X + 29} ${Y - 20} ${X + 28} ${Y} C${X + 28} ${Y + 20} ${X + 16} ${Y + 28} ${X} ${Y + 28} C${X - 16} ${Y + 28} ${X - 28} ${Y + 20} ${X - 28} ${Y} Z`), b, hp());
    s += part(P(tuft(X + 2, Y - 27, 14, 8, 3)), b, hp({ dx: -1, dy: -1, stroke: 2 }));
    s += part(P(`M${X} ${Y - 11} C${X - 6} ${Y - 21} ${X - 23} ${Y - 18} ${X - 22} ${Y - 4} C${X - 25} ${Y + 6} ${X - 22} ${Y + 24} ${X} ${Y + 25} C${X + 22} ${Y + 24} ${X + 25} ${Y + 6} ${X + 22} ${Y - 4} C${X + 23} ${Y - 18} ${X + 6} ${Y - 21} ${X} ${Y - 11} Z`), f, hp({ dx: -2, dy: -3 }));
    s += eyes(10, Y - 4, 5.6, "#6a4224");
    s += both((k) => line(`M${X + k * 5} ${Y - 12} Q${X + k * 10} ${Y - 15} ${X + k * 15} ${Y - 12}`, 1.6, "#6a4224"));
    s += flat(E(X - 3, Y + 8, 1.6, 1.2) + E(X + 3, Y + 8, 1.6, 1.2), "#5a3420");
    s += part(P(`M${X - 9} ${Y + 13} Q${X} ${Y + 23} ${X + 9} ${Y + 13} Q${X} ${Y + 16} ${X - 9} ${Y + 13} Z`), "#7a3a32", hp({ dx: 0, dy: -1, stroke: 1.6 }));
    s += blush(15, Y + 9, 4);
    return s;
  } },
  penguin: { fur: "#2a3048", draw() {
    const d = "#2c3250", w = "#f4f7f9";
    let s = part(P(`M${X - 30} ${Y + 2} C${X - 31} ${Y - 20} ${X - 16} ${Y - 30} ${X} ${Y - 30} C${X + 16} ${Y - 30} ${X + 31} ${Y - 20} ${X + 30} ${Y + 2} C${X + 30} ${Y + 22} ${X + 16} ${Y + 29} ${X} ${Y + 29} C${X - 16} ${Y + 29} ${X - 30} ${Y + 22} ${X - 30} ${Y + 2} Z`), d, hp({ shadow: "#1d2136" }));
    s += part(P(tuft(X, Y - 28, 8, 7, 2)), d, hp({ dx: -1, dy: -1, stroke: 2, shadow: "#1d2136" }));
    s += part(P(`M${X} ${Y - 9} C${X - 6} ${Y - 21} ${X - 24} ${Y - 18} ${X - 23} ${Y - 2} C${X - 24} ${Y + 12} ${X - 14} ${Y + 25} ${X} ${Y + 26} C${X + 14} ${Y + 25} ${X + 24} ${Y + 12} ${X + 23} ${Y - 2} C${X + 24} ${Y - 18} ${X + 6} ${Y - 21} ${X} ${Y - 9} Z`), w, hp({ dx: -2, dy: -3, stroke: 0, outline: false, shadow: "#c9d3e2" }));
    s += both((k) => flat(E(X + k * 27, Y + 10, 3, 7, ` transform="rotate(${k * -20} ${X + k * 27} ${Y + 10})"`), "#f6b73c")); // cheek patches
    s += eyes(10, Y - 2, 5.8, "#2b2f45");
    s += part(P(`M${X - 7} ${Y + 10} Q${X} ${Y + 16} ${X + 7} ${Y + 10} L${X} ${Y + 18} Z`), "#d9772b", hp({ dx: 0, dy: -1, stroke: 1.8 }));
    s += part(P(`M${X - 8} ${Y + 9} Q${X} ${Y + 3} ${X + 8} ${Y + 9} Q${X} ${Y + 13} ${X - 8} ${Y + 9} Z`), "#f59a3c", hp({ dx: -1, dy: -2, stroke: 1.8 }));
    s += blush(16, Y + 9, 4);
    return s;
  } },
};

// ---- suit + helmet ---------------------------------------------------------------------------
const HEAD_SCALE = 1.32; // head fills the bubble; chin rests in the collar
function pilot(animal) {
  uid = 0; defs = "";
  const trim = TRIM[animal], spec = HEADS[animal];
  const suit = "#f3f0ea", grey = "#c8cfdb", seam = ' opacity="0.35"';
  let s = "";
  // life-support pack behind the body
  s += part(R(50, 116, 100, 80, 18), grey, { dx: -3, dy: -3 });
  s += both((k) => part(R(100 + k * 44 - 4, 126, 8, 22, 4), "#9aa6b8", { dx: -1, dy: -1, stroke: 3 }));
  // legs with knee pads, moon boots with treads
  s += both((k) => {
    const x = 100 + k * 16;
    return part(R(x - 13, 190, 26, 42, 11), suit, { dx: -3, dy: -3 }) +
      part(R(x - 9, 206, 18, 10, 5), grey, { dx: -1, dy: -1, stroke: 2.5 }) +
      part(P(`M${x - 18} 242 C${x - 19} 228 ${x - 12} 226 ${x} 226 C${x + 12} 226 ${x + 20} 230 ${x + 19} 242 Z`), grey, { dx: -3, dy: -3 }) +
      part(R(x - 19, 240, 38, 7, 3.5), "#4a5578", { dx: 0, dy: -1, stroke: 3 });
  });
  // body: padded torso with seams, belt, chest unit, patch
  s += part(P("M64 140 C64 124 78 118 100 118 C122 118 136 124 136 140 L140 186 C141 206 124 214 100 214 C76 214 59 206 60 186 Z"), suit, { dx: -6, dy: -5 });
  s += line("M100 168 L100 214", 1.6, INK, seam) + line("M70 150 Q86 156 84 176 M130 150 Q114 156 116 176", 1.6, INK, seam);
  s += part(R(61, 182, 78, 11, 4), trim, { dx: 0, dy: -2, stroke: 3 }) + part(R(93, 181, 14, 13, 3), "#d7dde8", { dx: -1, dy: -1, stroke: 2.5 });
  s += part(R(82, 140, 36, 24, 5), "#36405f", { dx: 0, dy: 0, stroke: 3 });
  ["#ef6a5a", "#ffc56b", "#4fb8a8"].forEach((c, i) => (s += flat(C(91 + i * 9, 149, 3.2), c) + flat(C(90.2 + i * 9, 148, 1), "#fff")));
  s += flat(R(87, 156, 26, 3, 1.5), "#5a6690");
  s += part(C(128, 142, 6.5), trim, { dx: -1, dy: -1, stroke: 2.5 }) + flat(C(128, 142, 2.5), "#fff", ' opacity="0.8"');
  // arms: sleeves with cuffs, mitts with thumbs
  for (const k of [-1, 1]) {
    const g = (inner) => `<g transform="translate(${100 + k * 36},130) rotate(${k * -14})">${inner}</g>`;
    s += g(part(R(-10.5, 0, 21, 44, 10.5), suit, { dx: -3, dy: -3 }) + line(`M-7 18 Q0 21 7 18`, 1.6, INK, seam) +
      part(R(-11.5, 36, 23, 8, 4), grey, { dx: -1, dy: -1, stroke: 3 }) +
      part(E(k * -7, 49, 4.5, 6), trim, { dx: -1, dy: -1, stroke: 3 }) +
      part(E(0, 52, 11, 11.5), trim, { dx: -2, dy: -2, stroke: 3.5 }) + line(`M-3 57 L-3 61 M3 57 L3 61`, 1.4, INK, seam));
  }
  // helmet back glass, neck, head, front glass, collar
  defs += `<radialGradient id="glass" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#e8fbff" stop-opacity="0.35"/><stop offset="1" stop-color="#7fb4c9" stop-opacity="0.28"/></radialGradient>`;
  s += `<circle cx="100" cy="72" r="58" fill="url(#glass)"/>`;
  s += part(R(86, 100, 28, 26, 10), spec.fur, { dx: -2, dy: -2 });
  s += `<g transform="translate(100,${80}) scale(${HEAD_SCALE}) translate(-100,-80)">${spec.draw()}</g>`;
  s += `<circle cx="100" cy="72" r="56" fill="none" stroke="#e8fbff" stroke-width="2.5" opacity="0.5"/>`;
  s += `<circle cx="100" cy="72" r="58" fill="none" stroke="${INK}" stroke-width="${W}"/>`;
  s += line("M54 70 Q56 34 88 20", 6, "#fff", ' opacity="0.85"') + flat(C(98, 18, 3.2), "#fff");
  s += line("M150 90 Q146 108 132 118", 3, "#fff", ' opacity="0.45"');
  s += part(R(60, 119, 80, 16, 8), "#aeb9cc", { dx: -3, dy: -3 }) + flat(R(68, 123, 22, 3.5, 1.75), "#e8eef7");
  s += both((k) => flat(C(100 + k * 30, 127, 2.6), "#ffc56b"));
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 260" width="200" height="260"><defs>${defs}</defs>${s}</svg>`;
}

if (require.main === module) {
  for (const a of Object.keys(HEADS)) fs.writeFileSync(path.join(__dirname, a + ".svg"), pilot(a));
  console.log("wrote", Object.keys(HEADS).length, "pilots");
}
// Shared drawing kit for other characters (duck.js etc).
module.exports = { INK, part, flat, line, E, C, R, P, shine, lighten, shade,
  resetDefs: () => { uid = 0; defs = ""; }, takeDefs: () => defs, addDef: (d) => { defs += d; } };
