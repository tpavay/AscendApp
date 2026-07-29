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

// The phone screen is sized from the captures rather than the other way round:
// every app capture is a whole 19.5:9 iPhone screen, so the inner screen keeps
// that aspect and each capture lands at its true proportions. Scaling is always
// width-driven, which is what keeps app text and card edges off the crop line.
const phoneFrame = 18;
const innerWidth = 1012;
const statusBarHeight = 130;
const bodyHeight = 2062;
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

// `sourceTop` is the capture's own status band (or, for a capture taken with the
// status bar hidden, its blank leading padding). Everything below it is genuine
// app surface and is shown whole.
const screens = [
  {
    filename: '01-get-fit-stair-stepper.png',
    photo: '01-stair-stepper-effort.png',
    uiSource: 'real-ui-live-climb-share.png',
    // The share sheet's recap card is the only surface carrying the full climb
    // story, and it is half a screen tall. Take the widest chrome-free window of
    // the real capture - card plus the app background around it, with the sheet
    // header, page dots, caption and destination buttons all outside it - and
    // extend that window's own edge rows to the rest of the screen.
    inset: { top: 262, height: 1084, focusY: 928 },
    lines: ['GET FIT ON THE', 'STAIR STEPPER.'],
  },
  {
    filename: '02-climb-everest-stair-stepper.png',
    photo: '02-everest-summit.png',
    uiSource: 'real-ui-landmarks.png',
    sourceTop: 155,
    lines: ['CLIMB EVEREST FROM', 'YOUR STAIR STEPPER.'],
  },
  {
    filename: '03-race-real-landmarks.png',
    uiSource: 'real-ui-globe-browse.jpg',
    sourceTop: 100,
    lines: ['RACE THE WORLD UP', 'REAL LANDMARKS.'],
  },
  {
    filename: '04-race-real-climbers.png',
    uiSource: 'real-ui-live-attempt-leaderboard.png',
    sourceTop: 43,
    lines: ['RACE REAL CLIMBERS,', 'STEP FOR STEP.'],
  },
  {
    filename: '05-every-step-ranked.png',
    uiSource: 'real-ui-climb-leaderboard.jpg',
    sourceTop: 100,
    lines: ['EVERY STEP', 'RANKED.'],
  },
  {
    filename: '06-first-ascent-forever.png',
    uiSource: 'real-ui-first-ascent.png',
    sourceTop: 155,
    lines: ['BE THE FIRST.', 'CLAIM IT FOREVER.'],
  },
  {
    filename: '07-record-book-climbing.png',
    uiSource: 'real-ui-best-effort.png',
    sourceTop: 155,
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

/// A whole app screen, scaled by width so nothing is ever lost sideways. The
/// window taken from the capture already carries the phone body's aspect, so the
/// final resize neither crops nor visibly stretches.
async function fullScreenBody(screen) {
  const uiPath = path.join(sourceDirectory, screen.uiSource);
  const metadata = await sharp(uiPath).metadata();
  const sourceTop = screen.sourceTop ?? 0;
  const windowHeight = Math.ceil(metadata.width * bodyHeight / innerWidth);
  const available = metadata.height - sourceTop;

  if (windowHeight > available) {
    throw new Error(
      `${screen.filename}: ${screen.uiSource} offers ${available} rows below its status band, `
      + `but the phone body needs ${windowHeight} to fill without cropping sideways`
    );
  }

  return sharp(uiPath)
    .extract({ left: 0, top: sourceTop, width: metadata.width, height: windowHeight })
    .resize(innerWidth, bodyHeight, { fit: 'fill' })
    .flatten({ background: '#000000' })
    .png()
    .toBuffer();
}

/// A chrome-free window of a real capture, scaled by width and centred on its
/// subject. The rest of the screen continues the window's own edge rows, so the
/// surrounding surface is the app's background rather than an invented one.
async function insetBody(screen) {
  const uiPath = path.join(sourceDirectory, screen.uiSource);
  const metadata = await sharp(uiPath).metadata();
  const { top, height, focusY } = screen.inset;

  if (top + height > metadata.height) {
    throw new Error(`${screen.filename}: inset window falls outside ${screen.uiSource}`);
  }

  const scaled = await sharp(uiPath)
    .extract({ left: 0, top, width: metadata.width, height })
    .resize({ width: innerWidth })
    .flatten({ background: '#000000' })
    .png()
    .toBuffer();
  const scaledHeight = (await sharp(scaled).metadata()).height;

  if (scaledHeight > bodyHeight) {
    throw new Error(`${screen.filename}: inset is taller than the phone body`);
  }

  const focusOffset = Math.round((focusY - top) * innerWidth / metadata.width);
  const insetTop = Math.min(
    Math.max(Math.round(bodyHeight / 2 - focusOffset), 0),
    bodyHeight - scaledHeight
  );
  const insetBottom = bodyHeight - insetTop - scaledHeight;
  const edge = 8;

  // Collapse the slice to a single column first: the capture's background is a
  // flat vertical ramp, so averaging across it keeps the ramp and drops the
  // capture noise that stretching would otherwise smear into vertical streaks.
  const edgeBand = async (sourceRow, bandHeight) => {
    const column = await sharp(scaled)
      .extract({ left: 0, top: sourceRow, width: innerWidth, height: edge })
      .resize(1, bandHeight, { fit: 'fill' })
      .png()
      .toBuffer();

    return sharp(column)
      .resize(innerWidth, bandHeight, { fit: 'fill' })
      .png()
      .toBuffer();
  };

  const composites = [];
  if (insetTop > 0) {
    composites.push({ input: await edgeBand(0, insetTop), top: 0, left: 0 });
  }
  composites.push({ input: scaled, top: insetTop, left: 0 });
  if (insetBottom > 0) {
    composites.push({
      input: await edgeBand(scaledHeight - edge, insetBottom),
      top: insetTop + scaledHeight,
      left: 0,
    });
  }

  return sharp({
    create: {
      width: innerWidth,
      height: bodyHeight,
      channels: 3,
      background: '#000000',
    },
  })
    .composite(composites)
    .png()
    .toBuffer();
}

async function phoneBuffer(screen, statusBar) {
  const body = screen.inset ? await insetBody(screen) : await fullScreenBody(screen);

  const ui = await sharp({
    create: {
      width: innerWidth,
      height: innerHeight,
      channels: 4,
      background: '#000000',
    },
  })
    .composite([
      { input: statusBar, top: 0, left: 0 },
      { input: body, top: statusBarHeight, left: 0 },
      {
        input: Buffer.from(`
          <svg width="${innerWidth}" height="${innerHeight}" xmlns="http://www.w3.org/2000/svg">
            <rect width="${innerWidth}" height="${innerHeight}" rx="66" fill="#FFFFFF" />
          </svg>
        `),
        blend: 'dest-in',
      },
    ])
    .png()
    .toBuffer();

  const frame = Buffer.from(`
    <svg width="${phoneWidth}" height="${phoneHeight}" xmlns="http://www.w3.org/2000/svg">
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

  return sharp({
    create: {
      width: phoneWidth,
      height: phoneHeight,
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
    { input: phone, top: phoneY, left: phoneX }
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

function validateLayout() {
  if (phoneX < 0 || phoneY < 0) {
    throw new Error('The phone frame starts outside the canvas');
  }

  if (phoneX + phoneWidth > canvasWidth || phoneY + phoneHeight > canvasHeight) {
    throw new Error(
      `The phone frame (${phoneWidth}x${phoneHeight} at ${phoneX},${phoneY}) bleeds past the `
      + `${canvasWidth}x${canvasHeight} canvas, which would slice whatever sits at the screen's edge`
    );
  }
}

async function validateOutputs() {
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
        top: phoneY + phoneFrame,
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

validateLayout();
await mkdir(outputDirectory, { recursive: true });
await mkdir(qaDirectory, { recursive: true });

const statusBar = await normalizedStatusBar();

for (const screen of screens) {
  await renderScreen(screen, statusBar);
}

await validateOutputs();
await renderContactSheet();
