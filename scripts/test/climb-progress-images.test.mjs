import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {fileURLToPath} from "node:url";

import {
  contentTypeForPath,
  pngDimensions,
  progressObjectPath,
} from "../sync-climb-images.mjs";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));

function read(path) {
  return readFileSync(`${repositoryRoot}/${path}`, "utf8");
}

function catalogClimbs() {
  const catalog = JSON.parse(read("web/public/climbs/catalog-v1.json"));
  return catalog.climbs ?? catalog;
}

/**
 * The progress cut-outs are content: every live climb's catalog entry names its
 * own image and describes it, and the tool that publishes the images reads the
 * same entry the app does.
 */
test("every available climb names a progress cut-out in its own folder, described in full", () => {
  const available = catalogClimbs().filter((climb) => climb.releaseState === "available");
  assert.ok(available.length > 0);
  for (const climb of available) {
    const artwork = climb.progressArtwork;
    assert.ok(artwork, `${climb.id} has no progressArtwork`);
    assert.equal(progressObjectPath(climb), `climb-images/${climb.id}/progress/v1.png`, climb.id);
    assert.match(artwork.sha256, /^[0-9a-f]{64}$/, `${climb.id} sha256`);
    const bounds = artwork.visibleBoundsPixels;
    assert.ok(bounds.left >= 0 && bounds.top >= 0, climb.id);
    assert.ok(bounds.right <= artwork.canvasWidth && bounds.bottom <= artwork.canvasHeight, climb.id);
    assert.ok(artwork.progressTopY < artwork.progressBottomY, climb.id);
    if (artwork.layout !== undefined) {
      assert.ok(["side-by-side", "stacked"].includes(artwork.layout), `${climb.id} layout pin`);
    }
  }
});

test("the tool refuses a cut-out outside the climb's own folder", () => {
  assert.equal(progressObjectPath({id: "a", progressArtwork: {path: "climb-images/b/progress/v1.png"}}), null);
  assert.equal(progressObjectPath({id: "a", progressArtwork: {path: "climb-images/a/../b/v1.png"}}), null);
  assert.equal(progressObjectPath({id: "a"}), null);
  assert.equal(
    progressObjectPath({id: "a", progressArtwork: {path: "climb-images/a/progress/v2.png"}}),
    "climb-images/a/progress/v2.png"
  );
});

test("copies keep a cut-out labelled PNG and the photo set labelled HEIC", () => {
  assert.equal(contentTypeForPath("climb-images/a/progress/v1.png"), "image/png");
  assert.equal(contentTypeForPath("climb-images/a/v1/hero.heic"), "image/heic");
});

test("a PNG's canvas size is read from its header, and anything else is refused", () => {
  const png = readFileSync(`${repositoryRoot}/TestFixtures/climb-progress/charminar-progress.png`);
  assert.deepEqual(pngDimensions(png), {width: 1088, height: 1445});
  assert.equal(pngDimensions(Buffer.from("not a png at all, just some text")), null);
});
