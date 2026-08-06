import assert from "node:assert/strict";
import {readdir} from "node:fs/promises";
import {readFile} from "node:fs/promises";
import {join} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";

import {appBuildConfigurations, settingValue} from "../lib/monetization-build-settings.mjs";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const projectPath = join(repositoryRoot, "AscendApp.xcodeproj/project.pbxproj");
const infoPlistPath = join(repositoryRoot, "AscendApp/Info.plist");

// App Review reads this string on the permission alert, so it has to name every
// feature that actually reads the sensor and nothing that doesn't (#322).
const MAXIMUM_USAGE_DESCRIPTION_LENGTH = 140;

// The audited Core Motion surface: one CMHeadphoneMotionManager feed, its sample
// type, and the readiness probe. Any other file reaching for Core Motion means a
// second sensor consumer exists and the usage string no longer describes it.
const CORE_MOTION_SOURCE_PATHS = [
  "AscendApp/Features/Climbs/Services/HeadphoneMotionReadinessService.swift",
  "AscendApp/Shared/Services/HeadphoneMotion/HeadphoneMotionSample.swift",
  "AscendApp/Shared/Services/HeadphoneMotion/HeadphoneMotionSessionService.swift"
];

// Every Core Motion type that starts a sensor feed. CMHeadphoneMotionManager is
// the only one Ascend is allowed to use; the rest would each add a feature the
// usage string does not mention.
const CORE_MOTION_READER_TYPES = [
  "CMAltimeter",
  "CMBatchedSensorManager",
  "CMFallDetectionManager",
  "CMHeadphoneMotionManager",
  "CMHighFrequencyHeartRateSampler",
  "CMMotionActivityManager",
  "CMMotionManager",
  "CMOdometer",
  "CMPedometer",
  "CMSensorRecorder",
  "CMWaterSubmersionManager"
];

// The two view models that drive the one headphone-motion feed, and the feature
// each of them puts in front of a climber.
const MOTION_FEATURE_CONSUMERS = [
  {
    path: "AscendApp/Features/Climbs/ViewModels/LiveClimbSessionViewModel.swift",
    features: ["Live Climbs", "Just Climb"]
  },
  {
    path: "AscendApp/Features/Routines/ViewModels/ActiveRoutineViewModel.swift",
    features: ["routines"]
  }
];

async function swiftSources() {
  const paths = (await readdir(join(repositoryRoot, "AscendApp"), {recursive: true}))
    .filter((path) => path.endsWith(".swift"))
    .map((path) => `AscendApp/${path}`);

  return Promise.all(
    paths.map(async (path) => [path, await readFile(join(repositoryRoot, path), "utf8")])
  );
}

function infoPlistString(plist, key) {
  const match = plist.match(
    new RegExp(`<key>${key}</key>\\s*\\n\\s*<string>([^<]*)</string>`)
  );
  return match ? match[1] : null;
}

test("the motion usage description is identical everywhere iOS can read it", async () => {
  const plist = await readFile(infoPlistPath, "utf8");
  const project = await readFile(projectPath, "utf8");
  const sourceValue = infoPlistString(plist, "NSMotionUsageDescription");

  assert.notEqual(sourceValue, null, "AscendApp/Info.plist declares no NSMotionUsageDescription");

  const configurations = appBuildConfigurations(project);
  assert.deepEqual([...configurations.keys()].sort(), ["Debug", "Release", "Staging"]);

  for (const [name, {buildSettings}] of configurations) {
    assert.equal(
      settingValue(buildSettings, "INFOPLIST_KEY_NSMotionUsageDescription"),
      sourceValue,
      `The ${name} configuration's motion usage description differs from AscendApp/Info.plist`
    );
  }
});

test("the motion usage description stays plain, short, and feature-named", async () => {
  const plist = await readFile(infoPlistPath, "utf8");
  const value = infoPlistString(plist, "NSMotionUsageDescription");

  assert.ok(
    value.length <= MAXIMUM_USAGE_DESCRIPTION_LENGTH,
    `The motion usage description is ${value.length} characters, over the ` +
      `${MAXIMUM_USAGE_DESCRIPTION_LENGTH} the alert can show without truncating: "${value}"`
  );

  for (const phrase of ["headphones", "steps", "Live Climbs", "Just Climb", "routines"]) {
    assert.ok(
      value.includes(phrase),
      `The motion usage description omits "${phrase}": "${value}"`
    );
  }

  assert.doesNotMatch(
    value,
    /CMHeadphoneMotionManager|Core ?Motion|accelerometer|API/i,
    `The motion usage description must stay plain English: "${value}"`
  );
});

test("the only Core Motion reader in the app is the headphone motion feed", async () => {
  const sources = await swiftSources();

  const importers = sources
    .filter(([, source]) => /^@?\w*\s*import CoreMotion$/m.test(source))
    .map(([path]) => path)
    .sort();

  assert.deepEqual(
    importers,
    [...CORE_MOTION_SOURCE_PATHS].sort(),
    "A new file reads Core Motion; NSMotionUsageDescription has to name what it powers"
  );

  const readerPattern = new RegExp(`\\b(${CORE_MOTION_READER_TYPES.join("|")})\\b`, "g");

  for (const [path, source] of sources) {
    const readers = [...new Set([...source.matchAll(readerPattern)].map(([, type]) => type))];
    if (readers.length === 0) {
      continue;
    }

    assert.deepEqual(
      readers,
      ["CMHeadphoneMotionManager"],
      `${path} starts a Core Motion feed the usage description does not describe: ${readers}`
    );
  }
});

test("every feature the motion usage description names still reads the headphone feed", async () => {
  const plist = await readFile(infoPlistPath, "utf8");
  const value = infoPlistString(plist, "NSMotionUsageDescription");

  for (const {path, features} of MOTION_FEATURE_CONSUMERS) {
    const source = await readFile(join(repositoryRoot, path), "utf8");

    assert.match(
      source,
      /HeadphoneMotionSessionServic(e|ing)/,
      `${path} no longer drives the headphone motion feed, so the usage description overstates it`
    );

    for (const feature of features) {
      assert.ok(
        value.includes(feature),
        `${path} reads headphone motion for ${feature}, which the usage description omits`
      );
    }
  }
});
