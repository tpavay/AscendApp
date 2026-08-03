# Where the rules come from

Sourced 2026-08-02, against a citation-backed study of how shipped iOS apps actually change their local database.
The fuller report, with the evidence tags on every claim, lives outside this repository as `data/research-ios-schema-migration-practice/report.md` in the firstmate home.
What follows is the part the playbook depends on, kept here so the rules can be argued with rather than merely obeyed.

Claims below are marked where the distinction matters: **observed** means read in a primary source, **inferred** means reasoned from one, **unknown** means it was looked for and not found.

## Ascend is the outlier, so there is no category practice to copy

Of the fitness apps whose authority model could be established - Strava, Garmin Connect, AllTrails, Runna, Peloton, Nike Run Club - **every one is server-authoritative**.
The phone holds a cache plus an outbox; the server holds the truth.
Strava's own support documentation is the quotable version: delete and reinstall the app and "you will not lose any data since all data is stored on the Strava servers". **Observed.**
Garmin's documentation says the same thing in the same words.

That makes their migration story barely a story.
If the local database will not open, they delete it, recreate it empty, and refetch. WooCommerce's iOS app does exactly this in about forty lines, and it is the entire recovery plan. **Observed.**

**Ascend cannot do that**, because the local store holds records that may exist nowhere else. **Inferred**, from the observed authority models plus Ascend's architecture.

Two consequences:

1. Copying the fitness category's practice would mean copying data loss. There is nothing there to take.
2. The comparable apps are local-first ones outside fitness: Signal (GRDB, 154 schema versions, open source), Things, Day One, Actual Budget, Linear. Almost every rule worth stealing came from Signal.

A pattern worth naming: of every app surveyed in both groups, **exactly one uses SwiftData, and it is Ascend**.
Signal uses GRDB, Actual uses raw SQLite, WooCommerce and AllTrails use Core Data, Linear uses IndexedDB.
Every serious local-first app found runs migrations that are explicit, ordered, individually named, and recorded in the database itself.
None relies on a framework inferring the migration from a diff of the model types. **Observed.**

## The rule that mattered most, and why it is already spent

**Shipping an unversioned SwiftData store and adding versioning later breaks the app for existing users.**
The error is exact and reproducible: `Store failed to load. Cannot use staged migration with an unknown model version.` **Observed** in three independent places, including two Apple Developer Forums threads - one carrying a reply from DTS Engineer Ziqiao Chen giving the official structure - and a developer write-up from someone who shipped unversioned and crashed his users.

Two details that make it worse, both **observed** from thread 761735:

- The workaround for existing users is a two-release dance: release N wraps the current models in a `V1` schema with no migration, then release N+1 adds `V2` and the plan. Users who skip release N can still crash.
- Even following the DTS guidance, production users in that thread still report the crash, and **the thread contains no confirmed data-preserving recovery**.

This is the single most important rule in the playbook, and Ascend has already paid for it: `AscendSchemaV1` and `AscendSchemaV2` exist, and `ModelContainer` is constructed with `migrationPlan: AscendMigrationPlan.self`.
The window this rule protects does not reopen, which is why the rule survives as "never undo it" rather than "go do it".

## What SwiftData migrates automatically

**Apple does not document the boundary.** The DocC for `SchemaMigrationPlan`, `VersionedSchema`, `MigrationStage` and both of its cases carries a one-line abstract or none, and zero paragraphs of discussion. **Observed.**
`ModelContainer` states the principle - automatic migration handles changes until "the aggregate changes between two versions of your schema exceed the capabilities of automatic migrations" - and never says what those capabilities are.

So the operative list is Core Data's, because SwiftData is Core Data underneath. **Observed**, from Apple's "Migrating your data model automatically" and WWDC22 session 10120:

- Attributes: add, remove, non-optional becoming optional, **optional becoming non-optional with a default value**, rename via a renaming identifier.
- Relationships: add, remove, rename via identifier, change cardinality either way.
- Entities: add, remove, rename; create a parent or child; move properties up and down a hierarchy.
- Explicitly not supported: merging entity hierarchies that did not share a parent in the source, and anything requiring interpretation of existing values.

The one SwiftData-specific ineligibility Apple has stated on the record, from WWDC23 session 10195: making a property unique is **not** lightweight-eligible and needs a custom stage that deduplicates first. **Observed.**

**The gap that produced the "no required property without a default" rule.**
"Addition of an attribute" is listed unqualified, and the only place a default value is mentioned is the optional-becoming-non-optional case.
Adding a *new* non-optional attribute with no default has no defined value to write into existing rows, and no supported way for the inference engine to invent one.
No first-party sentence saying it fails could be found; a body of consistent field reports of automatic migration failing on ordinary property changes could. **Observed**, forum thread 810527 among others.
The rule Ascend adopts is therefore stricter than the documented boundary, deliberately.

## The failure modes that are real rather than theoretical

Each row is something a shipped app defends against, not a hypothetical.

| Failure | The defence that ships somewhere |
|---|---|
| **Disk exhausted mid-write** | Signal checks free space against database size before recovery, warns with a bypass, and runs a low-disk preflight before anything else. **Observed** |
| **Force-quit during a long migration** | GRDB runs each migration in its own transaction and stores the memory of applied migrations in the database itself, so a killed migration simply re-runs. Signal's comment makes the contract explicit: a failed migration *must* throw to be marked incomplete. WooCommerce migrates into a temporary store and swaps at the end, so an interruption leaves the original untouched. **Observed** |
| **Watchdog kill because migration blocked launch** | A documented incident: an app added two entities and one attribute, and users with multi-gigabyte stores got white screens on launch. Root cause was a WAL that had grown unbounded, so Core Data had to checkpoint gigabytes before migrating, taking over 20 seconds. It hit only long-term users with the largest stores - the most engaged ones. Fix was moving initialisation off the main thread. **Observed.** Signal's separate defence is a launch-attempt counter in `UserDefaults` that stops a crash loop at 3. **Observed** |
| **Store already corrupt from an earlier version** | Signal registers schema and data migrations separately so recovery can apply the structural half and skip the interpretive half. **Observed** |
| **A newer store meets an older app** | A user restores an old backup. Core Data appears to migrate *backwards* silently, dropping the added column with no error - **observed** as one developer's reported experiment, contradicted by WWDC22's statement that an incompatible store errors. The contradiction could not be resolved from primary sources. Signal does not rely on the framework: it stores the schema version in `UserDefaults`, checks it before touching the store, and refuses to launch with "Please upgrade to the latest version". **Observed** |
| **A widget opens the store during migration** | Apple's DTS confirms there is **no API** for this and you must build your own coordination. Ascend is not exposed today - `AscendLiveActivityWidgets` contains no SwiftData and the project declares no App Group - and becomes exposed the first time a widget reads the store. **Observed** |

## Where SwiftData is weaker than the alternatives

**Observed**, and worth knowing so nobody assumes a capability that is not there:

| Capability | GRDB | SwiftData |
|---|---|---|
| Named, ordered, individually-recorded migrations | yes, in a reserved table | no, version identifiers only |
| Per-step transaction and rollback | documented | not documented |
| Resume after interruption | by design | not documented |
| "Database too new" detection | `hasBeenSuperseded` | none |
| Migrate to a copy, atomic swap | trivial | no API |
| Progress reporting | you control the loop | none |
| Migrations independent of app types | enforced by convention | impossible; the schema *is* Swift types |

This is not an argument to leave SwiftData - Ascend is deep in it, and switching stores before launch would be a far larger risk than the one being mitigated.
It is an argument that anything on that list which Ascend needs has to be built by hand, and that `AscendMigrationPlan`'s on-disk stash, page-bounded sweep, attempt counter and explicit diagnostics are exactly that hand-built machinery rather than over-engineering.

Apple's own guidance, from WWDC22, on the part that is yours: *"If you perform app-specific logic during your migrations ... that logic must be 'restartable' in the event the migration is interrupted due to the process terminating."* **Observed.**

## Gating, and why the App Store lever is weaker than it sounds

Apple's own documentation on phased release, all **observed**: seven days at 1/2/5/10/20/50/100 percent; **"phased release is only available for version updates"**, so it never covers a first ship; pausable for up to 30 days; and the caveat that undoes it as a safety net - **"apps and app updates in phased release can be manually downloaded from the App Store by anyone at any time."**

So phased release delays *automatic* updates only.
The users who open the App Store and tap Update are exactly the engaged ones with the largest stores, and they bypass the ramp entirely.

For the same reason, and independently: on iOS, halting a rollout does not remove the build from anyone who already updated, whereas on Android it does. **Observed**, from GetYourGuide's published release-monitoring write-up.

That write-up is also where the **crash-free users** guardrail comes from, and it answers the "what if it only breaks for some users" question directly: they track crash-free users alongside crash-free sessions specifically to catch failures concentrated in a subset - a device class, an app version, a store size - that barely move the session rate.
Squarespace's Unfold publishes the adjacent constraint in one sentence: *"there is no such thing as a rollback"* for mobile.

Sources: <https://www.getyourguide.careers/posts/how-we-automate-the-app-release-monitoring-at-getyourguide>, <https://engineering.squarespace.com/blog/2024/unfolds-modern-mobile-release-process-and-the-subtle-art-of-making-them-boring>.

## Adopted, and rejected with reasons

**Adopted**

- The three routes for a non-optional property, and the rule that a default is only ever consulted for a *new* column. This is the correction that killed the proposed blanket sweep of defaults across the models: adding a default to a property that already exists changes nothing.
- "Never ship an unversioned store" as the first rule, because it is the only one with no recovery.
- Decomposing a hard change into a lightweight step plus a gated backfill, rather than doing interpretive work inside `ModelContainer.init`. This is Apple's own recommended technique and it moves risk from the ungateable half to the gateable one.
- Proving a migration against a store written in the previous shape. Already the discipline in `WorkoutSourceSchemaMigrationTests`.
- Crash-free **users** alongside sessions, for the large-store minority Ascend is most exposed to.

**Rejected, with reasons**

- **Automatic rollout halting on a crash threshold.** Squarespace and GetYourGuide both automate this, and both have release trains, dedicated tooling, and enough traffic for the statistics to mean something. Ascend is pre-launch; a confidence interval over near-zero sessions halts on noise. Revisit once there is a session baseline.
- **Keeping a full backup copy of the store before migrating.** Genuinely sound, and the standard industry safety net. But SwiftData exposes no `replacePersistentStore` equivalent, so there is no supported migrate-into-a-copy-and-swap, and `Workout` carries its heart-rate series inline so a hand-rolled copy can be gigabytes. Reconsider per-migration if one ever rewrites rows in place rather than adding to them.
- **A blanket sweep of default values across every model.** See above. It buys nothing and it hides the one case that matters.

## What is genuinely unknown

Stated plainly, because a short list of established things is worth more than a long list of plausible ones.
All four are avoided by the playbook rather than solved by it.

- Whether SwiftData rolls back a partially-applied custom stage that throws.
- What SwiftData does with a store newer than the app, and the Core Data evidence is self-contradictory.
- Which thread a custom migration stage runs on. In Ascend it is in practice the main thread, because the container is built in `AscendApp.init()`.
- Whether adding a non-optional property *with* a default reliably lightweight-migrates in SwiftData. Treat it as permitted-but-must-be-tested, never as assumed.

## Sources

**Apple, first-party**

- [SwiftData `ModelContainer`](https://developer.apple.com/documentation/swiftdata/modelcontainer) · [`SchemaMigrationPlan`](https://developer.apple.com/documentation/swiftdata/schemamigrationplan) · [`VersionedSchema`](https://developer.apple.com/documentation/swiftdata/versionedschema) · [`MigrationStage`](https://developer.apple.com/documentation/swiftdata/migrationstage)
- [Core Data: Migrating your data model automatically](https://developer.apple.com/documentation/coredata/migrating-your-data-model-automatically)
- [WWDC23 session 10195, Model your schema with SwiftData](https://developer.apple.com/videos/play/wwdc2023/10195/) · [WWDC22 session 10120, Evolve your Core Data schema](https://developer.apple.com/videos/play/wwdc2022/10120/)
- [App Store Connect Help: Release a version update in phases](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases/)
- Developer Forums: [761735, unversioned migration, with DTS reply](https://developer.apple.com/forums/thread/761735) · [769149, un-versioned to versioned](https://developer.apple.com/forums/thread/769149) · [810527, fails to migrate on a new property](https://developer.apple.com/forums/thread/810527) · [774618, widget during migration, with DTS reply](https://developer.apple.com/forums/thread/774618) · [747370, old app after migration](https://developer.apple.com/forums/thread/747370)

**Open-source implementations**

- Signal-iOS: [`GRDBSchemaMigrator.swift`](https://github.com/signalapp/Signal-iOS/blob/main/SignalServiceKit/Storage/Database/GRDBSchemaMigrator.swift) · [`DatabaseCorruptionState.swift`](https://github.com/signalapp/Signal-iOS/blob/main/SignalServiceKit/Storage/Database/DatabaseCorruptionState.swift) · [`DatabaseRecoveryViewController.swift`](https://github.com/signalapp/Signal-iOS/blob/main/Signal/src/ViewControllers/DatabaseRecoveryViewController.swift) · [`AppDelegate.swift`](https://github.com/signalapp/Signal-iOS/blob/main/Signal/AppLaunch/AppDelegate.swift) · [`SSKPreferences.swift`](https://github.com/signalapp/Signal-iOS/blob/main/SignalServiceKit/Util/SSKPreferences.swift)
- [GRDB.swift: Migrations](https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/Migrations.md)
- WooCommerce-iOS: [`CoreDataManager.swift`](https://github.com/woocommerce/woocommerce-ios/blob/trunk/Modules/Sources/Storage/CoreData/CoreDataManager.swift) · [`CoreDataIterativeMigrator.swift`](https://github.com/woocommerce/woocommerce-ios/blob/trunk/Modules/Sources/Storage/CoreData/CoreDataIterativeMigrator.swift) · [issue 2667](https://github.com/woocommerce/woocommerce-ios/issues/2667)

**Authority models and incidents**

- [Strava: Troubleshooting Syncing](https://support.strava.com/hc/en-us/articles/216919037-Troubleshooting-Syncing)
- [Garmin Forums: reinstall and data](https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-mobile-ios/297261/if-i-remove-garmin-connect-altogether-then-reinstall-will-all-my-data-be-deleted)
- [Core Data migration incident analysis](https://fatbobman.com/en/posts/core-data-migration-incident-analysis/)
- [Mert Bulan: Never use SwiftData without VersionedSchema](https://mertbulan.com/programming/never-use-swiftdata-without-versionedschema)
