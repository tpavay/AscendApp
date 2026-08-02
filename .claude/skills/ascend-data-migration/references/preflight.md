# Pre-flight

Run this before a schema change ships.
Every line is a gate, not a suggestion, because none of them can be checked after the fact on a device you cannot reach.

## The checklist

**Shape**

- [ ] The change is classified against the decision procedure in `SKILL.md`, and the row is named in the PR body.
- [ ] If a non-optional property is new, one of the three routes was chosen deliberately: optional, honest blanket default, or a custom stage. Which one, and why, is in the PR body.
- [ ] A new `AscendSchemaV*` exists with a bumped `versionIdentifier`, listing **every** model, not only the changed ones.
- [ ] The previous `AscendSchemaV*` is byte-for-byte unchanged.
- [ ] A stage is appended to `AscendMigrationPlan.stages`, connecting the previous version to the new one, with no gap.
- [ ] `AscendLocalStore.currentSchema` points at the new schema. `AscendApp.createModelContainer` reads it from there, and so do account deletion's local sweep and the sign-in ownership gate.
- [ ] If the change adds a model, `AscendLocalStoreFixture` gains a row for it. Deletion and the gate pick it up on their own, but nothing *proves* deletion removes it until the fixture can create one - and the coverage test fails until it does.
- [ ] If a stage computes the value for a new required column, `SharedTestVectors/swiftdata-schema-shape.json` names that column in `customStageColumns`. See below.
- [ ] `node scripts/check-swiftdata-schema.mjs --update` runs clean and the re-recorded `SharedTestVectors/swiftdata-schema-shape.json` is in the same commit.

**Proof**

- [ ] **The migration is proven against a store created by the previous shape, not a fresh one.** See below. This is the item everyone skips and it is the only one that proves anything.
- [ ] Proven against a realistic row count, not three rows. `Workout` carries its heart-rate series inline, so a few hundred sessions is tens of megabytes on disk.
- [ ] Asserted on the *contents* after the migration, not only that the container opened. A migration that opens successfully and drops a column is worse than one that fails loudly, because nothing reports it.
- [ ] The empty-store case still works, because that is every new install.
- [ ] If a stage can fail, it is proven to leave a recoverable state, and the recovery is proven to converge rather than re-run forever.

**Everything else the change drags in**

- [ ] If a Firestore field changed too, `firestore.rules` was updated first and accepts the version range still in the field. See `ascend-firebase-data`.
- [ ] If a new data type is now collected, `PrivacyInfo.xcprivacy`, the privacy policy, the App Store questionnaire and the `Info.plist` strings all agree. See `ascend-privacy-manifest`.
- [ ] Any interpretive work that could live in a post-launch backfill instead does, behind `local_data_migrations_enabled`.
- [ ] The PR body says what happens to a user still on the previous build reading data this build wrote, and what happens to a user who restores an older backup onto a newer store.

## The test everyone skips

A migration tested against a store your current build just created is a migration tested against a store that already has the new schema.
It proves nothing, because the rows it needed to fail on were never written in the old shape.

**Ascend already does this properly and you should copy it, not reinvent it.**
`AscendAppTests/WorkoutSourceSchemaMigrationTests.swift` seeds a real on-disk store through `AscendSchemaV1` first:

```swift
let schema = Schema(versionedSchema: AscendSchemaV1.self)
let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
```

then closes that container, reopens the same file with `AscendSchemaV2` **and the migration plan**, and asserts on what came out.
The suite's own header says why: the failure being guarded against is silent, and a store that lost every source reads back exactly like a healthy fresh install.

Copy that shape:

1. Seed a store through the **previous** `VersionedSchema`, with rows that cover the interesting cases - every enum case, nulls in every optional, the relationship graph populated, and at least one row that is legitimately weird.
2. Let the seeding container go before reopening. Two live containers on one file fight.
3. Reopen with the current schema and the plan.
4. Assert on values, not on the open succeeding.

**Where this approximation is weaker than it looks, and it matters.**
`AscendSchemaV1` declares frozen copies of only three types - `Workout`, `WorkoutSourceLink`, `WorkoutParticipation`.
Its `models` list names the other nine by their **live** type, because the two versions were identical for them.
So a store seeded "under V1" already has today's shape for those nine.
The moment you change one of them, `AscendSchemaV1` silently starts describing the new shape too, which is the "never edit a shipped schema version" rule broken by aliasing rather than by editing.
Freeze a copy of any model you are about to change into the schema version that shipped it, in the same PR.

## Naming the column a stage covers

A custom stage does not excuse a required column on its own.
`SharedTestVectors/swiftdata-schema-shape.json` carries a hand-written `customStageColumns` list, and a new required column with no default passes only when that list names it **and** the change adds a stage that `AscendMigrationPlan.stages` actually runs:

```json
"customStageColumns": ["Workout.sourceRawValue"]
```

The list is written by hand and `--update` carries it across rather than regenerating it, because the whole point is that a human said which column the stage computes.
Without it, one PR that adds a stage for `Routine.intervalPlan` would silently wave through an unrelated `Workout.cadence` in the same diff, and every existing workout would take whatever SwiftData decided.
The same entry is what lets a deliberate type change through.

A stage declared but never referenced from `stages` counts for nothing, because it migrates nothing.

**A rename does not need any of this.**
`@Attribute(originalName: "oldName")` is read off the declaration, so the check treats the column as a continuation of `oldName` rather than as a brand-new required one, and no stage or allowlist entry is involved.
A rename *without* the annotation still fails, and that is correct: SwiftData reads it as a delete plus an add and the old values are gone.
A rename that also changes the type is still a type change, and is still caught.

## Collapsing unshipped schema versions before a release

The check demands a new `AscendSchemaV*` for every persisted-shape change, and it cannot tell a version that has shipped from one that exists only on your machine.
So several versions can accumulate inside a single unreleased cycle: three PRs that each change the shape leave you at V5 with three stages, even though users are still on V2.

**Before a release ships, collapse the versions that have never reached a user into a single version with a single stage.**
Every surplus version is another stage chained inside `ModelContainer.init`, on the launch path, forever - and that is the most expensive place in the app to do work.
Collapsing is a hand edit: delete the intermediate `AscendSchemaV*` files and their stages, renumber the survivor, then re-record the baseline with `node scripts/check-swiftdata-schema.mjs --update`.
The check does not offer an escape hatch for this and is not meant to: re-recording is the escape hatch, and it only writes once the collapsed state is legal.

**A version that has reached a user can never be collapsed. That includes TestFlight.**
A store on someone's device was written by that version, and the plan is the only thing that knows how to read it.
The moment a build leaves your machine, its schema version is permanent.

## Things that are cheap and worth doing while you are here

- Migrate a store from **two or more** versions back in one hop. Users skip releases, and a chain that is never exercised is a chain that is assumed to work.
- Time the migration against a large store and assert it against a budget. That is the watchdog test, and the watchdog does not send you a crash report saying "your migration was slow" - it sends one that looks like a launch crash.
- Test the low-disk case if the change rewrites rows rather than appending. Peak disk during a rewrite is roughly twice the store.
