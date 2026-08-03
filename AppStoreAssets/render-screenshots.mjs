import { mkdir, readFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const require = createRequire(new URL('../web/package.json', import.meta.url));
const sharp = require('sharp');

const assetDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.dirname(assetDirectory);
const sourceDirectory = path.join(assetDirectory, 'sources');
const outputDirectory = path.join(assetDirectory, 'screenshots/iphone-6.9-en-US');
const qaDirectory = path.join(assetDirectory, 'qa');

const canvasWidth = 1320;
const canvasHeight = 2868;
const background = '#0D1117';
const accent = '#86D30A';
const accentRuleBottom = 515;

// The phone is sized from the captures rather than the other way round. Every
// body is scaled by width only, so no column of app UI is ever lost, and each
// screen's window runs from below its capture's own status chrome down to a
// row that sits in a gap between two real elements. Because the captures are
// scrolled to different places, those gaps do not all land at the same height,
// so the body height is derived per screen and the devices are centred in one
// band; `maxDeviceSpread` keeps that variation small enough to read as one
// device across the set.
const phoneFrame = 18;
const innerWidth = 1012;
const statusBarHeight = 130;
const phoneWidth = innerWidth + phoneFrame * 2;
const phoneX = Math.round((canvasWidth - phoneWidth) / 2);
const deviceBandTop = 585;
const maxDeviceSpread = 40;

const statusBarMaster = {
  file: 'real-ui-first-ascent.png',
  crop: { left: 0, top: 0, width: 1206, height: 155 },
};

const fontPath = path.join(
  repositoryRoot,
  'AscendApp/Resources/Fonts/Montserrat/Montserrat-Bold.ttf'
);
const fontData = await readFile(fontPath);
const fontBase64 = fontData.toString('base64');

// `statusBandBottom` is the first capture row clear of the device's own status
// chrome - one past the bottom of its Dynamic Island, which is drawn black and
// so is invisible on a dark capture but shows as a second pill over a lighter
// app surface. `sourceTop` must start at or below it.
// `lastRow` is the final row of the last element that must be whole on screen
// and `nextRow` the first row of the element that must not appear at all;
// `sourceBottom` is asserted to fall between them, so no card, row, glyph or
// control can be sliced by a later change to a capture or to the geometry.
const screens = [
  {
    filename: '01-get-fit-stair-stepper.png',
    photo: '01-stair-stepper-effort.png',
    uiSource: 'real-ui-live-climb-share.png',
    // The recap card is roughly half a screen tall, so the device runs off the
    // bottom of the canvas and the visible screen is exactly the capture's
    // chrome-free window: the card and the app background above it, ending
    // before the page dots. Nothing is synthesized to fill a taller body.
    bleed: true,
    statusBandBottom: 108,
    sourceTop: 262,
    sourceBottom: 1346,
    lastRow: 1339,
    nextRow: 1351,
    lines: ['GET FIT ON THE', 'STAIR STEPPER.'],
  },
  {
    filename: '02-climb-everest-stair-stepper.png',
    photo: '02-everest-summit.png',
    uiSource: 'real-ui-landmarks.png',
    statusBandBottom: 153,
    sourceTop: 153,
    sourceBottom: 2586,
    lastRow: 2107,
    nextRow: 2622,
    lines: ['CLIMB EVEREST FROM', 'YOUR STAIR STEPPER.'],
  },
  {
    filename: '03-race-real-landmarks.png',
    uiSource: 'real-ui-globe-browse.jpg',
    statusBandBottom: 93,
    sourceTop: 93,
    sourceBottom: 1566,
    lastRow: 1546,
    nextRow: 1567,
    lines: ['RACE THE WORLD UP', 'REAL LANDMARKS.'],
  },
  {
    filename: '04-race-real-climbers.png',
    uiSource: 'real-ui-live-attempt-leaderboard.png',
    // This capture was taken with the status bar hidden, so its first row is
    // already app surface and the normalized band sits above it.
    statusBandBottom: 0,
    sourceTop: 44,
    sourceBottom: 1772,
    lastRow: 1766,
    nextRow: 1816,
    lines: ['RACE REAL CLIMBERS,', 'STEP FOR STEP.'],
  },
  {
    filename: '05-every-step-ranked.png',
    uiSource: 'real-ui-climb-leaderboard-20.png',
    statusBandBottom: 153,
    sourceTop: 153,
    sourceBottom: 2588,
    lastRow: 2581,
    nextRow: 2622,
    lines: ['EVERY STEP', 'RANKED.'],
  },
  {
    filename: '06-first-ascent-forever.png',
    uiSource: 'real-ui-first-ascent.png',
    statusBandBottom: 153,
    sourceTop: 153,
    sourceBottom: 2586,
    lastRow: 2380,
    nextRow: 2622,
    lines: ['BE THE FIRST.', 'CLAIM IT FOREVER.'],
  },
  {
    filename: '07-record-book-climbing.png',
    uiSource: 'real-ui-best-effort.png',
    statusBandBottom: 153,
    sourceTop: 170,
    sourceBottom: 2622,
    lastRow: 2621,
    nextRow: 2622,
    lines: ['YOUR RECORD BOOK.', "AND IT'S CLIMBING."],
  },
];

function escapeXml(value) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

function textSvg(lines) {
  const textLines = lines
    .map((line, index) => (
      `<text x="96" y="${242 + index * 118}">${escapeXml(line)}</text>`
    ))
    .join('');

  return Buffer.from(`
    <svg width="${canvasWidth}" height="${canvasHeight}" xmlns="http://www.w3.org/2000/svg">
      <style>
        @font-face {
          font-family: AscendMontserrat;
          src: url(data:font/ttf;base64,${fontBase64});
        }
        text {
          fill: #FFFFFF;
          font-family: AscendMontserrat, sans-serif;
          font-size: 102px;
          font-weight: 700;
          letter-spacing: -2px;
        }
      </style>
      ${textLines}
    </svg>
  `);
}

function marketingChromeSvg() {
  return Buffer.from(`
    <svg width="${canvasWidth}" height="${canvasHeight}" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <radialGradient id="glow" cx="88%" cy="4%" r="80%">
          <stop offset="0%" stop-color="${accent}" stop-opacity="0.08" />
          <stop offset="58%" stop-color="${accent}" stop-opacity="0" />
        </radialGradient>
      </defs>
      <rect width="${canvasWidth}" height="${canvasHeight}" fill="${background}" />
      <rect width="${canvasWidth}" height="${canvasHeight}" fill="url(#glow)" />
      <rect x="96" y="505" width="118" height="10" rx="5" fill="${accent}" />
    </svg>
  `);
}

function photoScrimSvg() {
  return Buffer.from(`
    <svg width="${canvasWidth}" height="${canvasHeight}" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="scrim" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#05080C" stop-opacity="0.66" />
          <stop offset="25%" stop-color="#05080C" stop-opacity="0.34" />
          <stop offset="64%" stop-color="#05080C" stop-opacity="0.26" />
          <stop offset="100%" stop-color="#05080C" stop-opacity="0.72" />
        </linearGradient>
      </defs>
      <rect width="${canvasWidth}" height="${canvasHeight}" fill="url(#scrim)" />
      <rect x="96" y="505" width="118" height="10" rx="5" fill="${accent}" />
    </svg>
  `);
}

async function normalizedStatusBar() {
  return sharp(path.join(sourceDirectory, statusBarMaster.file))
    .extract(statusBarMaster.crop)
    .resize(innerWidth, statusBarHeight, { fit: 'fill' })
    .flatten({ background: '#101010' })
    .png()
    .toBuffer();
}

/// Resolves and checks the capture window each screen shows, and the body height
/// that window scales to. Scaling is width-driven, so nothing is lost sideways.
async function measureScreen(screen) {
  const metadata = await sharp(path.join(sourceDirectory, screen.uiSource)).metadata();

  if (screen.sourceTop < screen.statusBandBottom) {
    throw new Error(
      `${screen.filename}: the body starts at capture row ${screen.sourceTop}, inside `
      + `${screen.uiSource}'s own status chrome, which reaches row ${screen.statusBandBottom - 1}. `
      + 'Those rows would render as a second status bar below the normalized one'
    );
  }

  if (screen.sourceBottom > metadata.height) {
    throw new Error(
      `${screen.filename}: the body ends at capture row ${screen.sourceBottom}, past the end of `
      + `${screen.uiSource} at row ${metadata.height}`
    );
  }

  if (screen.sourceBottom <= screen.lastRow) {
    throw new Error(
      `${screen.filename}: the body ends at capture row ${screen.sourceBottom}, which slices the `
      + `element running to row ${screen.lastRow}`
    );
  }

  if (screen.sourceBottom > screen.nextRow) {
    throw new Error(
      `${screen.filename}: the body ends at capture row ${screen.sourceBottom}, which slices the `
      + `element starting at row ${screen.nextRow}`
    );
  }

  const window = screen.sourceBottom - screen.sourceTop;

  return {
    sourceWidth: metadata.width,
    window,
    bodyHeight: Math.round(window * innerWidth / metadata.width),
  };
}

async function bodyBuffer(screen, measurement) {
  return sharp(path.join(sourceDirectory, screen.uiSource))
    .extract({
      left: 0,
      top: screen.sourceTop,
      width: measurement.sourceWidth,
      height: measurement.window,
    })
    .resize(innerWidth, measurement.bodyHeight, { fit: 'fill' })
    .flatten({ background: '#000000' })
    .png()
    .toBuffer();
}

async function phoneBuffer(screen, measurement, statusBar, device) {
  const visibleInnerHeight = statusBarHeight + measurement.bodyHeight;
  // A bleeding device shows its top bezel only; its bottom bezel is off canvas.
  const outlineInnerHeight = screen.bleed ? device.innerHeight : visibleInnerHeight;
  const outlinePhoneHeight = outlineInnerHeight + phoneFrame * 2;
  const visiblePhoneHeight = visibleInnerHeight + phoneFrame * (screen.bleed ? 1 : 2);

  if (visibleInnerHeight > outlineInnerHeight) {
    throw new Error(
      `${screen.filename}: its ${visibleInnerHeight}px screen is taller than the ${outlineInnerHeight}px `
      + 'device it is drawn inside, so the rounded mask would blank the bottom of the composite'
    );
  }

  const ui = await sharp({
    create: {
      width: innerWidth,
      height: visibleInnerHeight,
      channels: 4,
      background: '#000000',
    },
  })
    .composite([
      { input: statusBar, top: 0, left: 0 },
      { input: await bodyBuffer(screen, measurement), top: statusBarHeight, left: 0 },
      {
        input: Buffer.from(`
          <svg width="${innerWidth}" height="${visibleInnerHeight}" xmlns="http://www.w3.org/2000/svg">
            <rect width="${innerWidth}" height="${outlineInnerHeight}" rx="66" fill="#FFFFFF" />
          </svg>
        `),
        blend: 'dest-in',
      },
    ])
    .png()
    .toBuffer();

  const frame = Buffer.from(`
    <svg width="${phoneWidth}" height="${visiblePhoneHeight}" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <filter id="shadow" x="-30%" y="-20%" width="160%" height="160%">
          <feDropShadow dx="0" dy="22" stdDeviation="24" flood-color="#000000" flood-opacity="0.62" />
        </filter>
      </defs>
      <rect
        x="4"
        y="4"
        width="${phoneWidth - 8}"
        height="${outlinePhoneHeight - 8}"
        rx="82"
        fill="#080A0C"
        stroke="#353A40"
        stroke-width="4"
        filter="url(#shadow)"
      />
    </svg>
  `);

  const buffer = await sharp({
    create: {
      width: phoneWidth,
      height: visiblePhoneHeight,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  })
    .composite([
      { input: frame, top: 0, left: 0 },
      { input: ui, top: phoneFrame, left: phoneFrame },
    ])
    .png()
    .toBuffer();

  const top = screen.bleed
    ? canvasHeight - visiblePhoneHeight
    : deviceBandTop + Math.round((device.phoneHeight - visiblePhoneHeight) / 2);

  if (top + visiblePhoneHeight > canvasHeight || top <= accentRuleBottom) {
    throw new Error(
      `${screen.filename}: the device (${phoneWidth}x${visiblePhoneHeight} at ${phoneX},${top}) `
      + `does not sit between the headline rule and the bottom of the ${canvasWidth}x${canvasHeight} canvas`
    );
  }

  return { buffer, top };
}

async function renderScreen(screen, measurement, statusBar, device) {
  const backgroundLayer = screen.photo
    ? await sharp(path.join(sourceDirectory, screen.photo))
      .resize(canvasWidth, canvasHeight, { fit: 'cover', position: 'centre' })
      .flatten({ background })
      .png()
      .toBuffer()
    : marketingChromeSvg();

  const phone = await phoneBuffer(screen, measurement, statusBar, device);
  const composites = [{ input: backgroundLayer, top: 0, left: 0 }];

  if (screen.photo) {
    composites.push({ input: photoScrimSvg(), top: 0, left: 0 });
  }

  composites.push(
    { input: textSvg(screen.lines), top: 0, left: 0 },
    { input: phone.buffer, top: phone.top, left: phoneX }
  );

  const outputPath = path.join(outputDirectory, screen.filename);
  await sharp({
    create: {
      width: canvasWidth,
      height: canvasHeight,
      channels: 3,
      background,
    },
  })
    .composite(composites)
    .flatten({ background })
    .removeAlpha()
    .toColourspace('srgb')
    .png({ compressionLevel: 9 })
    .withMetadata({ density: 72 })
    .toFile(outputPath);

  return phone.top;
}

async function renderContactSheet() {
  const thumbWidth = 240;
  const thumbHeight = Math.round(thumbWidth * canvasHeight / canvasWidth);
  const gap = 24;
  const padding = 32;
  const sheetWidth = padding * 2 + screens.length * thumbWidth + (screens.length - 1) * gap;
  const sheetHeight = padding * 2 + thumbHeight;

  const thumbnails = await Promise.all(
    screens.map((screen) => (
      sharp(path.join(outputDirectory, screen.filename))
        .resize(thumbWidth, thumbHeight, { fit: 'fill' })
        .png()
        .toBuffer()
    ))
  );

  await sharp({
    create: {
      width: sheetWidth,
      height: sheetHeight,
      channels: 3,
      background: '#06090D',
    },
  })
    .composite(thumbnails.map((thumbnail, index) => ({
      input: thumbnail,
      left: padding + index * (thumbWidth + gap),
      top: padding,
    })))
    .png({ compressionLevel: 9 })
    .toFile(path.join(qaDirectory, 'app-store-contact-sheet.png'));
}

function resolveDevice(measurements) {
  const framed = screens
    .filter((screen) => !screen.bleed)
    .map((screen) => measurements.get(screen.filename).bodyHeight);
  const tallest = Math.max(...framed);
  const spread = tallest - Math.min(...framed);

  if (spread > maxDeviceSpread) {
    throw new Error(
      `The framed screens' body heights span ${spread}px, past the ${maxDeviceSpread}px that still `
      + 'reads as one device across the set'
    );
  }

  const innerHeight = statusBarHeight + tallest;
  const phoneHeight = innerHeight + phoneFrame * 2;

  if (deviceBandTop + phoneHeight > canvasHeight) {
    throw new Error(
      `The device band (${phoneHeight}px from ${deviceBandTop}) runs past the bottom of the `
      + `${canvasWidth}x${canvasHeight} canvas`
    );
  }

  return { innerHeight, phoneHeight, spread };
}

async function validateOutputs(phoneTops) {
  const expectedFilenames = screens.map((screen) => screen.filename).sort();
  const actualFilenames = (await readdir(outputDirectory))
    .filter((filename) => filename.endsWith('.png'))
    .sort();

  if (JSON.stringify(actualFilenames) !== JSON.stringify(expectedFilenames)) {
    throw new Error(`Expected exactly seven screenshot PNG files, found: ${actualFilenames.join(', ')}`);
  }

  const statusBarHashes = [];

  for (const screen of screens) {
    const outputPath = path.join(outputDirectory, screen.filename);
    const metadata = await sharp(outputPath).metadata();
    const colorSpace = metadata.space?.toLowerCase();

    if (
      metadata.width !== canvasWidth
      || metadata.height !== canvasHeight
      || colorSpace !== 'srgb'
      || metadata.hasAlpha
    ) {
      throw new Error(`Invalid App Store screenshot output: ${screen.filename}`);
    }

    const statusBarPixels = await sharp(outputPath)
      .extract({
        left: phoneX + phoneFrame + 70,
        top: phoneTops.get(screen.filename) + phoneFrame,
        width: innerWidth - 140,
        height: statusBarHeight,
      })
      .raw()
      .toBuffer();
    statusBarHashes.push(
      createHash('sha256').update(statusBarPixels).digest('hex')
    );

    console.log(
      `${screen.filename}: ${metadata.width}x${metadata.height}, ${colorSpace}, alpha=${metadata.hasAlpha}`
    );
  }

  if (new Set(statusBarHashes).size !== 1) {
    throw new Error('Status-bar pixels are not identical across all seven screenshots');
  }
}

await mkdir(outputDirectory, { recursive: true });
await mkdir(qaDirectory, { recursive: true });

const measurements = new Map();
for (const screen of screens) {
  measurements.set(screen.filename, await measureScreen(screen));
}

const device = resolveDevice(measurements);
const statusBar = await normalizedStatusBar();
const phoneTops = new Map();

for (const screen of screens) {
  phoneTops.set(
    screen.filename,
    await renderScreen(screen, measurements.get(screen.filename), statusBar, device)
  );
}

await validateOutputs(phoneTops);
await renderContactSheet();

console.log(`device ${phoneWidth}x${device.phoneHeight}, body-height spread ${device.spread}px`);
