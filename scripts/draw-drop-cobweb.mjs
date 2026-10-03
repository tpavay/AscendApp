#!/usr/bin/env node

/**
 * Draws the Halloween drop email's cobweb as SVG, from the same recipe and
 * seed as the app's haunted-gate web (`MountainHauntedProps.web` on the
 * Halloween build): a haze of loose silk sagging between the two walls of a
 * corner, an uneven orb whose spiral is broken in places, and a few torn
 * threads hanging from its edge - so the email's web and the app's match.
 * The email adds a soft glow so the silk sits in the dark rather than on it.
 *
 * The web is anchored in the top-left corner. Rasterize it and flip it for
 * other corners:
 *   node scripts/draw-drop-cobweb.mjs > web.svg
 *   rsvg-convert -w 320 -h 320 web.svg -o cobweb-top-left.png
 * then rerun `node scripts/build-drop-email-assets.mjs`.
 */

const SIZE = 1024;

/**
 * The app's linear congruential generator, bit for bit (UInt64 wrapping).
 * @param {bigint} seed Initial seed.
 * @return {function(): number} Next value in [0, 1).
 */
function generator(seed) {
  let state = seed;
  const mask = (1n << 64n) - 1n;
  return () => {
    state = (state * 6364136223846793005n + 1442695040888963407n) & mask;
    return Number(state >> 40n) / 2 ** 24;
  };
}

/**
 * Builds the web's SVG.
 * @return {string} SVG document.
 */
export function cobwebSvg() {
  const random = generator(0x5EEDC0B3n);
  const full = SIZE;
  // Core Graphics draws y-up from the bottom; SVG draws y-down. The app's
  // corner (0, full) is the top-left, so flip every y.
  const flip = (y) => (full - y).toFixed(1);
  const point = (angle, radius) => ({
    x: Math.cos(angle) * radius,
    y: full + Math.sin(angle) * radius,
  });
  const silk = (alpha) => `rgba(236,236,248,${alpha.toFixed(3)})`;
  const paths = [];
  const quad = (from, control, to, color, width) => paths.push(
    `<path d="M${from.x.toFixed(1)} ${flip(from.y)} Q${control.x.toFixed(1)} ` +
      `${flip(control.y)} ${to.x.toFixed(1)} ${flip(to.y)}" stroke="${color}" ` +
      `stroke-width="${width.toFixed(2)}"/>`
  );

  // The haze: threads strung from the top wall to the side wall, each sagging.
  for (let index = 0; index < 260; index += 1) {
    const from = {x: random() * full * 0.9, y: full};
    const to = {x: 0, y: full - random() * full * 0.9};
    const middle = {x: (from.x + to.x) / 2, y: (from.y + to.y) / 2};
    const sag = {x: middle.x + random() * 60, y: middle.y - 40 - random() * 120};
    const alpha = 0.05 + random() * 0.12;
    const width = 1 + random() * 1.4;
    quad(from, sag, to, silk(alpha), width);
  }

  // The orb: uneven spokes, a spiral with gaps where threads have broken.
  const angles = [];
  for (let spoke = 0; spoke <= 12; spoke += 1) {
    const wobble = (random() - 0.5) * 0.09;
    angles.push(-Math.PI / 2 * Math.min(Math.max(spoke / 12 + wobble, 0), 1));
  }
  const corner = {x: 0, y: full};
  for (const angle of angles) {
    const width = 2 + random() * 1.2;
    const reach = full * (0.72 + random() * 0.26);
    const control = point(angle + (random() - 0.5) * 0.06, reach * 0.5);
    quad(corner, control, point(angle, reach), silk(0.75), width);
  }
  let radius = full * 0.06;
  while (radius < full * 0.78) {
    for (let index = 0; index + 1 < angles.length; index += 1) {
      if (!(random() > 0.16)) {
        continue;
      }
      const a0 = angles[index];
      const a1 = angles[index + 1];
      const r0 = radius * (0.97 + random() * 0.06);
      const r1 = radius * (0.97 + random() * 0.06);
      const alpha = 0.35 + random() * 0.35;
      const width = 1.2 + random();
      const control = point((a0 + a1) / 2, (r0 + r1) / 2 * (0.86 + random() * 0.08));
      quad(point(a0, r0), control, point(a1, r1), silk(alpha), width);
    }
    radius *= 1.1 + random() * 0.06;
  }

  // A few torn threads hanging loose from the orb's edge.
  for (let index = 0; index < 5; index += 1) {
    const start = point(-Math.PI / 2 * (0.15 + random() * 0.7), full * (0.55 + random() * 0.2));
    const end = {x: start.x + (random() - 0.5) * 40, y: start.y - 120 - random() * 160};
    quad(start, {x: start.x + 30, y: start.y - 60}, end, silk(0.5), 1.5);
  }

  const strands = paths.join("");
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${SIZE} ${SIZE}" `,
    `width="${SIZE}" height="${SIZE}">`,
    "<defs><filter id=\"glow\" x=\"-10%\" y=\"-10%\" width=\"120%\" height=\"120%\">",
    "<feGaussianBlur stdDeviation=\"7\"/></filter></defs>",
    // The glow: the same silk, blurred and faint, under the crisp strands.
    `<g fill="none" stroke-linecap="round" filter="url(#glow)" opacity="0.55">${strands}</g>`,
    `<g fill="none" stroke-linecap="round">${strands}</g>`,
    "</svg>",
  ].join("");
}

process.stdout.write(cobwebSvg());
