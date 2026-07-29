import test from "node:test";
import assert from "node:assert/strict";
import {
  lstatSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  readlinkSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import {spawnSync} from "node:child_process";
import {tmpdir} from "node:os";
import {dirname, join, resolve} from "node:path";
import {fileURLToPath} from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const scriptPath = resolve(here, "../link-firebase-plists.sh");
const devPlist = "GoogleService-Info-Dev.plist";
const stagingPlist = "GoogleService-Info-Staging.plist";
const productionPlist = "GoogleService-Info-Production.plist";
const plistNames = [devPlist, stagingPlist, productionPlist];

test("unset CONFIGURATION never replaces a tracked plist", (t) => {
  const fixture = makeFixture(t);
  const result = runScript(fixture);

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.ok(
    lstatSync(fixture.devTarget).isFile(),
    "tracked Dev plist must remain a regular file"
  );
  assert.equal(
    readFileSync(fixture.devTarget, "utf8"),
    trackedContents(devPlist)
  );
  assert.equal(trackedStatus(fixture.projectRoot), "");

  for (const fileName of [stagingPlist, productionPlist]) {
    const target = join(fixture.targetDirectory, fileName);
    assert.ok(lstatSync(target).isSymbolicLink());
    assert.equal(readlinkSync(target), join(fixture.sourceDirectory, fileName));
  }
});

test("every tracked plist target is left untouched", (t) => {
  const fixture = makeFixture(t, {trackedFileNames: plistNames});
  const result = runScript(fixture);

  assert.equal(result.status, 0, result.stderr || result.stdout);
  for (const fileName of plistNames) {
    const target = join(fixture.targetDirectory, fileName);
    assert.ok(lstatSync(target).isFile(), `${fileName} must remain a file`);
    assert.equal(readFileSync(target, "utf8"), trackedContents(fileName));
  }
  assert.equal(trackedStatus(fixture.projectRoot), "");
});

test("tracked plist stays clean for every configuration and source state", (t) => {
  const configurations = [
    undefined,
    "Debug",
    "Staging",
    "Release",
    "Profile",
  ];
  const sourceStates = ["complete", "empty", "absent"];

  for (const configuration of configurations) {
    for (const sourceState of sourceStates) {
      const fixture = makeFixture(t, {sourceState});
      runScript(fixture, configuration);
      const context = `CONFIGURATION=${configuration ?? "unset"}, source=${sourceState}`;

      assert.ok(
        lstatSync(fixture.devTarget).isFile(),
        `tracked Dev plist must remain a file for ${context}`
      );
      assert.equal(
        readFileSync(fixture.devTarget, "utf8"),
        trackedContents(devPlist),
        `tracked Dev plist contents changed for ${context}`
      );
      assert.equal(
        trackedStatus(fixture.projectRoot),
        "",
        `tracked status changed for ${context}`
      );
    }
  }
});

test("CI can use a decoded plist without a local source directory", (t) => {
  const fixture = makeFixture(t, {sourceState: "absent"});
  const stagingTarget = join(fixture.targetDirectory, stagingPlist);
  writeFileSync(stagingTarget, "decoded-staging\n");

  const result = runScript(fixture, "Staging");

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.ok(lstatSync(stagingTarget).isFile());
  assert.equal(readFileSync(stagingTarget, "utf8"), "decoded-staging\n");
  assert.equal(trackedStatus(fixture.projectRoot), "");
});

function makeFixture(
  t,
  {sourceState = "complete", trackedFileNames = [devPlist]} = {}
) {
  const projectRoot = mkdtempSync(join(tmpdir(), "ascend-link-plists-"));
  t.after(() => rmSync(projectRoot, {recursive: true, force: true}));

  const targetDirectory = join(projectRoot, "AscendApp/App/Firebase");
  const sourceDirectory = join(projectRoot, "plist-source");
  mkdirSync(targetDirectory, {recursive: true});

  if (sourceState !== "absent") {
    mkdirSync(sourceDirectory);
  }

  if (sourceState === "complete") {
    for (const fileName of plistNames) {
      writeFileSync(join(sourceDirectory, fileName), `source-${fileName}\n`);
    }
  }

  for (const fileName of trackedFileNames) {
    writeFileSync(
      join(targetDirectory, fileName),
      trackedContents(fileName)
    );
  }

  runGit(projectRoot, ["init", "--quiet"]);
  runGit(projectRoot, [
    "add",
    ...trackedFileNames.map(
      (fileName) => `AscendApp/App/Firebase/${fileName}`
    ),
  ]);
  runGit(projectRoot, [
    "-c",
    "user.name=Ascend Tests",
    "-c",
    "user.email=tests@example.com",
    "commit",
    "--quiet",
    "-m",
    "Add tracked plist fixture",
  ]);

  return {
    devTarget: join(targetDirectory, devPlist),
    projectRoot,
    sourceDirectory,
    targetDirectory,
  };
}

function runScript(fixture, configuration) {
  const environment = {
    ...process.env,
    ASCEND_FIREBASE_PLISTS_DIR: fixture.sourceDirectory,
    HOME: join(fixture.projectRoot, "home"),
    SRCROOT: fixture.projectRoot,
  };
  delete environment.CONFIGURATION;

  if (configuration !== undefined) {
    environment.CONFIGURATION = configuration;
  }

  return spawnSync(scriptPath, {
    encoding: "utf8",
    env: environment,
  });
}

function trackedStatus(projectRoot) {
  return runGit(projectRoot, ["status", "--porcelain", "--untracked-files=no"]);
}

function trackedContents(fileName) {
  return `tracked-${fileName}\n`;
}

function runGit(projectRoot, arguments_) {
  const result = spawnSync("git", ["-C", projectRoot, ...arguments_], {
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return result.stdout.trim();
}
