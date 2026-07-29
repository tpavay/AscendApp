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
const margin = 96;
const safeTextWidth = width - margin * 2;
const background = '#0D1117';
const accent = '#86D30A';

// Every app capture comes from a 402 x 874 point iPhone screen, so source pixels
// convert to points by dividing by this width. The 62 point top inset is what a
// captured status bar occupies before normalisation.
const devicePointWidth = 402;
const statusBarPoints = 62;

const fontPath = path.join(
  root,
  'AscendApp/Resources/Fonts/Montserrat/Montserrat-Bold.ttf'
);
const statusFontPath = path.join(
  root,
  'AscendApp/Resources/Fonts/Montserrat/Montserrat-SemiBold.ttf'
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
    capturedStatusBar: true,
  },
  {
    filename: '04-race-real-climbers.png',
    source: 'web/public/images/ascend-live-climb-leaderboard-preview.png',
    lines: ['RACE REAL CLIMBERS,', 'STEP FOR STEP.'],
    capturedStatusBar: false,
  },
  {
    filename: '05-every-step-ranked.png',
    source: 'web/public/images/ascend-climb-leaderboard.jpg',
    lines: ['EVERY STEP', 'RANKED.'],
    capturedStatusBar: true,
  },
  {
    filename: '06-first-ascent-forever.png',
    source: 'web/public/images/ascend-climb-detail.jpg',
    lines: ['BE THE FIRST.', 'CLAIMED ONCE.', 'HELD FOREVER.'],
    capturedStatusBar: true,
    badge: true,
  },
  {
    filename: '07-record-book-climbing.png',
    source: 'web/public/images/ascend-best-effort-detail.png',
    lines: ['YOUR RECORD BOOK.', "AND IT'S CLIMBING."],
    capturedStatusBar: true,
  },
];

const transformationScreens = [
  {
    filename: '01-get-fit-stair-stepper.png',
    source: path.join(sourceDirectory, '01-stair-stepper-effort.png'),
    lines: ['GET FIT ON THE', 'STAIR STEPPER.'],
    inset: {
      source: 'web/public/images/ascend-live-climb-leaderboard-preview.png',
      capturedStatusBar: false,
      // Live attempt leaderboard: header through the highlighted "You" row.
      crop: { top: 0.108, bottom: 0.456 },
    },
  },
  {
    filename: '02-climb-everest-stair-stepper.png',
    source: path.join(sourceDirectory, '02-everest-summit.png'),
    lines: ['CLIMB EVEREST FROM', 'YOUR STAIR STEPPER.'],
    inset: {
      source: 'web/public/images/ascend-climb-detail.jpg',
      capturedStatusBar: true,
      // Climb detail: landmark card footer through the completion stats.
      crop: { top: 0.5, bottom: 0.84 },
    },
  },
];

const fontData = await readFile(fontPath);
const fontBase64 = fontData.toString('base64');
const statusFontData = await readFile(statusFontPath);
const statusFontBase64 = statusFontData.toString('base64');

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
  const x = alignment === 'center' ? width / 2 : margin;
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

/**
 * Rasterises a layer and returns the bounding box of every pixel that carries
 * ink. Layout is validated against measured pixels rather than assumed metrics,
 * because the headline font, size and tracking all move the real extent.
 */
async function measureInkBounds(layer) {
  const { data, info } = await sharp(layer)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  let left = info.width;
  let right = -1;
  let top = info.height;
  let bottom = -1;

  for (let y = 0; y < info.height; y += 1) {
    const rowStart = y * info.width * info.channels;
    for (let x = 0; x < info.width; x += 1) {
      if (data[rowStart + x * info.channels + (info.channels - 1)] <= 8) {
        continue;
      }
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }

  if (right < 0) {
    throw new Error('Layer rendered no visible pixels');
  }
  return { left, right, top, bottom };
}

/**
 * Shrinks the headline until its measured ink fits inside the safe text column,
 * then hard-fails if even the smallest permitted size overflows.
 */
async function fitHeadline(lines, options) {
  const { maxFontSize, minFontSize, lineHeightRatio, label } = options;
  for (let fontSize = maxFontSize; fontSize >= minFontSize; fontSize -= 2) {
    const layer = textSvg(lines, {
      ...options,
      fontSize,
      lineHeight: Math.round(fontSize * lineHeightRatio),
    });
    const bounds = await measureInkBounds(layer);
    if (bounds.left >= margin - 8 && bounds.right <= width - margin) {
      return { layer, fontSize, bounds };
    }
  }
  throw new Error(
    `Headline does not fit the ${safeTextWidth}px safe column at ${minFontSize}px: ${label}`
  );
}

function accentRuleSvg(y) {
  return Buffer.from(`
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <rect x="${margin}" y="${y}" width="118" height="10" rx="5" fill="${accent}" />
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

/**
 * One uniform marketing status bar for every screen: 9:41, full signal, Wi-Fi
 * and a full battery, drawn at the proportions of the captured device.
 */
function statusBarSvg(barWidth, barHeight) {
  const unit = barWidth / devicePointWidth;
  const centerY = 30 * unit;
  const barBottom = centerY + 5.5 * unit;
  const signalBars = [4, 6, 8.5, 11]
    .map((barPointHeight, index) => {
      const barX = 286 * unit + index * 6.4 * unit;
      const drawHeight = barPointHeight * unit;
      return `<rect x="${barX}" y="${barBottom - drawHeight}" width="${4.2 * unit}" height="${drawHeight}" rx="${1.4 * unit}" fill="#FFFFFF" />`;
    })
    .join('');

  const wifiX = 318 * unit;
  const wifiScale = unit;
  const wifi = `
    <g transform="translate(${wifiX} ${centerY - 5 * wifiScale}) scale(${wifiScale})">
      <path d="M0.6 4.2 A 13 13 0 0 1 17.4 4.2" fill="none" stroke="#FFFFFF" stroke-width="2.5" stroke-linecap="round" />
      <path d="M4.2 8.2 A 8 8 0 0 1 13.8 8.2" fill="none" stroke="#FFFFFF" stroke-width="2.5" stroke-linecap="round" />
      <circle cx="9" cy="12.6" r="1.9" fill="#FFFFFF" />
    </g>
  `;

  const batteryX = 342 * unit;
  const batteryWidth = 27 * unit;
  const batteryHeight = 13 * unit;
  const batteryY = centerY - batteryHeight / 2;
  const battery = `
    <rect x="${batteryX}" y="${batteryY}" width="${batteryWidth}" height="${batteryHeight}" rx="${4 * unit}" fill="none" stroke="#FFFFFF" stroke-opacity="0.45" stroke-width="${1.3 * unit}" />
    <rect x="${batteryX + 2 * unit}" y="${batteryY + 2 * unit}" width="${batteryWidth - 4 * unit}" height="${batteryHeight - 4 * unit}" rx="${2 * unit}" fill="#FFFFFF" />
    <path d="M ${batteryX + batteryWidth + 1.4 * unit} ${centerY - 3 * unit} a ${3 * unit} ${3 * unit} 0 0 1 0 ${6 * unit} z" fill="#FFFFFF" fill-opacity="0.45" />
  `;

  return Buffer.from(`
    <svg width="${Math.round(barWidth)}" height="${Math.round(barHeight)}" xmlns="http://www.w3.org/2000/svg">
      <style>
        @font-face {
          font-family: AscendStatus;
          src: url(data:font/ttf;base64,${statusFontBase64});
        }
        .clock {
          fill: #FFFFFF;
          font-family: AscendStatus, sans-serif;
          font-size: ${17 * unit}px;
          font-weight: 600;
        }
      </style>
      <rect width="100%" height="100%" fill="#000000" />
      <text class="clock" x="${67 * unit}" y="${centerY}" text-anchor="middle" dominant-baseline="central">9:41</text>
      ${signalBars}
      ${wifi}
      ${battery}
    </svg>
  `);
}

/**
 * Scales an app capture to completely fill a screen box - never padded, so the
 * renderer can no longer letterbox a screen with a black band. The aspect guard
 * keeps the resulting edge crop small enough that no UI row is sliced away.
 */
async function captureWindow(sourcePath, { capturedStatusBar, crop }) {
  const pipeline = sharp(sourcePath).flatten({ background: '#000000' });
  const metadata = await pipeline.metadata();

  const cropTop = crop
    ? Math.round(metadata.height * crop.top)
    : (capturedStatusBar ? Math.round((metadata.width / devicePointWidth) * statusBarPoints) : 0);
  const cropBottom = crop ? Math.round(metadata.height * (1 - crop.bottom)) : 0;
  const cropHeight = metadata.height - cropTop - cropBottom;

  if (cropHeight <= 0) {
    throw new Error(`Capture crop leaves no content: ${sourcePath}`);
  }

  return { pipeline, cropTop, cropWidth: metadata.width, cropHeight };
}

async function fillScreenBox(sourcePath, { boxWidth, boxHeight, capturedStatusBar, crop }) {
  const { pipeline, cropTop, cropWidth, cropHeight } = await captureWindow(sourcePath, {
    capturedStatusBar,
    crop,
  });

  const sourceAspect = cropWidth / cropHeight;
  const boxAspect = boxWidth / boxHeight;
  const edgeCrop = Math.abs(1 - sourceAspect / boxAspect);
  if (edgeCrop > 0.14) {
    throw new Error(
      `Capture aspect ${sourceAspect.toFixed(3)} is too far from the ${boxAspect.toFixed(3)} screen box `
      + `(${Math.round(edgeCrop * 100)}% would be cropped away): ${sourcePath}`
    );
  }

  return pipeline
    .extract({ left: 0, top: cropTop, width: cropWidth, height: cropHeight })
    .resize(Math.round(boxWidth), Math.round(boxHeight), {
      fit: 'cover',
      position: 'top',
    })
    .png()
    .toBuffer();
}

/**
 * Builds the framed app screen: normalised status bar band on top, capture
 * filling everything beneath it.
 */
async function renderFramedScreen(screen, { boxWidth, boxHeight }) {
  const statusBarHeight = Math.round((boxWidth / devicePointWidth) * statusBarPoints);
  const capture = await fillScreenBox(path.join(root, screen.source), {
    boxWidth,
    boxHeight: boxHeight - statusBarHeight,
    capturedStatusBar: screen.capturedStatusBar,
    crop: screen.crop,
  });

  return sharp({
    create: {
      width: Math.round(boxWidth),
      height: Math.round(boxHeight),
      channels: 4,
      background: '#000000',
    },
  })
    .composite([
      { input: capture, top: statusBarHeight, left: 0 },
      { input: statusBarSvg(boxWidth, statusBarHeight), top: 0, left: 0 },
    ])
    .png()
    .toBuffer();
}

function insetPanelMaskSvg(panelWidth, panelHeight, radius) {
  return Buffer.from(`
    <svg width="${panelWidth}" height="${panelHeight}" xmlns="http://www.w3.org/2000/svg">
      <rect width="${panelWidth}" height="${panelHeight}" rx="${radius}" fill="#FFFFFF" />
    </svg>
  `);
}

function insetPanelBorderSvg(panelWidth, panelHeight, radius) {
  return Buffer.from(`
    <svg width="${panelWidth}" height="${panelHeight}" xmlns="http://www.w3.org/2000/svg">
      <rect x="1.5" y="1.5" width="${panelWidth - 3}" height="${panelHeight - 3}" rx="${radius - 1.5}"
        fill="none" stroke="${accent}" stroke-opacity="0.55" stroke-width="3" />
    </svg>
  `);
}

/**
 * Guideline 2.3.3: the transformation screens keep their photographic treatment
 * but carry a genuine Ascend app surface so both show the app in use.
 */
async function renderAppSurfaceInset(inset, { panelWidth }) {
  const radius = 44;
  const sourcePath = path.join(root, inset.source);
  const window = await captureWindow(sourcePath, {
    capturedStatusBar: inset.capturedStatusBar,
    crop: inset.crop,
  });
  const panelHeight = Math.round(panelWidth * (window.cropHeight / window.cropWidth));

  const surface = await fillScreenBox(sourcePath, {
    boxWidth: panelWidth,
    boxHeight: panelHeight,
    capturedStatusBar: inset.capturedStatusBar,
    crop: inset.crop,
  });

  const panel = await sharp(surface)
    .composite([
      { input: insetPanelMaskSvg(panelWidth, panelHeight, radius), blend: 'dest-in' },
      { input: insetPanelBorderSvg(panelWidth, panelHeight, radius), blend: 'over' },
    ])
    .png()
    .toBuffer();

  return { panel, panelHeight };
}

async function renderTransformation(screen) {
  const panelWidth = 1000;
  const panelBottom = 2140;
  const panelLeft = Math.round((width - panelWidth) / 2);

  const headline = await fitHeadline(screen.lines, {
    top: 2408,
    maxFontSize: 112,
    minFontSize: 72,
    lineHeightRatio: 128 / 112,
    label: screen.filename,
  });

  const { panel, panelHeight } = await renderAppSurfaceInset(screen.inset, { panelWidth });

  const outputPath = path.join(outputDirectory, screen.filename);
  await sharp(screen.source)
    .resize(width, height, { fit: 'cover', position: 'centre' })
    .composite([
      { input: transformationScrimSvg(), top: 0, left: 0 },
      { input: panel, top: panelBottom - panelHeight, left: panelLeft },
      { input: accentRuleSvg(2262), top: 0, left: 0 },
      { input: headline.layer, top: 0, left: 0 },
    ])
    .flatten({ background })
    .removeAlpha()
    .png({ compressionLevel: 9 })
    .withMetadata({ density: 72 })
    .toFile(outputPath);

  return headline;
}

async function renderFeature(screen) {
  const deviceX = 145;
  const deviceY = 610;
  const screenX = deviceX + 15;
  const screenY = deviceY + 15;
  const screenWidth = 1000;
  const screenHeight = height - screenY;

  const framedScreen = await renderFramedScreen(screen, {
    boxWidth: screenWidth,
    boxHeight: screenHeight,
  });

  const headline = await fitHeadline(screen.lines, {
    top: 190,
    maxFontSize: screen.badge ? 91 : 104,
    minFontSize: 68,
    lineHeightRatio: screen.badge ? 110 / 91 : 118 / 104,
    label: screen.filename,
  });

  const composites = [
    { input: accentRuleSvg(490), top: 0, left: 0 },
    { input: headline.layer, top: 0, left: 0 },
    { input: framedScreen, top: screenY, left: screenX },
    {
      input: path.join(sourceDirectory, 'device-frame.png'),
      top: deviceY,
      left: deviceX,
    },
  ];

  if (screen.badge) {
    // Anchored to the landmark card's upper right so the card's own
    // "Empire State Building / New York, USA" label stays fully readable.
    const badge = await sharp(badgePath)
      .resize(540, 540, { fit: 'contain' })
      .png()
      .toBuffer();
    composites.push({ input: badge, top: 1005, left: 645 });
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

  return headline;
}

await mkdir(outputDirectory, { recursive: true });

const renderedHeadlines = new Map();

for (const screen of transformationScreens) {
  renderedHeadlines.set(screen.filename, await renderTransformation(screen));
}

for (const screen of featureScreens) {
  renderedHeadlines.set(screen.filename, await renderFeature(screen));
}

for (const screen of [...transformationScreens, ...featureScreens]) {
  const outputPath = path.join(outputDirectory, screen.filename);
  const metadata = await sharp(outputPath).metadata();
  if (
    metadata.width !== width
    || metadata.height !== height
    || metadata.space?.toLowerCase() !== 'srgb'
    || metadata.hasAlpha
  ) {
    throw new Error(`Invalid App Store screenshot output: ${screen.filename}`);
  }

  const headline = renderedHeadlines.get(screen.filename);
  if (headline.bounds.right > width - margin || headline.bounds.left < margin - 8) {
    throw new Error(`Headline overflows the safe column: ${screen.filename}`);
  }

  console.log(
    `${screen.filename}: ${metadata.width}x${metadata.height}, ${metadata.space}, alpha=${metadata.hasAlpha}, `
    + `headline ${headline.fontSize}px ending at x=${headline.bounds.right}`
  );
}

await writeContactSheet([...transformationScreens, ...featureScreens]);

async function writeContactSheet(screens) {
  const columns = 4;
  const tileWidth = 280;
  const tileHeight = Math.round(tileWidth * (height / width));
  const gap = 24;
  const padding = 24;
  const rows = Math.ceil(screens.length / columns);
  const sheetWidth = padding * 2 + columns * tileWidth + (columns - 1) * gap;
  const sheetHeight = padding * 2 + rows * tileHeight + (rows - 1) * gap;

  const tiles = await Promise.all(screens.map(async (screen, index) => ({
    input: await sharp(path.join(outputDirectory, screen.filename))
      .resize(tileWidth, tileHeight)
      .png()
      .toBuffer(),
    left: padding + (index % columns) * (tileWidth + gap),
    top: padding + Math.floor(index / columns) * (tileHeight + gap),
  })));

  const sheetPath = path.join(taskDirectory, 'qa/app-store-contact-sheet.png');
  await mkdir(path.dirname(sheetPath), { recursive: true });
  await sharp({
    create: { width: sheetWidth, height: sheetHeight, channels: 3, background },
  })
    .composite(tiles)
    .flatten({ background })
    .removeAlpha()
    .png({ compressionLevel: 9 })
    .toFile(sheetPath);

  console.log(`qa/app-store-contact-sheet.png: ${sheetWidth}x${sheetHeight}, ${screens.length} screens`);
}
