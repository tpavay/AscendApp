---
name: ascend-data-migration
description: Use when you are about to add, remove, rename or change the type of a stored property on an `@Model`; add or delete an `@Model` type; touch anything under `AscendApp/Shared/Models/Migrations/`; or reason about what happens to an existing user's data when they install the next build. Also use when a shipped migration is failing in the field, or when someone claims Ascend has no migration plan. Covers the decision procedure for a model change, the absolute rules, the pre-flight checklist, what a stranger's phone does when a migration fails, and why Firestore needs none of this.
---

# Data migration

Ascend keeps workouts in a local SwiftData store on the user's device.
Some of those records exist nowhere else.
That is the whole reason this skill exists: a bad local migration is not a bug you fix in the next release, because an iOS binary cannot be rolled back and the data is already gone.

**Ascend has a versioned schema and a migration plan. It has had one since the `Workout.source` change.**
Anyone who tells you otherwise is reading `main`, or reading nothing.
Start from what is actually here.

## What exists today

| Thing | Where |
|---|---|
| The shapes older installs wrote | `AscendApp/Shared/Models/Migrations/AscendSchemaV1.swift`, `AscendSchemaV2.swift`, `AscendSchemaV3.swift` |
| The shape the app writes now | `AscendApp/Shared/Models/Migrations/AscendSchemaV4.swift` |
| The plan that carries V1 forward to V4 | `AscendApp/Shared/Models/Migrations/AscendMigrationPlan.swift` |
| The one declaration of which schema is live, read by everything that must cover the whole store | `AscendApp/Shared/Models/AscendLocalStore.swift` (`currentSchema`) |
| Where the container is opened, and the interrupted-migration retry | `AscendApp/App/AscendApp.swift` (`createModelContainer`, `finishInterruptedMigrationIfNeeded`) |
| Proof it works against a real V1 store | `AscendAppTests/WorkoutSourceSchemaMigrationTests.swift` |
| Proof it works against a real V2 store | `AscendAppTests/RoutineBackupSchemaMigrationTests.swift` |
| A gated post-launch backfill, for contrast | `AscendApp/Shared/Services/WorkoutRemoteSyncMigrationService.swift` |

`AscendSchemaV1` is `Schema.Version(1, 0, 0)` and is frozen.
It declares its own copies of `Workout`, `WorkoutSourceLink`, `WorkoutParticipation`, `Routine` and `RoutineFolder` so the migration can *read* what is on disk.
`AscendSchemaV2` is `Schema.Version(2, 0, 0)` and is frozen too; it carries its own `Routine` and `RoutineFolder`, unchanged from V1, because those two gained columns in V3.
`AscendSchemaV3` is `Schema.Version(3, 0, 0)` and lists thirteen models.
It needs no frozen copies of its own, because V4 changed no existing model - it only added one.
`AscendSchemaV4` is `Schema.Version(4, 0, 0)` and lists the fourteen live models: V3's thirteen plus `WorkoutSyncOutboxEntry`, the persisted retry schedule for a workout that is not yet in the cloud.
`AscendMigrationPlan.stages` holds three stages: `migrateV1toV2`, a `.custom` stage, then `migrateV2toV3` and `migrateV3toV4`, both lightweight.

**Read `migrateV1toV2` before you write a migration of your own.**
It is the worked example of the hardest case in the decision procedure below, and it is real code in this repository rather than a paraphrase of Apple's documentation.

## The decision procedure

Run it top to bottom. The first matching row wins.

**Step 0. Is this a schema change at all?**
Computed properties, methods, extensions, and enum cases whose raw value is stored in an unchanged `String` column do not touch the store.
Stop here. None of the below applies.

**Step 1. Classify the change.**

| What you are doing | Route |
|---|---|
| Adding an **optional** property (`T?`) | Lightweight. The safest change there is |
| Adding a **non-optional** property **with a default** | Lightweight, but only when the blanket value is honest. See Step 2 |
| Adding a **non-optional** property with **no default** | **Forbidden.** There is no value to write into existing rows. Go to Step 2 |
| Removing a property | Lightweight. That column's data is gone forever - decide before you delete, not after |
| Renaming a property | Lightweight **only** with `@Attribute(originalName: "oldName")`. Without it SwiftData sees a delete plus an add and the old values are silently lost |
| Adding, removing or renaming a model type | Lightweight (rename needs `originalName`). Deletion is silent and permanent - see the rules below |
| Adding, removing or re-pointing a relationship, or changing its cardinality or delete rule | Lightweight |
| Adding `@Attribute(.unique)` | **Custom stage, mandatory.** Deduplicate in `willMigrate` first. Apple names this case explicitly |
| Changing a property's type | **Custom stage**, or better, decompose. See Step 3 |
| Any value that must be **computed from existing data** | **Custom stage**, or a gated post-launch backfill. See Step 3 |
| Merging two model hierarchies under a shared parent | **Not possible.** Core Data forbids it outright. Redesign |

**Step 2. If the property is non-optional, decide what existing rows should hold.**

This is the question a default value answers, and it is the *only* question it answers.
A default is consulted when a property is **new** and the store must decide what already-written rows contain.
Adding a default to a property that already exists changes nothing, because those rows are already populated.
So there is no reason to sweep defaults through the models, and doing so hides the one case that matters.

Three honest answers, and you must pick one:

1. **The value is genuinely optional.** Make it `T?`. Nothing further is needed.
2. **A single blanket value is true of every existing record.** Give it a default. `Workout.remoteSyncStatusRawValue = WorkoutRemoteSyncStatus.pendingUpsert.rawValue` is this case: every pre-existing workout really did still need an upsert.
3. **A blanket value would be a lie.** Write a `.custom` `MigrationStage` that computes the right value per record.

**Case 3 is what `AscendMigrationPlan.migrateV1toV2` does, and reading it is faster than describing it.**
`Workout.source` moved from a Codable enum column to `sourceRawValue`.
Defaulting it to `.manual` would have claimed every recorded Live Climb was hand-entered - no enrichment, no Live Climb attempt, while `integrityLevel` still said verified.
So `willMigrate` reads each workout's real `source` from the V1 store and stashes it keyed by the workout's own `id`, and `didMigrate` writes it back onto the migrated store.
It has to be two phases because neither context can see both columns, and it is keyed by `id` because `PersistentIdentifier` does not survive the migration.

**Step 3. If you landed on a custom stage, try to decompose first.**

A custom stage runs inside `ModelContainer.init` during launch.
That is the most expensive place in the app to do work: it blocks the first frame, it cannot be gated, and if it takes too long the iOS watchdog kills the app before it draws.

The decomposition, for changing `foo: Int` into `foo: String`:

1. **V(n+1), lightweight:** add `fooString: String?` alongside `foo`. Both exist; the app writes both and reads `foo`.
2. **Backfill:** populate `fooString` from `foo` in ordinary app code, after launch, in the background, behind the `local_data_migrations_enabled` flag. `WorkoutRemoteSyncMigrationService` is the shape to copy.
3. **V(n+2), lightweight:** once the backfill has drained, remove `foo` and rename `fooString` to `foo` with `originalName`.

This moves the interpretive work out of the ungateable, launch-blocking, watchdog-exposed half and into the half that has a kill switch.
Reserve `willMigrate`/`didMigrate` for what only they can do: making the data legal for a structural change that is about to happen, or carrying a value across a column that is about to disappear.

## The absolute rules

- **Never ship an unversioned store.** Adding `VersionedSchema` to a store that shipped without one produces `Cannot use staged migration with an unknown model version`, and there is no confirmed data-preserving recovery. Ascend is already past this; the rule exists so nobody undoes it. Never remove `migrationPlan:` from `ModelContainer.init`, and never open the store with a bare `Schema([...])`.
- **Never add a required property with no default and no stage.** Existing rows have nothing to write. Pick one of the three routes in Step 2.
- **Never delete a model without first deciding where its data goes.** Deletion is silent and permanent. There is no warning, no error, and no recovery: the table is dropped and the rows are gone. Decide, write the decision in the PR body, then delete.
- **Never edit a `VersionedSchema` that has shipped.** It describes a store shape that exists on real devices. Add the next one instead.
- **Never rename a stored property without `@Attribute(originalName:)`.** SwiftData reads it as a delete plus an add, and the old values are dropped without a sound.
- **Never assume the kill switch protects a schema migration.** It does not, and the next section explains why.

## What a kill switch does and does not reach

`CLAUDE.md` has a standing tripwire that a new code path writing or reshaping persisted data needs a Remote Config kill switch in front of it.
That is right, and it is right for backfills.
It is not available for a schema migration, and the distinction is load-bearing:

- A **schema migration** runs inside `ModelContainer.init`, which `AscendApp.init()` calls before Firebase Remote Config has fetched anything. There is no value to consult. It is unconditional on every device that takes the build.
- A **backfill** is ordinary app code that runs after launch, so `RemoteFeatureGate` can defer it. `WorkoutRemoteSyncMigrationService` reads the gate before the sweep and stamps its completion key only after the sweep finishes, so a switch thrown before it runs leaves the work pending rather than falsely done; `RoutineRemoteSyncAdoptionService` stamps nothing at all and simply re-runs on the next bootstrap.

App Store phased release is not a substitute.
It does not apply to a first release at all, and it only delays *automatic* updates - anyone can open the App Store and tap Update.

So: put as much of the risk as possible into the backfill half, where a switch reaches it.
The half that stays in `ModelContainer.init` is protected only by being small, being tested against a real prior store, and failing well.

## What is NOT a migration

**Firestore has no fixed schema and needs none of this.**
It is a document store: adding a field to a document adds a field, and documents that lack it simply lack it.
There is no store-wide shape to migrate, no `VersionedSchema`, no stage, and no launch-time risk.

Adding a Firestore field is governed by a different and unrelated contract:

- `firestore.rules` uses strict `hasOnly`/`hasAll`, so the server rejects a field the rules do not list. Deploy rules first. See `ascend-firebase-data`.
- Readers accept a **bounded `schemaVersion` range**, never one exact value, because old app versions keep writing the old shape indefinitely (#296).
- Reshaping documents that already exist is a supervised script you run against our own infrastructure, with a dry run, a ledger, and a re-run if it goes wrong. `scripts/lib/migration-discipline.mjs` is the machinery; `ascend-firebase-data` is the skill.

Conflating the two has already cost time.
The local store is a bet you place on a device you cannot reach.
Firestore is an operation you perform and can perform again.

## The checks that hold this up

`node scripts/check-swiftdata-schema.mjs` reads the Swift sources and fails on the two mistakes that are otherwise invisible in a diff:

1. **The model list and the current versioned schema disagree.** A model declared but absent from `AscendLocalStore.currentSchema`'s `models` is never migrated and never opened with the store. The check also catches a plan or a container left pointing at a stale schema.
2. **A schema change adds a required property with no default and no stage, or changes a stored property's type.** The first fires only on properties that are *new* or newly non-optional, and only on models that already have rows - a brand-new model is exempt because it has none. The second fires on any existing column whose type changed, because lightweight migration drops the old column and takes the new one's default. It also fails a change to a shipped `VersionedSchema`, and a shape change with no new schema version.

Either one is excused only by a stage `AscendMigrationPlan.stages` actually runs **plus** a hand-written `customStageColumns` entry naming the column it covers, so a second unrelated column cannot ride in on the first one's stage.
The recorded shape lives in `SharedTestVectors/swiftdata-schema-shape.json`.
After a legitimate schema change, re-record it in the same PR with `node scripts/check-swiftdata-schema.mjs --update`; the update refuses to write while a rule is violated, and carries `customStageColumns` across untouched.
`scripts/test/swiftdata-schema-shape.test.mjs` runs both checks against this repository and proves each rule fires, and CI runs it in the `SwiftData Schema Verify` job on every change under `AscendApp/`.

Because the check cannot tell a shipped schema version from an unshipped one, several can pile up inside one unreleased cycle - and every surplus version is another stage chained inside `ModelContainer.init` at launch, forever.
`references/preflight.md` has the collapse step to run before a release ships, and the rule that a version which has reached a user, TestFlight included, can never be collapsed.

## References

- `references/preflight.md` - the checklist to run before a schema change ships, including the test everyone skips
- `references/failure-and-recovery.md` - what a stranger's phone does when a migration fails, what is reported, and what can be done for that user afterwards
- `references/research.md` - what comparable apps do, what was adopted and rejected, and the honest unknowns, with sources

## Related

- `swiftdata-pro` for `VersionedSchema` / `SchemaMigrationPlan` API detail
- `ascend-firebase-data` for the Firestore rules-first contract and the `schemaVersion` range
- `ascend-workout-model` for the workout schema open/closed rule and what `Workout` persists
- `docs/remote-config-kill-switches.md` for the flags, what they defer, and how to publish them
