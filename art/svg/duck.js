// Rocket Race - astronaut duck poses (sticker style, full duck body).
//   node art/svg/duck.js   -> art/svg/duck_astro.svg, duck_bubble.svg, duck_cheer.svg (200x220)
// Round little duck in a white flight suit: wings for arms, webbed feet. Options choose the
// helmet (open visor or full glass bubble), wing poses, mouth, and facing direction.
const fs = require("fs");
const path = require("path");
const K = require("./pilots.js");
const { INK, part, flat, line, E, C, R, P, shine } = K;

const WHITE = "#f7f6f2", FEATHER_SH = "#cfd3e2";
const SUIT = "#f2f4f9", BLUE = "#4f9fe0", NAVY = "#2c3a6b";
const ORANGE = "#f7a23b", ORANGE_D = "#e07e2e", IRIS = "#2fa596";
const o = (x = {}) => Object.assign({ stroke: 4, dx: -4, dy: -4 }, x);
const FEATHER_LINE = "#aab0c4";

// ---- wings ------------------------------------------------------------------------------------
const NEAR = { // viewer's left wing
  down: () => part(P("M76 140 C56 138 42 158 46 180 Q52 188 57 181 Q61 190 67 182 Q74 187 77 176 C82 164 84 150 76 140 Z"), WHITE, o({ shadow: FEATHER_SH, dx: -3, dy: -3 })) +
    line("M55 170 Q58 162 64 157 M64 176 Q66 167 72 161", 1.5, FEATHER_LINE),
  chest: () => part(P("M74 140 C62 152 66 170 82 172 Q89 176 94 170 Q100 172 101 165 Q106 163 104 157 C96 150 88 150 80 140 Z"), WHITE, o({ shadow: FEATHER_SH, dx: -3, dy: -3 })) +
    line("M78 160 Q86 162 94 160 M80 167 Q88 168 96 165", 1.5, FEATHER_LINE),
  up: () => part(P("M72 136 C62 122 52 108 40 102 Q28 99 28 109 Q19 113 25 122 Q20 131 31 133 C40 141 52 147 64 150 Z"), WHITE, o({ shadow: FEATHER_SH, dx: -2, dy: -3 })) +
    line("M58 132 Q50 122 40 116 M52 139 Q44 133 36 128", 1.5, FEATHER_LINE),
};
const NEAR_CUFF = { down: [72, 144, -28], chest: [74, 144, 30], up: [71, 141, 40] };
const FAR = { // viewer's right wing (drawn in front)
  wave: () => part(P("M136 134 C144 118 154 102 168 96 Q180 93 180 103 Q189 107 183 116 Q188 125 177 127 C168 136 156 145 144 148 Z"), WHITE, o({ shadow: FEATHER_SH, dx: -2, dy: -3 })) +
    line("M150 132 Q158 122 168 116 M156 139 Q164 131 172 126", 1.5, FEATHER_LINE) +
    line("M184 92 Q189 98 187 106 M189 85 Q196 95 193 107", 2.5, INK, ' opacity="0.55"'),
  down: () => part(P("M132 140 C152 138 164 158 160 180 Q154 188 149 181 Q145 190 139 182 Q132 187 129 176 C124 164 124 150 132 140 Z"), WHITE, o({ shadow: FEATHER_SH, dx: -3, dy: -3 })) +
    line("M151 170 Q148 162 142 157 M142 176 Q140 167 134 161", 1.5, FEATHER_LINE),
};
const FAR_CUFF = { wave: [137, 140, -40], down: [136, 144, 28] };

function cuff([x, y, rot]) {
  return part(R(-9, -5, 18, 10, 5, ` transform="translate(${x},${y}) rotate(${rot})"`), BLUE, o({ dx: 0, dy: -1, stroke: 3 }));
}

// ---- face -----------------------------------------------------------------------------------
function face(mouth) {
  let s = "";
  for (const [x, w] of [[92, 9.5], [126, 8.5]]) {
    s += flat(E(x, 80, w, 11.5), INK);
    s += flat(E(x + 0.5, 82.5, w * 0.72, 8.5), IRIS);
    s += flat(E(x + 0.5, 85.5, w * 0.6, 4.5), "#7fd8c8", ' opacity="0.7"');
    s += flat(E(x + 1, 82.5, w * 0.36, 5), INK);
    s += flat(C(x - 3, 75.5, 3.6), "#fff") + flat(C(x + 3.5, 86, 1.6), "#fff");
  }
  s += flat(E(80, 98, 7, 4), "#f49aa8", ' opacity="0.85"') + flat(E(140, 98, 6, 3.6), "#f49aa8", ' opacity="0.85"');
  if (mouth === "open") { // cheering: lower bill dropped, mouth and tongue showing
    s += part(P("M97 102 Q112 128 129 102 Z"), ORANGE_D, o({ dx: 0, dy: -1, stroke: 3, shadow: "#c46526" }));
    s += flat(P("M101 104 Q112 121 125 104 Z"), "#8a2f3a") + flat(E(113, 113, 7, 4), "#f07a8a");
  } else {
    s += part(P("M98 104 Q112 117 128 104 Z"), ORANGE_D, o({ dx: 0, dy: -1, stroke: 3, shadow: "#c46526" }));
  }
  s += part(P("M95 96 C97 88 129 87 133 95 C138 103 126 107 112 106 C98 107 89 103 95 96 Z"), ORANGE, o({ dx: -2, dy: -3, stroke: 3.2, shadow: ORANGE_D }));
  s += flat(E(107, 93.5, 1.7, 1) + E(119, 93.5, 1.7, 1), "#a55a1e") + shine(102, 95, 6, 1.8, 0.75, -12);
  return s;
}
const TUFT = "M100 46 C98 38 104 34 108 38 C106 40 106 44 110 46 C112 40 118 40 118 46 Z";

// ---- the duck -------------------------------------------------------------------------------
function duck({ helmet = "visor", near = "down", far = "wave", mouth = "closed", mirror = false } = {}) {
  K.resetDefs();
  let s = "";

  // tail feathers, far ear pod, antenna (behind the helmet)
  s += part(P("M68 178 C52 178 44 168 42 156 C50 162 56 160 60 156 C58 164 64 168 72 166 Z"), WHITE, o({ shadow: FEATHER_SH, dx: -2, dy: -2 }));
  s += part(C(157, 82, 10), "#c9d0de", o({ dx: -2, dy: -2 }));
  if (helmet === "visor")
    s += line("M86 30 Q80 18 74 10", 3.5) + part(C(73, 9, 5.5), ORANGE, o({ dx: -1, dy: -1, stroke: 3 })) + shine(71, 7, 2, 1.2, 0.9, 0);

  // body + feet + suit details
  s += part(P("M68 142 C64 120 138 114 140 138 C148 160 148 198 104 199 C60 200 54 170 68 142 Z"), SUIT, o({ dx: -7, dy: -6, shadow: "#c8cee0" }));
  s += line("M104 138 L104 190", 1.6, INK, ' opacity="0.3"');
  s += line("M76 170 Q90 178 96 192 M134 168 Q124 180 114 192", 1.5, INK, ' opacity="0.25"');
  for (const x of [86, 122]) {
    s += part(E(x, 193, 13, 6), BLUE, o({ dx: -1, dy: -2, stroke: 3 }));
    s += part(P(`M${x - 13} 205 Q${x - 15} 196 ${x} 196 Q${x + 15} 196 ${x + 13} 205 Q${x + 10} 212 ${x + 6} 207 Q${x + 3} 213 ${x} 207 Q${x - 3} 213 ${x - 6} 207 Q${x - 10} 212 ${x - 13} 205 Z`),
      ORANGE, o({ dx: -1, dy: -2, stroke: 3.5, shadow: ORANGE_D }));
    s += line(`M${x - 3} 199 L${x - 4} 205 M${x + 3} 199 L${x + 4} 205`, 1.2, "#b9601f", ' opacity="0.7"');
  }
  if (near !== "chest") {
    s += part(R(82, 146, 20, 13, 4), NAVY, o({ dx: 0, dy: 0, stroke: 2.5 }));
    s += flat(C(88, 152.5, 2.3), "#7ed6a0") + flat(C(95, 152.5, 2.3), "#ffc56b") + flat(R(85, 156, 14, 1.5, 0.75), "#5a6690");
  }
  const px = near === "chest" ? 112 : 124; // patch sits where the chest wing can touch it
  s += `<g transform="translate(${px - 124},0)">`;
  s += part(C(124, 154, 10), NAVY, o({ dx: -1, dy: -1, stroke: 2.5 }));
  s += flat(P("M124 145.5 C128 149 128 156 126.5 158.5 L121.5 158.5 C120 156 120 149 124 145.5 Z"), "#f2f4f9");
  s += flat(P("M121.5 158.5 L124 163 L126.5 158.5 Z"), ORANGE) + flat(C(124, 152, 1.5), BLUE);
  s += line("M115 150 Q114 145 118 146", 1.2, "#fff", ' opacity="0.8"');
  s += "</g>";

  // near wing + cuff
  s += NEAR[near]() + cuff(NEAR_CUFF[near]);

  if (helmet === "visor") {
    // open-visor shell: face framed by a blue rim
    s += part(C(102, 76, 55), "#eef1f7", o({ dx: -6, dy: -6, shadow: "#bfc7d9" }));
    s += part(C(49, 84, 13), "#c9d0de", o({ dx: -2, dy: -2 }));
    s += part(C(49, 84, 7.5), BLUE, o({ dx: -1, dy: -1, stroke: 2.5 })) + flat(C(47, 82, 2.2), "#e8fbff");
    const visor = E(108, 82, 42, 40);
    K.addDef(`<clipPath id="visor">${visor}</clipPath>`);
    s += flat(visor, "#25335a");
    const head = part(E(110, 92, 45, 44), WHITE, o({ shadow: FEATHER_SH, dx: -6, dy: -7, outline: false })) +
      part(P(TUFT), WHITE, o({ shadow: FEATHER_SH, dx: -1, dy: -1, stroke: 2.4 })) + face(mouth);
    s += `<g clip-path="url(#visor)">${head}</g>`;
    s += `<g clip-path="url(#visor)"><path d="M70 74 Q74 52 92 44" fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round" opacity="0.7"/>${flat(visor, "#cfefff", ' opacity="0.07"')}</g>`;
    s += `<g fill="none" stroke="${BLUE}" stroke-width="6">${visor}</g><g fill="none" stroke="${INK}" stroke-width="3">${E(108, 82, 45, 43)}</g>`;
    s += shine(70, 36, 12, 4, 0.8, -40);
  } else {
    // full glass bubble: whole head visible inside, thick blue rim ring at the base
    K.addDef(`<radialGradient id="bub" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#e8fbff" stop-opacity="0.38"/><stop offset="1" stop-color="#7fb4d9" stop-opacity="0.3"/></radialGradient>`);
    s += `<circle cx="104" cy="74" r="58" fill="url(#bub)"/>`;
    s += part(R(92, 112, 26, 18, 9), WHITE, o({ shadow: FEATHER_SH, dx: -2, dy: -2, stroke: 3 })); // neck
    s += part(P("M104 30 C96 20 102 12 108 16 C106 20 108 24 112 26 C114 18 122 18 122 26 C120 30 116 32 112 32 Z"), WHITE, o({ shadow: FEATHER_SH, dx: -1, dy: -1, stroke: 2.6 }));
    s += part(E(110, 76, 40, 42), WHITE, o({ shadow: FEATHER_SH, dx: -5, dy: -6, stroke: 3.5 }));
    s += `<g transform="translate(1,-8)">${face(mouth)}</g>`;
    s += part(C(46, 92, 10), "#c9d0de", o({ dx: -2, dy: -2 })) + part(C(46, 92, 5.5), BLUE, o({ dx: -1, dy: -1, stroke: 2.5 }));
    s += `<circle cx="104" cy="74" r="56" fill="none" stroke="#e8fbff" stroke-width="2.5" opacity="0.55"/>`;
    s += `<circle cx="104" cy="74" r="58" fill="none" stroke="${INK}" stroke-width="4"/>`;
    s += line("M58 72 Q60 36 92 22", 6, "#fff", ' opacity="0.85"') + flat(C(101, 19, 3.2), "#fff");
    s += line("M154 92 Q150 110 136 120", 3, "#fff", ' opacity="0.45"');
  }

  // collar band joining helmet and suit
  s += line("M66 124 Q104 144 142 124", 16, INK) + line("M66 124 Q104 144 142 124", 9, BLUE) +
    line("M78 130 Q88 134 98 135", 2.5, "#bfe3ff", ' opacity="0.9"');

  // far wing + cuff (in front)
  s += cuff(FAR_CUFF[far]) + FAR[far]();

  const body = mirror ? `<g transform="translate(206,0) scale(-1,1)">${s}</g>` : s;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 220" width="200" height="220"><defs>${K.takeDefs()}</defs>${body}</svg>`;
}

const POSES = {
  duck_astro: {},
  duck_bubble: { helmet: "bubble", near: "chest", far: "down", mirror: true },
  duck_cheer: { helmet: "visor", near: "up", far: "wave", mouth: "open" },
};
for (const [name, opts] of Object.entries(POSES)) fs.writeFileSync(path.join(__dirname, name + ".svg"), duck(opts));
console.log("wrote", Object.keys(POSES).join(", "));
