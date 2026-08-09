---
name: live-climb-content
description: Use when adding, editing, releasing, or validating Ascend Live Climb catalog content, climb drops, landmark metadata, release states, climb images, or hosted climb catalog deployment.
---

# Live Climb Content

Use this skill for any request to add, change, release, hide, or validate Live Climbs.

This is harness-neutral. If the current AI tool does not support skills, paste or reference this file and follow it as the source-of-truth workflow.

## Source Of Truth

- Remote catalog: `web/public/climbs/catalog-v1.json`
- Remote manifest: `web/public/climbs/manifest.json`
- Bundled fallback catalog: `AscendApp/Features/Climbs/Resources/climbs.json`
- Model schema: `AscendApp/Features/Climbs/Models/Climb.swift`
- Release states: `AscendApp/Features/Climbs/Models/ClimbReleaseState.swift`
- Tier thresholds: `AscendApp/Features/Climbs/Models/ClimbTier.swift`
- Image paths: `AscendApp/Features/Climbs/Repositories/FirebaseClimbImageRepository.swift`
- Optional dev replay fixtures: `scripts/seed-live-replay-leaderboards.mjs`

Keep `web/public/climbs/catalog-v1.json` and `AscendApp/Features/Climbs/Resources/climbs.json` in sync unless the user explicitly wants a remote-only experiment. The bundled file is the metadata fallback before remote content is fetched.

## Catalog Fields

Each climb must include:

```json
{
  "id": "kebab-case-stable-id",
  "name": "Landmark Name",
  "city": "City",
  "country": "Country",
  "continent": "Continent",
  "latitude": 0,
  "longitude": 0,
  "totalHeightMeters": 0,
  "totalHeightFeet": 0,
  "realClimbableHeightMeters": null,
  "realClimbableHeightFeet": null,
  "totalSteps": 0,
  "realStairCount": null,
  "calculatedFloors": 0,
  "category": "tower",
  "tier": "bronze",
  "tags": ["short", "specific", "lowercase"],
  "funFact": "One concise sourced fact.",
  "sourceURL": "https://example.com/source",
  "releaseState": "comingSoon"
}
```

Optional fields:

```json
"imageSetVersion": 1,
"commonName": "John Hancock Center"
```

If absent, the app defaults `imageSetVersion` to `1`.

`commonName` is the name a city still uses for a renamed landmark. It never replaces `name`, which stays the official one, and no surface renders it yet. Populate it only with a citable source recorded in `docs/climb-coordinate-and-name-sources.md`, which is also where a climb's coordinate provenance goes.

### Category is free-form, but the app branches on it

Reuse an existing `category` where one fits. Introducing a new value is a code change as well as a data change, because three places switch on the string and each has a silent default:

- `ClimbArtworkView` picks the SF Symbol placeholder shown until Storage artwork exists - unlisted falls back to `building.2.fill`.
- `ClimbCameraFraming.isNatural` decides whether the globe and flyover frame the climb as terrain (pulled far back) or as a structure - unlisted is framed as a structure.
- `Climb.globeCameraDistance` picks the distance band for non-natural categories - unlisted gets the tower band.

`staircase` is classified natural because the one climb using it is an open hillside stair whose route *is* the terrain, so structure framing would crop it.

## Release States

- `available`: visible and startable. First Ascent / leaderboard surfaces may activate.
- `comingSoon`: visible teaser, not startable.
- `hidden`: not visible. Use for planned content that should not tease.
- `disabled`: not visible. Use for retired or blocked content.

If images are missing or uncertain, default new climbs to `comingSoon` or `hidden`, not `available`.

## Tier Rules

Set `tier` from the climb's reference step count:

- `common`: under 300
- `bronze`: 300-599
- `silver`: 600-1,199
- `gold`: 1,200-2,099
- `diamond`: 2,100-3,499
- `epic`: 3,500-5,999
- `legendary`: 6,000-11,999
- `mythic`: 12,000+

The app uses `realStairCount ?? totalSteps` as the reference step count.

## Step Counts Are Race Distances

`totalSteps` is the architectural-height derivation, `round(totalHeightMeters * 5.5)`. It is a height fact, never a route: for a tower it converts an antenna spire nobody climbs, and for a mountain it converts elevation above sea level. Leave it alone.

`realStairCount` is the verified count of the steps people actually climb, and it is what the app races and ranks on. Correcting a distance means populating `realStairCount`, never rewriting `totalSteps`.

Every populated `realStairCount` needs a citable primary source recorded in `docs/climb-real-stair-counts.md` - the venue owner, the event organiser, the custodian body, or the Towerrunning World Association race record. Where published figures disagree, record the disagreement there rather than silently picking one. Where no defensible figure exists, leave `realStairCount: null`; a height-derived guess shipped as a race distance is worse than an admitted gap.

`realClimbableHeightMeters` / `realClimbableHeightFeet` follow the same rule for the climbed vertical, and feed `referenceHeightMeters`.

`calculatedFloors` renders as FLOORS beside STEPS on climb detail, so it answers for the same route. Set it from the route's published storey count where a source states one, and from `round(referenceStepCount / 19.8)` otherwise - never from `totalHeightMeters`, which is what put 876 floors next to Monserrate's 1,605 steps. A published *flight* or *landing* count is not a storey count and is not shipped as one unless a second independent source restates that same figure as storeys; otherwise record it in `docs/climb-real-stair-counts.md` and derive instead. That file states the rule in full and names the one climb that clears the bar.

Changing a reference step count invalidates every recorded time on that climb, because it changes the distance raced. `AscendAppTests/ClimbCatalogStairCountTests.swift` enforces that both catalogue files stay byte-identical, that every `tier` matches its reference count, that `totalSteps` stays height-derived, and that every climb's steps-per-floor stays plausible.

## Image Assets

The app fetches Firebase Storage images from:

```txt
climb-images/{climbId}/v{imageSetVersion}/hero.heic
climb-images/{climbId}/v{imageSetVersion}/card.heic
climb-images/{climbId}/v{imageSetVersion}/thumb.heic
```

It also checks legacy fallback paths:

```txt
climb-images/{climbId}/hero.heic
climb-images/{climbId}/card.heic
climb-images/{climbId}/thumb.heic
```

If replacing images for an existing climb, increment `imageSetVersion` in both catalog files so clients fetch the new cached path.

### Image tooling (`scripts/sync-climb-images.mjs`)

Images are per-environment Storage content — publishing a catalog does NOT move images. Use this tool to keep buckets in sync with the catalog:

```bash
# Check a bucket against the catalog (exits 1 if an available climb lacks images)
node scripts/sync-climb-images.mjs audit --project staging

# Upload new artwork (folder must contain hero.heic, card.heic, thumb.heic)
node scripts/sync-climb-images.mjs upload --project dev --climb <id> --dir <folder> --image-set-version 1

# Propagate images between environments (dry-run first)
node scripts/sync-climb-images.mjs sync --from staging --to production --dry-run
node scripts/sync-climb-images.mjs sync --from staging --to production --confirm-production
```

Writes to production require `--confirm-production`. Sync copies only missing/changed objects (md5 compare) and never deletes. When adding a climb: upload images to dev/staging first, validate in-app, then sync to production alongside (or before) the catalog deploy that references them.

## Workflow

1. Read the existing catalog entries to match style, order, tags, and category naming.
2. Research the landmark from reliable public sources. Use exact coordinates, height, city, country, and a source URL.
3. Add or edit the climb entry in `web/public/climbs/catalog-v1.json`.
4. Mirror the same metadata change in `AscendApp/Features/Climbs/Resources/climbs.json`.
5. Increment `catalogVersion` in `web/public/climbs/manifest.json`.
6. Update `updatedAt` in `web/public/climbs/manifest.json` to a UTC ISO timestamp.
7. Update `featuredClimbId` only if the user asked to feature the new climb.
8. If dev replay fixtures should include the climb, add it to `ACTIVE_CLIMBS` or `WARM_CLIMBS` in `scripts/seed-live-replay-leaderboards.mjs`.
   To seed the climb with an open First Ascent slot instead of synthetic traffic, use `FIRST_ASCENT_OPEN_CLIMBS` in the same file and follow the constraints documented on that list.
9. Validate JSON and schema by decoding both catalog files.
10. Build web before deploying hosted catalog content.

## Validation Commands

Run JSON validation:

```bash
node -e 'const fs=require("fs"); for (const p of ["web/public/climbs/catalog-v1.json","AscendApp/Features/Climbs/Resources/climbs.json","web/public/climbs/manifest.json"]) JSON.parse(fs.readFileSync(p,"utf8")); console.log("climb catalog json ok");'
```

Check remote and bundled catalogs are identical:

```bash
diff -q web/public/climbs/catalog-v1.json AscendApp/Features/Climbs/Resources/climbs.json
```

Build hosted assets:

```bash
npm --prefix web run build
```

If changing Swift behavior or unsure about schema compatibility, run:

```bash
xcodebuild -scheme AscendApp -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Deployment

Deploy only the intended environment.

```bash
npx -y firebase-tools@15.22.1 deploy --only hosting --project dev
npx -y firebase-tools@15.22.1 deploy --only hosting --project staging
npx -y firebase-tools@15.22.1 deploy --only hosting --project production
```

The CLI version is pinned repo-wide; see `docs/dependency-security.md` before changing it.

For ordinary catalog additions, do not change Firestore rules, Storage rules, PrivacyInfo, or app code.

## Output Checklist

When done, report:

- Added/changed climb IDs.
- Release state for each climb.
- Catalog version before and after.
- Whether remote and bundled catalogs match.
- Whether web build passed.
- Whether hosting was deployed, and to which Firebase project.
