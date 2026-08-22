# Climb-drop notifications

`announceClimbDrops` (`functions/src/climbDropNotifications.ts`) is the sender behind the promise every climb-drop surface makes.
It is a scheduled Cloud Function, deployed and operated entirely from the backend: no app release is involved in announcing a drop.

## The promise it keeps

The shipped strings are the authority, not the backlog and not a design guide.
All five of them say the alert arrives **when** a climb opens:

| Surface | Copy |
|---|---|
| `PostAuthOnboardingFlowView.swift` | "Get an Ascend alert when new climbs open. Be ready to claim the First Ascent before anyone else." |
| `NotificationSettingsView.swift` | "New climb drops" / "A new landmark opens in the catalog." |
| `CollectionSection.swift` | "Be the first to know when new climbs drop." |
| `PrestigeSection.swift` | "…be first up when the next climb drops." |
| `EmailPreferencesContentView.swift` | "Ascend emails you when a climb drops and when you hit a milestone." |

So the contract is an alert at the open, delivered to everyone at once, not advance notice.

**Advance notice is not available to promise.**
The catalogue is a static file published by a hosting deploy and carries no unlock timestamp, so there is nothing to count back from.
Giving notice ahead of an open would take a catalogue schema change *and* a client that withholds an already-published climb until a scheduled moment - a client change.
`scripts/test/climb-drop-promise-contract.test.mjs` fails any surface or document that reintroduces the 24-hour claim that used to live in the internal docs.

The email half of that table is **not** honored yet: there is no `climb_drop` type in `functions/src/email/catalog.ts`, so nothing queues a drop email.
That is the one remaining gap between the copy and the code.

## How a drop is detected

There is no Firestore state transition to trigger on - `releaseState` lives in `web/public/climbs/catalog-v1.json`, deployed to Firebase Hosting.
So the sweep polls, every five minutes, the same files the app reads:

1. `GET https://{projectId}.web.app/climbs/manifest.json`.
   Unchanged `catalogVersion` means nothing was published; the catalogue itself is not fetched.
2. On a version change, `GET` the catalogue (with the version as a cache key, because the edge caches it for an hour).
3. Anything `available` that is not already in the baseline is a drop.

`climb_drop_notification_state/current` holds the baseline as `announcedClimbIds`, and it only ever **grows**.
A climb pulled back to `hidden` and later reopened therefore does not announce twice.

A catalogue row without a `name`, or without an `id` that can name a Firestore document, is skipped at fetch time.
One malformed entry costs that climb its announcement and nothing else - detection, and every other climb in the same publish, still runs - and because a skipped climb never enters the baseline, a corrected publish announces it then.
A hand-authored `"id": "tour/eiffel"` is the case that matters: an id carrying a `/` would resolve `dispatches.doc(...)` to a collection and throw inside the admin SDK.
Belt and braces, the dispatch id sanitizes the leading climb id down to one path segment before splicing it in - the 12-character digest is what makes the id unique, so the prefix is only there to keep the document legible in the console.

**Detection cannot stall delivery.**
Everything that reads hosting lives in one guarded block.
A drop already created owes its remaining devices an alert whether or not `manifest.json` is answering, and delivery reads nothing from the catalogue - so a fetch that fails records itself as `detectionError` on the run summary and the sweep falls through to the dispatches still in flight.
Left unguarded, one 503 stalls every partly-sent drop for as long as hosting is unwell.

**The dispatch and the baseline are one write.**
Creating `climb_drop_dispatches/{dispatchId}` and advancing `announcedClimbIds` commit in a single Firestore batch, so neither can outlive the other.
Two writes break in both orders: a baseline that lands first records a climb as announced with nothing to announce it and never re-detects it, and a dispatch that lands first lets the next detection fold that climb into a differently-hashed union whose receipts are a fresh ledger - a second push for a climb already sent.
A climb belongs to exactly one dispatch, for good, and that is what the whole no-duplicate guarantee rests on.

### Bootstrapping a new environment

The first sweep in a project finds no state document, records every currently-available climb as already announced, and sends nothing.
That is deliberate: against an empty baseline the whole catalogue looks like a drop.

The same is true if the state document is ever deleted - the sweep goes quiet rather than announcing 58 climbs.
Restoring a lost baseline by hand means writing `announcedClimbIds` with the ids that should *not* announce.

## How a drop is sent

`climb_drop_dispatches/{dispatchId}` is one announcement.
The id is derived from the climb ids, so re-detecting the same drop lands on the document that already exists.
A deploy that opens four landmarks produces **one** dispatch and one push, led by the longest race in the set.

Sending walks `notification_devices` in ordered pages of 500 - FCM's multicast ceiling - and for each device:

1. **Claims** it by `create`-ing `climb_drop_dispatches/{dispatchId}/receipts/{tokenHash}`.
   A receipt that already exists is a device already claimed for this drop, in any earlier run, and it is skipped.
2. Sends the page as one `sendEachForMulticast`.
3. Records each outcome onto the receipt, and unregisters every token FCM reports as dead.

The claim happens **before** the send on purpose.
The other order would cost a duplicate push, and "never twice" is the harder half of the promise to recover from.

### A send that never reached FCM

`sendEachForMulticast` reports a per-token refusal *inside* its response.
So a send that **throws** - a 503, a DNS blip, a transport error - is a batch FCM never saw, and nothing on it was delivered.

The claim is kept: releasing it is the ordering that risks a duplicate if the send did in fact land.
The receipts are marked `state: "unsent"` instead, which a later run can tell apart from a device actually alerted, and re-send to.
The cursor is not advanced either, so the next run re-walks exactly that page.

A plain `claimed` receipt is deliberately **not** re-sent.
It may be a page whose push landed and whose settle write did not, and a second push is the failure never-twice cannot recover from.

**The retry is bounded, and the bound is conjunctive.**
A device is given up on only once **both** budgets are spent: three sends, **and** thirty minutes elapsed since it was first claimed.
Neither term alone may abandon anyone.

An attempt counter on its own is not a budget here.
Three sends fit inside three five-minute ticks, so a bare count writes off the one page that was in flight about fifteen minutes into an FCM incident - and every page after the incident then delivers normally, leaving exactly those climbers the ones who never heard about the climb.

The clock is `abandonEligibleAt`, an **absolute date** written onto the receipt at its first claim, never a duration recomputed per run.
It therefore keeps running across a restart, a redeploy and a cold start instead of starting over with the process.
`planReceiptAbandon` is the single expression of the rule, shared by the store and its test harness.

When both budgets are spent the receipt flips to `abandoned` and that device is written off - a page that can never be reached must not hold its cursor, and its drop's per-run slot, open for good.

Claims run at bounded concurrency, and each device's create gets **three** attempts with a short backoff.
Firing 500 unthrottled creates and rejecting the page on the first failure would abandon receipts that already landed, leaving those devices claimed for good and never sent to.

A `create` is not idempotent, so an attempt that commits and then loses its response leaves the retry reading ALREADY_EXISTS for a document nothing will ever send to.
That case is reported as *ambiguous* rather than as "another run has this device", and counted with the devices left behind - reading it the other way is how a device vanishes from the counters entirely.

A device still unclaimed after its three attempts is **left behind**: it is counted in `unclaimedCount`, the page sends to everyone it did claim, and the cursor advances as normal.
That device misses this drop, and no later run picks it up - the same trade the claim-before-send ordering already accepts.
Holding the cursor for it instead would wedge the drop on one document: the same page re-walked every run, the dispatch never completing, and one of the three per-run slots held for good.
A drop that cannot finish is the broken promise; one missed device is not.

Dead-token pruning (`deactivatePushTokensByHash`, shared with the operational callable) is bounded the same way, and it tolerates a per-hash failure rather than throwing.
Pruning is housekeeping that runs *after* the send: a dead token surviving until the next drop costs far less than a stalled dispatch.

A run processes at most 20 pages per dispatch and 3 dispatches, and the function is given the 540s timeout that budget needs - the default 60s could not execute the work the code declares.
Because a run can outlive its own five-minute interval, the function is pinned to `maxInstances: 1` and `concurrency: 1`: two concurrent sweeps would read the same `deviceCursor` and the slower one's write would drag the drop back to a page already sent.
Belt and braces, a page boundary can only ever move the cursor **forward**, and `state: "sent"` is terminal - `planDispatchAdvance` refuses to move a finished dispatch back into the unfinished set, and a page boundary that plans no change writes nothing at all rather than landing its counters on a drop another run already finished.
Neither page write may create a dispatch it cannot find, either: an absent document is an operator cancelling a drop by deleting it, and a `{merge: true}` set would recreate it with counters and no `createdAt` - which `listUnfinishedDispatches` orders by and could therefore never return.
Anything left over resumes from `deviceCursor`, which is persisted at every page boundary rather than once at the end of a run.
Correctness never rested on that: the receipts make any resume free of duplicates.
What it buys is that a run the platform kills mid-drop resumes at the page it finished, instead of re-scanning and re-claiming every device already alerted on every subsequent run.
A dispatch whose send throws is isolated - the drop behind it still goes out, and the failing one retries on the next run.

Receipts hold no `uid`.
A token hash resolves to nobody once the device's `notification_devices` document is deleted, so account deletion owes this ledger no sweep.

## Who gets sent to

`isDeliverableClimbDropRegistration` in `functions/src/pushNotifications.ts` is the single answer, shared with the operational `sendClimbDropNotification` callable.
A device must be `active`, `platform: "ios"`, hold a token, have `climbDropPushEnabled: true`, and report an authorization status iOS will actually deliver on.

The toggle is the climber's standing intent and outlives an iOS denial - the denial costs delivery, never the stored preference - so both facts are checked, never one standing in for the other.

## The payload

```json
{
  "type": "climb_drop",
  "route": "climb_detail",
  "climbId": "<the drop's marquee climb>",
  "climbIds": "<comma-joined>",
  "dispatchId": "<dispatch id>",
  "campaignId": "<dispatch id>"
}
```

`type` plus `climbId` is exactly what `PushNotificationRouter` in the shipped 1.0 build already routes, so a tap deep-links into that climb's detail screen with no client change.
`climbIds` and `dispatchId` are inert to that build and are there for a later one to read.

## Operating it

**Stopping a send.** Set `sendingEnabled: false` on `climb_drop_notification_state/current`.
Detection keeps running and dispatches keep being created; nothing is sent until the flag returns, and then the queued drop goes out from where it stopped.
An absent field reads as enabled, so a document written before the flag existed is not held.
This is the choke point that *defers*, not the raw FCM call - the same invariant as the client kill switches in `docs/remote-config-kill-switches.md`.

**Announcing by hand.** `sendClimbDropNotification` still exists for an operator with the `admin` claim and is unchanged.

**Deploy order.** Indexes before functions: `listUnfinishedDispatches` queries `state` + `createdAt` and fails without the composite index in `firestore.indexes.json`.

**Watching it.** Every run logs `announceClimbDrops sweep completed` with its counters, or an error-level line when something went wrong:

| Log line | What fired it |
|---|---|
| `announceClimbDrops sweep left drops unsent` | a dispatch threw; it retries on the next run |
| `announceClimbDrops sweep could not read the catalogue` | detection failed; delivery of drops already in flight carried on |
| `announceClimbDrops sweep gave up on devices` | a page FCM could not be reached on, three runs running |
| `announceClimbDrops sweep left devices unclaimed` | a receipt create kept failing, or settled ambiguously |

The per-run summary is the signal to act on - each of the devices in the last two lines missed the drop for good.

**Did this drop lose anyone, and how many?** Read `abandonedCount` on `climb_drop_dispatches/{dispatchId}`.
It is seeded to `0` when the dispatch is created, so a clean drop reads as a real zero rather than a missing field.
Each device flips to `abandoned` exactly once, and the page's flips reach the dispatch in one `increment` after the claim pass - the same way every other counter reaches that document, and without putting 500 devices into optimistic contention on one document at the moment they all resolve together.
Re-walking the page cannot inflate it: an already-abandoned receipt resolves as held and is not counted again.
Cross-check it against the receipts: `state: "abandoned"` names exactly those devices.

The run summary reports the same number for the run, and it survives a dispatch that also throws - a page that gave up on devices and then failed its next send still logs `gave up on devices`, because a silenced alarm is the failure this counter exists to prevent.

**Recovering an abandoned page.** There is no automatic second chance: the dispatch ends `state: "sent"`, so `listUnfinishedDispatches` will never return it again.
Re-sending to exactly those devices means, on that dispatch, deleting the `state: "abandoned"` receipts, rewinding `deviceCursor` to just before the abandoned page, and setting `state` back to `sending`.
Delete the receipts rather than editing them - a receipt that is absent is re-claimed cleanly, and every device that already has a `delivered` receipt is skipped, so the re-run cannot double-alert anyone.

`unclaimedCount` is a plain `FieldValue.increment` and re-increments every run that re-walks the same page, so it is an upper bound rather than a count; use it to notice a claim fault, not to size one.

## What it costs

Receipts accumulate at one document per device per drop.
They are only read while a dispatch is unfinished, so a completed drop's receipts are inert - worth expiring if the device count ever makes them matter, but not worth a TTL policy at the current fleet size.
