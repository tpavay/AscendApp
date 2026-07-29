import { readFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import path from 'node:path';

const require = createRequire(new URL('../web/package.json', import.meta.url));
const sharp = require('sharp');

const root = process.cwd();
const assetDirectory = path.join(root, 'AppStoreAssets');
const sourceDirectory = path.join(assetDirectory, 'sources');
const outputDirectory = path.join(assetDirectory, 'screenshots/iphone-6.9-en-US');
const qaDirectory = path.join(assetDirectory, 'qa');

const canvasWidth = 1320;
const canvasHeight = 2868;
const background = '#0D1117';
const accent = '#86D30A';
const phoneWidth = 1040;
const phoneHeight = 2490;
const phoneX = 140;
const phoneY = 585;
const phoneFrame = 18;
const innerWidth = phoneWidth - phoneFrame * 2;
const innerHeight = phoneHeight - phoneFrame * 2;
const statusBarHeight = 130;
const bodyHeight = innerHeight - statusBarHeight;

const fontPath = path.join(
  root,
  'AscendApp/Resources/Fonts/Montserrat/Montserrat-Bold.ttf'
);
const fontData = await readFile(fontPath);
const fontBase64 = fontData.toString('base64');

const screens = [
  {
    filename: '01-get-fit-stair-stepper.png',
    source: path.join(sourceDirectory, '01-stair-stepper-effort.png'),
    uiSource: path.join(root, 'web/public/images/ascend-live-climb-share.png'),
    sourceStatusHeight: 130,
    lines: ['GET FIT ON THE', 'STAIR STEPPER.'],
    photo: true,
  },
  {
    filename: '02-climb-everest-stair-stepper.png',
    source: path.join(sourceDirectory, '02-everest-summit.png'),
    uiSource: path.join(sourceDirectory, 'real-ui-landmarks.png'),
    sourceStatusHeight: 155,
    lines: ['CLIMB EVEREST FROM', 'YOUR STAIR STEPPER.'],
    photo: true,
  },
  {
    filename: '03-race-real-landmarks.png',
    uiSource: path.join(root, 'web/public/images/ascend-globe-browse.jpg'),
    sourceStatusHeight: 100,
    lines: ['RACE THE WORLD UP', 'REAL LANDMARKS.'],
  },
  {
    filename: '04-race-real-climbers.png',
    uiSource: path.join(root, 'web/public/images/ascend-live-climb-leaderboard-preview.png'),
    sourceStatusHeight: 0,
    sourceBottomCrop: 230,
    sourceBottomPadding: 300,
    lines: ['RACE REAL CLIMBERS,', 'STEP FOR STEP.'],
  },
  {
    filename: '05-every-step-ranked.png',
    uiSource: path.join(root, 'web/public/images/ascend-climb-leaderboard.jpg'),
    sourceStatusHeight: 100,
    lines: ['EVERY STEP', 'RANKED.'],
  },
  {
    filename: '06-first-ascent-forever.png',
    uiSource: path.join(sourceDirectory, 'real-ui-first-ascent.png'),
    sourceStatusHeight: 155,
    lines: ['BE THE FIRST.', 'CLAIM IT FOREVER.'],
  },
  {
    filename: '07-record-book-climbing.png',
    uiSource: path.join(root, 'web/public/images/ascend-best-effort-detail.png'),
    sourceStatusHeight: 155,
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
          <stop offset="0%" stop-color="#05080C" stop-opacity="0.72" />
          <stop offset="25%" stop-color="#05080C" stop-opacity="0.46" />
          <stop offset="64%" stop-color="#05080C" stop-opacity="0.34" />
          <stop offset="100%" stop-color="#05080C" stop-opacity="0.78" />
        </linearGradient>
      </defs>
      <rect width="${canvasWidth}" height="${canvasHeight}" fill="url(#scrim)" />
      <rect x="96" y="505" width="118" height="10" rx="5" fill="${accent}" />
    </svg>
  `);
}

async function normalizedStatusBar() {
  const masterPath = path.join(sourceDirectory, 'real-ui-first-ascent.png');
  return sharp(masterPath)
    .extract({ left: 0, top: 0, width: 1206, height: 155 })
    .resize(innerWidth, statusBarHeight, { fit: 'fill' })
    .flatten({ background: '#101010' })
    .png()
    .toBuffer();
}

async function phoneBuffer(screen, statusBar) {
  const metadata = await sharp(screen.uiSource).metadata();
  const sourceStatusHeight = screen.sourceStatusHeight;
  const sourceBottomCrop = screen.sourceBottomCrop ?? 0;
  const sourceBottomPadding = screen.sourceBottomPadding ?? 0;
  const sourceBodyHeight = metadata.height - sourceStatusHeight - sourceBottomCrop;

  const croppedBody = await sharp(screen.uiSource)
    .extract({
      left: 0,
      top: sourceStatusHeight,
      width: metadata.width,
      height: sourceBodyHeight,
    })
    .flatten({ background: '#000000' })
    .png()
    .toBuffer();

  const paddedBody = sourceBottomPadding > 0
    ? await sharp({
      create: {
        width: metadata.width,
        height: sourceBodyHeight + sourceBottomPadding,
        channels: 3,
        background: '#000000',
      },
    })
      .composite([{ input: croppedBody, top: 0, left: 0 }])
      .png()
      .toBuffer()
    : croppedBody;

  const body = await sharp(paddedBody)
    .resize(innerWidth, bodyHeight, {
      fit: 'cover',
      position: 'top',
    })
    .png()
    .toBuffer();

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
    ? await sharp(screen.source)
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

const statusBar = await normalizedStatusBar();

for (const screen of screens) {
  await renderScreen(screen, statusBar);
}

await validateOutputs();
await renderContactSheet();
