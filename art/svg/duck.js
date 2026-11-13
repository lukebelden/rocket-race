// Rocket Race - the new astronaut duck (sticker style, full duck body).
//   node art/svg/duck.js   -> art/svg/duck_astro.svg (viewBox 200x220)
// Round little duck in a white flight suit: wings for arms (one waving), webbed feet,
// head turned a little to the right inside an open-visor helmet with ear pods + antenna.
const fs = require("fs");
const path = require("path");
const K = require("./pilots.js");
const { INK, part, flat, line, E, C, R, P, shine } = K;

const WHITE = "#f7f6f2", FEATHER_SH = "#cfd3e2";
const SUIT = "#f2f4f9", BLUE = "#4f9fe0", NAVY = "#2c3a6b";
const ORANGE = "#f7a23b", ORANGE_D = "#e07e2e", IRIS = "#2fa596";
const o = (x = {}) => Object.assign({ stroke: 4, dx: -4, dy: -4 }, x);

function duck() {
  K.resetDefs();
  let s = "";

  // tail feathers (behind), far ear pod + antenna (behind the helmet shell)
  s += part(P("M68 178 C52 178 44 168 42 156 C50 162 56 160 60 156 C58 164 64 168 72 166 Z"), WHITE, o({ shadow: FEATHER_SH, dx: -2, dy: -2 }));
  s += part(C(157, 82, 10), "#c9d0de", o({ dx: -2, dy: -2 }));
  s += line("M86 30 Q80 18 74 10", 3.5) + part(C(73, 9, 5.5), ORANGE, o({ dx: -1, dy: -1, stroke: 3 })) + shine(71, 7, 2, 1.2, 0.9, 0);

  // body: round suit
  s += part(P("M68 142 C64 120 138 114 140 138 C148 160 148 198 104 199 C60 200 54 170 68 142 Z"), SUIT, o({ dx: -7, dy: -6, shadow: "#c8cee0" }));
  s += line("M104 138 L104 190", 1.6, INK, ' opacity="0.3"');
  s += line("M76 170 Q90 178 96 192 M134 168 Q124 180 114 192", 1.5, INK, ' opacity="0.25"');
  // suit leg cuffs + webbed feet
  for (const [x, flip] of [[86, 1], [122, 1]]) {
    s += part(E(x, 193, 13, 6), BLUE, o({ dx: -1, dy: -2, stroke: 3 }));
    s += part(P(`M${x - 13} 205 Q${x - 15} 196 ${x} 196 Q${x + 15} 196 ${x + 13} 205 Q${x + 10} 212 ${x + 6} 207 Q${x + 3} 213 ${x} 207 Q${x - 3} 213 ${x - 6} 207 Q${x - 10} 212 ${x - 13} 205 Z`),
      ORANGE, o({ dx: -1, dy: -2, stroke: 3.5, shadow: ORANGE_D }));
    s += line(`M${x - 3} 199 L${x - 4} 205 M${x + 3} 199 L${x + 4} 205`, 1.2, "#b9601f", ' opacity="0.7"');
  }
  // chest: control panel + Rocket Race patch
  s += part(R(82, 146, 20, 13, 4), NAVY, o({ dx: 0, dy: 0, stroke: 2.5 }));
  s += flat(C(88, 152.5, 2.3), "#7ed6a0") + flat(C(95, 152.5, 2.3), "#ffc56b") + flat(R(85, 156, 14, 1.5, 0.75), "#5a6690");
  s += part(C(124, 154, 10), NAVY, o({ dx: -1, dy: -1, stroke: 2.5 }));
  s += flat(P("M124 145.5 C128 149 128 156 126.5 158.5 L121.5 158.5 C120 156 120 149 124 145.5 Z"), "#f2f4f9");
  s += flat(P("M121.5 158.5 L124 163 L126.5 158.5 Z"), ORANGE) + flat(C(124, 152, 1.5), BLUE);
  s += line("M115 150 Q114 145 118 146", 1.2, "#fff", ' opacity="0.8"');

  // near wing (down, viewer's left) coming out of a sleeve cuff
  s += part(P("M76 140 C56 138 42 158 46 180 Q52 188 57 181 Q61 190 67 182 Q74 187 77 176 C82 164 84 150 76 140 Z"), WHITE, o({ shadow: FEATHER_SH, dx: -3, dy: -3 }));
  s += line("M55 170 Q58 162 64 157 M64 176 Q66 167 72 161", 1.5, "#aab0c4");
  s += part(R(-9, -5, 18, 10, 5, ' transform="translate(72,144) rotate(-28)"'), BLUE, o({ dx: 0, dy: -1, stroke: 3 }));

  // helmet: shell, near ear pod, visor opening, head inside, glass, rim
  s += part(C(102, 76, 55), "#eef1f7", o({ dx: -6, dy: -6, shadow: "#bfc7d9" }));
  s += part(C(49, 84, 13), "#c9d0de", o({ dx: -2, dy: -2 }));
  s += part(C(49, 84, 7.5), BLUE, o({ dx: -1, dy: -1, stroke: 2.5 })) + flat(C(47, 82, 2.2), "#e8fbff");
  const visor = E(108, 82, 42, 40);
  K.addDef(`<clipPath id="visor">${visor}</clipPath>`);
  s += flat(visor, "#25335a");
  let head = "";
  head += part(E(110, 92, 45, 44), WHITE, o({ shadow: FEATHER_SH, dx: -6, dy: -7, outline: false }));
  // forehead feather curl
  head += part(P("M100 46 C98 38 104 34 108 38 C106 40 106 44 110 46 C112 40 118 40 118 46 Z"), WHITE, o({ shadow: FEATHER_SH, dx: -1, dy: -1, stroke: 2.4 }));
  // eyes (3/4 view: far eye a bit narrower)
  for (const [x, w] of [[92, 9.5], [126, 8.5]]) {
    head += flat(E(x, 80, w, 11.5), INK);
    head += flat(E(x + 0.5, 82.5, w * 0.72, 8.5), IRIS);
    head += flat(E(x + 0.5, 85.5, w * 0.6, 4.5), "#7fd8c8", ' opacity="0.7"');
    head += flat(E(x + 1, 82.5, w * 0.36, 5), INK);
    head += flat(C(x - 3, 75.5, 3.6), "#fff") + flat(C(x + 3.5, 86, 1.6), "#fff");
    head += line(`M${x - w} ${70} Q${x} ${64} ${x + w} ${70}`, 1.4, INK, ' opacity="0.0"');
  }
  head += flat(E(80, 98, 7, 4), "#f49aa8", ' opacity="0.85"') + flat(E(140, 98, 6, 3.6), "#f49aa8", ' opacity="0.85"');
  // bill: lower then upper, nostrils, gloss
  head += part(P("M98 104 Q112 117 128 104 Z"), ORANGE_D, o({ dx: 0, dy: -1, stroke: 3, shadow: "#c46526" }));
  head += part(P("M95 96 C97 88 129 87 133 95 C138 103 126 109 112 108 C98 109 89 103 95 96 Z"), ORANGE, o({ dx: -2, dy: -3, stroke: 3.2, shadow: ORANGE_D }));
  head += flat(E(107, 93.5, 1.7, 1) + E(119, 93.5, 1.7, 1), "#a55a1e") + shine(102, 95, 6, 1.8, 0.75, -12);
  s += `<g clip-path="url(#visor)">${head}</g>`;
  s += `<g clip-path="url(#visor)"><path d="M70 74 Q74 52 92 44" fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round" opacity="0.7"/>${flat(visor, "#cfefff", ' opacity="0.07"')}</g>`;
  s += `<g fill="none" stroke="${BLUE}" stroke-width="6">${visor}</g><g fill="none" stroke="${INK}" stroke-width="3">${E(108, 82, 45, 43)}</g>`;
  s += shine(70, 36, 12, 4, 0.8, -40);

  // collar ring joining helmet and suit
  s += line("M70 124 Q104 142 138 124", 16, INK) + line("M70 124 Q104 142 138 124", 9, BLUE) +
    line("M80 129 Q90 133 98 134", 2.5, "#bfe3ff", ' opacity="0.9"');

  // far wing raised, waving (in front), with motion marks
  s += part(R(-9, -5, 18, 10, 5, ' transform="translate(137,140) rotate(-40)"'), BLUE, o({ dx: 0, dy: -1, stroke: 3 }));
  s += part(P("M136 134 C144 118 154 102 168 96 Q180 93 180 103 Q189 107 183 116 Q188 125 177 127 C168 136 156 145 144 148 Z"), WHITE, o({ shadow: FEATHER_SH, dx: -2, dy: -3 }));
  s += line("M150 132 Q158 122 168 116 M156 139 Q164 131 172 126", 1.5, "#aab0c4");
  s += line("M184 92 Q189 98 187 106 M189 85 Q196 95 193 107", 2.5, INK, ' opacity="0.55"');

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 220" width="200" height="220"><defs>${K.takeDefs()}</defs>${s}</svg>`;
}

fs.writeFileSync(path.join(__dirname, "duck_astro.svg"), duck());
console.log("wrote duck_astro.svg");
