# Share stat clusters

The eleven pre-formatted clusters - Hero, Rank, Row, Splits, Receipt, Minimal,
Routine, HR Hero, HR Row, Full Grid, HR Minimal - are curated Swift data in
`AscendApp/Features/ShareComposer/Models/ShareStatClusterPreset.swift`, drawn by
the same `ShareCardRenderer` that draws the recap cards.
A cluster is the arrangement done for the climber, so nobody has to lay stats
out by hand and nobody is pushed onto a recap card just to use their own photo.
This file records the rules that are settled, so a later edit does not quietly
re-litigate them; `ascend-share-composer` carries the engineering detail behind
them.
Everything here is enforced by tests; the anchor test for each rule is named
beside it.

## Plate-free by default

A cluster ships with no backing panel and holds up over a photograph on its own
text treatment.
The edit rail's existing text-background control is the way a climber adds a
panel when their photo is busy, and it is their choice rather than the default.
**A plate is never the fix for legibility.**
When small text washes out, the answer is the treatment on the run - a tighter
shadow, and a hairline outline below the size threshold - never a slab behind
it.
Anchors: `ShareStatClusterPresetTests.aClusterStartsPlateFreeAndTheExistingControlStillAddsAPlate`,
`ShareStatClusterPresetTests.addingAPanelDoesNotChangeTheTextTreatment`.

## One movable unit

A cluster is an ordinary sticker.
It drags to reposition, pinches to resize, taps to select, and deletes over the
trash zone exactly as a single-stat sticker does.
There is no second gesture path, no second model and no cluster-only editing
mode.
What the rail withholds is only what the curated arrangement already answers:
label placement, the structure sheet and per-stat toggling.
Anchors: `ShareStatClusterPresetTests.aClusterIsOneStickerThatDragsResizesAndDeletes`,
`ShareStatClusterPresetTests.aClusterReleasedOverTheTrashIsDeleted`.

## Availability follows the data

A cluster is offered when its required stats resolve, and withheld when they do
not.
Nothing branches on the session type: one catalog serves a Live Climb, a routine
and a Just Climb, and a preset is never labelled as belonging to one of them.
A workout with no heart rate is simply not offered the heart-rate clusters; a
session too short for step ranges is not offered Splits.
Anchors: `ShareStatClusterPresetTests.aLiveClimbARoutineAndAJustClimbAreEachOfferedTheClustersTheirDataSupports`,
`ShareStatClusterPresetTests.heartRateClustersAreWithheldFromAWorkoutWithoutHeartRate`,
`ShareStatClusterPresetTests.aSessionTooShortForStepRangesIsNotOfferedTheSplitsCluster`.

## Heart rate

Only two heart-rate numbers exist per session, so the clusters show stats rather
than a trace.
They read exactly `AVERAGE HR` and `MAX HR`, with no BPM suffix and no heart
glyph, and `ShareStatResolver` owns that copy so every sticker and cluster says
the same thing.
On HR Hero and HR Minimal the max sits centered beneath the average, quieter
than it.
Anchors: `ShareStatClusterPresetTests.heartRateStatsReadAverageHrAndMaxHr`,
`ShareStatClusterPresetTests.theHeartRateHeroPutsMaxBeneathAverage`.

## The wordmark

A cluster never spells or draws the Ascend wordmark.
A composed image already carries exactly one lockup - the canvas-level
`AscendWordmark`, or a recap background's own burned-in mark - and that is the
only place the brand appears, the same rule `docs/share-cards.md` keeps for the
recap cards.
Anchors: `ShareStatClusterPresetTests.noClusterSpellsOrDrawsTheWordmark`,
`ShareStatClusterPresetEvidenceTests.theCanvasWordmarkStaysTheOnlyOneOnEveryCluster`.

## Typography

Clusters are designed in three of the bundled faces only: Anton, Montserrat and
Space Mono.
That is where a cluster starts, not what it is locked to - the climber can still
switch it to any of the six faces from the edit rail, and the whole cluster
restyles together.
Labels are white at reduced opacity rather than the lime accent, which fights a
photograph.
Anchors: `ShareStatClusterPresetTests.clustersAreDesignedInAntonMontserratOrSpaceMono`,
`ShareStatClusterPresetTests.aClusterStartsInItsDesignedFaceAndTheRailCanStillChangeIt`.
