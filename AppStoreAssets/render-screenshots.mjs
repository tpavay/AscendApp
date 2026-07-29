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

// The phone screen is sized from the captures rather than the other way round:
// every app capture is a whole 19.5:9 iPhone screen, so the inner screen keeps
// that aspect and each capture lands at its true proportions. Scaling is always
// width-driven, which is what keeps app text and card edges off the crop line.
// The body height is then tuned so that every screen's bottom edge lands in the
// gap between two real elements - see `lastRow` / `nextRow` on each screen.
const phoneFrame = 18;
const innerWidth = 1012;
const statusBarHeight = 130;
const bodyHeight = 2052;
const innerHeight = statusBarHeight + bodyHeight;
const phoneWidth = innerWidth + phoneFrame * 2;
const phoneHeight = innerHeight + phoneFrame * 2;
const phoneX = Math.round((canvasWidth - phoneWidth) / 2);
const phoneY = 585;

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

// `sourceTop` is the first capture row the phone body shows: past the capture's
// own status band, inside the blank gap above the first real element.
// `lastRow` is the final row of the last element that must be whole on screen and
// `nextRow` the first row of the element that must not appear at all. The renderer
// asserts the body's bottom edge falls between them, so no card, row, glyph or
// control can be sliced by a later change to the geometry or to a capture.
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
    sourceTop: 155,
    lastRow: 2107,
    nextRow: 2622,
    lines: ['CLIMB EVEREST FROM', 'YOUR STAIR STEPPER.'],
  },
  {
    filename: '03-race-real-landmarks.png',
    uiSource: 'real-ui-globe-browse.jpg',
    sourceTop: 72,
    lastRow: 1546,
    nextRow: 1570,
    lines: ['RACE THE WORLD UP', 'REAL LANDMARKS.'],
  },
  {
    filename: '04-race-real-climbers.png',
    uiSource: 'real-ui-live-attempt-leaderboard.png',
    sourceTop: 44,
    lastRow: 1766,
    nextRow: 1816,
    lines: ['RACE REAL CLIMBERS,', 'STEP FOR STEP.'],
  },
  {
    filename: '05-every-step-ranked.png',
    uiSource: 'real-ui-climb-leaderboard.jpg',
    sourceTop: 72,
    lastRow: 1550,
    nextRow: 1574,
    lines: ['EVERY STEP', 'RANKED.'],
  },
  {
    filename: '06-first-ascent-forever.png',
    uiSource: 'real-ui-first-ascent.png',
    sourceTop: 155,
    lastRow: 2380,
    nextRow: 2622,
    lines: ['BE THE FIRST.', 'CLAIM IT FOREVER.'],
  },
  {
    filename: '07-record-book-climbing.png',
    uiSource: 'real-ui-best-effort.png',
    sourceTop: 176,
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

/// The capture window the phone body shows, scaled by width so no column of app
/// UI is ever lost. Every visible pixel comes from the capture.
async function bodyBuffer(screen) {
  const uiPath = path.join(sourceDirectory, screen.uiSource);
  const metadata = await sharp(uiPath).metadata();
  const windowHeight = screen.bleed
    ? screen.sourceBottom - screen.sourceTop
    : Math.ceil(metadata.width * bodyHeight / innerWidth);
  const bottomEdge = screen.sourceTop + windowHeight;

  if (bottomEdge > metadata.height) {
    throw new Error(
      `${screen.filename}: ${screen.uiSource} offers ${metadata.height - screen.sourceTop} rows `
      + `below its status band, but the phone body needs ${windowHeight} to fill without cropping sideways`
    );
  }

  if (bottomEdge <= screen.lastRow) {
    throw new Error(
      `${screen.filename}: the body ends at capture row ${bottomEdge}, which slices the element `
      + `running to row ${screen.lastRow}`
    );
  }

  if (bottomEdge > screen.nextRow) {
    throw new Error(
      `${screen.filename}: the body ends at capture row ${bottomEdge}, which slices the element `
      + `starting at row ${screen.nextRow}`
    );
  }

  const height = screen.bleed
    ? Math.round(windowHeight * innerWidth / metadata.width)
    : bodyHeight;

  const buffer = await sharp(uiPath)
    .extract({ left: 0, top: screen.sourceTop, width: metadata.width, height: windowHeight })
    .resize(innerWidth, height, { fit: 'fill' })
    .flatten({ background: '#000000' })
    .png()
    .toBuffer();

  return { buffer, height };
}

async function phoneBuffer(screen, statusBar) {
  const body = await bodyBuffer(screen);
  const visibleInnerHeight = statusBarHeight + body.height;
  // A bleeding device shows its top bezel only; its bottom bezel is off canvas.
  const visiblePhoneHeight = visibleInnerHeight + phoneFrame * (screen.bleed ? 1 : 2);

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
      { input: body.buffer, top: statusBarHeight, left: 0 },
      {
        input: Buffer.from(`
          <svg width="${innerWidth}" height="${visibleInnerHeight}" xmlns="http://www.w3.org/2000/svg">
            <rect width="${innerWidth}" height="${innerHeight}" rx="66" fill="#FFFFFF" />
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
        height="${phoneHeight - 8}"
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

  const top = screen.bleed ? canvasHeight - visiblePhoneHeight : phoneY;

  if (top + visiblePhoneHeight > canvasHeight || top <= accentRuleBottom) {
    throw new Error(
      `${screen.filename}: the device (${phoneWidth}x${visiblePhoneHeight} at ${phoneX},${top}) `
      + `does not sit between the headline rule and the bottom of the ${canvasWidth}x${canvasHeight} canvas`
    );
  }

  return { buffer, top };
}

async function renderScreen(screen, statusBar) {
  const backgroundLayer = screen.photo
    ? await sharp(path.join(sourceDirectory, screen.photo))
      .resize(canvasWidth, canvasHeight, { fit: 'cover', position: 'centre' })
      .flatten({ background })
      .png()
      .toBuffer()
    : marketingChromeSvg();

  const phone = await phoneBuffer(screen, statusBar);
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

const statusBar = await normalizedStatusBar();
const phoneTops = new Map();

for (const screen of screens) {
  phoneTops.set(screen.filename, await renderScreen(screen, statusBar));
}

await validateOutputs(phoneTops);
await renderContactSheet();
