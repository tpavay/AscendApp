import { readFile } from 'node:fs/promises';
import { mkdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';

const require = createRequire(new URL('../../web/package.json', import.meta.url));
const sharp = require('sharp');

const root = process.cwd();
const taskDirectory = path.join(root, 'data/ascend-support-page-and-product-page-package');
const sourceDirectory = path.join(taskDirectory, 'screenshot-sources');
const outputDirectory = path.join(taskDirectory, 'screenshots/iphone-6.9-en-US');

const width = 1320;
const height = 2868;
const background = '#0D1117';
const accent = '#86D30A';
const fontPath = path.join(
  root,
  'AscendApp/Resources/Fonts/Montserrat/Montserrat-Bold.ttf'
);
const badgePath = path.join(
  root,
  'AscendApp/Resources/Assets.xcassets/Images/FirstAscentBadgeDetailed.imageset/FirstAscentBadgeDetailed.png'
);

const featureScreens = [
  {
    filename: '03-race-real-landmarks.png',
    source: 'web/public/images/ascend-globe-browse.jpg',
    lines: ['RACE THE WORLD UP', 'REAL LANDMARKS.'],
  },
  {
    filename: '04-race-real-climbers.png',
    source: 'web/public/images/ascend-live-climb-leaderboard-preview.png',
    lines: ['RACE REAL CLIMBERS,', 'STEP FOR STEP.'],
  },
  {
    filename: '05-every-step-ranked.png',
    source: 'web/public/images/ascend-climb-leaderboard.jpg',
    lines: ['EVERY STEP', 'RANKED.'],
  },
  {
    filename: '06-first-ascent-forever.png',
    source: 'web/public/images/ascend-climb-detail.jpg',
    lines: ['BE THE FIRST.', 'CLAIMED ONCE.', 'HELD FOREVER.'],
    badge: true,
  },
  {
    filename: '07-record-book-climbing.png',
    source: 'web/public/images/ascend-best-effort-detail.png',
    lines: ['YOUR RECORD BOOK.', "AND IT'S CLIMBING."],
  },
];

const transformationScreens = [
  {
    filename: '01-get-fit-stair-stepper.png',
    source: path.join(sourceDirectory, '01-stair-stepper-effort.png'),
    lines: ['GET FIT ON THE', 'STAIR STEPPER.'],
  },
  {
    filename: '02-climb-everest-stair-stepper.png',
    source: path.join(sourceDirectory, '02-everest-summit.png'),
    lines: ['CLIMB EVEREST FROM', 'YOUR STAIR STEPPER.'],
  },
];

const fontData = await readFile(fontPath);
const fontBase64 = fontData.toString('base64');

function escapeXml(value) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

function textSvg(lines, { top, fontSize, lineHeight, alignment = 'left' }) {
  const anchor = alignment === 'center' ? 'middle' : 'start';
  const x = alignment === 'center' ? width / 2 : 96;
  const textLines = lines
    .map((line, index) => (
      `<text x="${x}" y="${top + index * lineHeight}" text-anchor="${anchor}">${escapeXml(line)}</text>`
    ))
    .join('');

  return Buffer.from(`
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <style>
        @font-face {
          font-family: AscendMontserrat;
          src: url(data:font/ttf;base64,${fontBase64});
        }
        text {
          fill: #FFFFFF;
          font-family: AscendMontserrat, sans-serif;
          font-size: ${fontSize}px;
          font-weight: 700;
          letter-spacing: -2px;
        }
      </style>
      ${textLines}
    </svg>
  `);
}

function accentRuleSvg(y) {
  return Buffer.from(`
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <rect x="96" y="${y}" width="118" height="10" rx="5" fill="${accent}" />
    </svg>
  `);
}

function transformationScrimSvg() {
  return Buffer.from(`
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="scrim" x1="0" y1="0" x2="0" y2="1">
          <stop offset="42%" stop-color="#05080C" stop-opacity="0" />
          <stop offset="70%" stop-color="#05080C" stop-opacity="0.52" />
          <stop offset="100%" stop-color="#05080C" stop-opacity="0.96" />
        </linearGradient>
      </defs>
      <rect width="${width}" height="${height}" fill="url(#scrim)" />
    </svg>
  `);
}

async function renderTransformation(screen) {
  const outputPath = path.join(outputDirectory, screen.filename);
  await sharp(screen.source)
    .resize(width, height, { fit: 'cover', position: 'centre' })
    .composite([
      { input: transformationScrimSvg(), top: 0, left: 0 },
      { input: accentRuleSvg(2262), top: 0, left: 0 },
      {
        input: textSvg(screen.lines, {
          top: 2408,
          fontSize: 112,
          lineHeight: 128,
        }),
        top: 0,
        left: 0,
      },
    ])
    .flatten({ background })
    .removeAlpha()
    .png({ compressionLevel: 9 })
    .withMetadata({ density: 72 })
    .toFile(outputPath);
}

async function renderFeature(screen) {
  const deviceX = 145;
  const deviceY = 610;
  const screenX = deviceX + 15;
  const screenY = deviceY + 15;
  const screenWidth = 1000;
  const screenHeight = height - screenY + 260;

  const capture = await sharp(path.join(root, screen.source))
    .flatten({ background: '#000000' })
    .resize(screenWidth, screenHeight, {
      fit: 'contain',
      position: 'top',
      background: '#000000',
    })
    .png()
    .toBuffer();

  const composites = [
    { input: accentRuleSvg(490), top: 0, left: 0 },
    {
      input: textSvg(screen.lines, {
        top: 190,
        fontSize: screen.badge ? 91 : 104,
        lineHeight: screen.badge ? 110 : 118,
      }),
      top: 0,
      left: 0,
    },
    { input: capture, top: screenY, left: screenX },
    {
      input: path.join(sourceDirectory, 'device-frame.png'),
      top: deviceY,
      left: deviceX,
    },
  ];

  if (screen.badge) {
    const badge = await sharp(badgePath)
      .resize(720, 720, { fit: 'contain' })
      .png()
      .toBuffer();
    composites.push({ input: badge, top: 1410, left: 300 });
  }

  const outputPath = path.join(outputDirectory, screen.filename);
  await sharp({
    create: {
      width,
      height,
      channels: 3,
      background,
    },
  })
    .composite(composites)
    .flatten({ background })
    .removeAlpha()
    .png({ compressionLevel: 9 })
    .withMetadata({ density: 72 })
    .toFile(outputPath);
}

await mkdir(outputDirectory, { recursive: true });

for (const screen of transformationScreens) {
  await renderTransformation(screen);
}

for (const screen of featureScreens) {
  await renderFeature(screen);
}

for (const screen of [...transformationScreens, ...featureScreens]) {
  const outputPath = path.join(outputDirectory, screen.filename);
  const metadata = await sharp(outputPath).metadata();
  if (
    metadata.width !== width
    || metadata.height !== height
    || metadata.space.toLowerCase() !== 'srgb'
    || metadata.hasAlpha
  ) {
    throw new Error(`Invalid App Store screenshot output: ${screen.filename}`);
  }
  console.log(`${screen.filename}: ${metadata.width}x${metadata.height}, ${metadata.space}, alpha=${metadata.hasAlpha}`);
}
