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

The email half of that table is **not** honoured yet: there is no `climb_drop` type in `functions/src/email/catalog.ts`, so nothing queues a drop email.
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

A catalogue row without an `id` or a `name` is skipped at fetch time.
One malformed entry costs that climb its announcement and nothing else - detection, and every other climb in the same publish, still runs - and because a skipped climb never enters the baseline, a corrected publish announces it then.

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
   A receipt that already exists is a device already sent to, in any earlier run, and it is skipped.
2. Sends the page as one `sendEachForMulticast`.
3. Records each outcome onto the receipt, and unregisters every token FCM reports as dead.

The claim happens **before** the send on purpose.
A crash in between costs that page its alert; the other order would cost a duplicate push, and "never twice" is the harder half of the promise to recover from.

Claims run at bounded concurrency and no single one can abandon its page.
A create that fails for any reason other than "already exists" leaves that device unclaimed and counted (`unclaimedCount`), the page still sends to everyone it did claim, and the cursor stays where the page *started*.
The next run re-walks that page: the devices already claimed refuse a second claim, and the ones that missed their attempt get one.
Firing 500 unthrottled creates and rejecting the page on the first failure would do the opposite - abandon receipts that already landed, leaving those devices claimed for good and never sent to.

A run processes at most 20 pages per dispatch and 3 dispatches, and the function is given the 540s timeout that budget needs - the default 60s could not execute the work the code declares.
Because a run can outlive its own five-minute interval, the function is pinned to `maxInstances: 1` and `concurrency: 1`: two concurrent sweeps would read the same `deviceCursor` and the slower one's write would drag the drop back to a page already sent.
Belt and braces, a page boundary can only ever move the cursor **forward**, and `state: "sent"` is terminal - `planDispatchAdvance` refuses to move a finished dispatch back into the unfinished set.
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

**Watching it.** Every run logs `announceClimbDrops sweep completed` with its counters, or `announceClimbDrops sweep left drops unsent` at error level when a dispatch failed.
A non-zero `unclaimedCount` means Firestore refused some receipt creates; those devices are re-walked on the next run, so it is a signal to watch rather than a loss - unless it stays non-zero across runs.

## What it costs

Receipts accumulate at one document per device per drop.
They are only read while a dispatch is unfinished, so a completed drop's receipts are inert - worth expiring if the device count ever makes them matter, but not worth a TTL policy at the current fleet size.
