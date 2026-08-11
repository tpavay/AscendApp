# Heart Rate & Cadence Zones + Device Connectivity

Status: **Partly shipped; the zones work is POST-LAUNCH - parked.** Captured June 11, 2026.
Tier A (BLE chest straps) and shared live HR capture have since shipped - see "Already shipped"
below. Everything else here waits on the launch blockers in
[launch-readiness-audit.md](launch-readiness-audit.md).
WWDC26 API claims verified against [session 207](https://developer.apple.com/videos/play/wwdc2026/207/).

---

## What WWDC26 introduced

*Deliver workout insights with HealthKit workout zones* (WWDC26 session 207). In iOS/watchOS 27,
HealthKit has heart-rate zones built in as a first-class concept:

- Read zones from a finished workout (`zoneGroupsByType`) → time spent in each zone, for
  post-workout charts.
- Live zone updates during a workout (`HKLiveWorkoutBuilder` delegate, `didUpdateWorkoutZone`) →
  real-time "you crossed into Zone 4" events.
- Zone boundaries come from Apple's personalized defaults (age / resting HR, synced from Health
  settings) or a custom model we define (`HKWorkoutZoneConfiguration` — source enum distinguishes
  System / User / App-supplied thresholds).

**The catch:** this is heart-rate based, and live HR via this API comes from an Apple Watch running
a workout session. It does nothing for users without a Watch — and nothing for our core
headphone-motion signal.

## What we want to build

Two parallel zone systems, presented with one shared UI — directly analogous to Strava's
heart-rate zones + pace zones:

1. **Cadence (SPM) zones — the universal layer.** Built on our headphone-motion step data. We
   define the SPM bands (Recovery / Steady / Push / Sprint), compute current SPM on a rolling
   window, bucket it, track time-in-zone, and fire our own zone-crossing events. No Watch, no
   extra hardware — works for every user on day one. This is our "pace zone" equivalent (cadence
   is the natural intensity proxy on a stepper since there's no horizontal pace).
2. **Heart-rate zones — the enhanced layer.** Real physiological effort, when the user has an HR
   device. Apple Watch gives us this natively via session 207; other devices we read directly
   (see below).

Both use the same visual language: live zone indicator during a climb, time-in-zone chart in the
post-climb summary, and zone stats as draggable stickers in the share composer. Splits break each
climb into landmark segments (floors, base-camp-to-summit stages) with avg SPM, avg HR, and
dominant zone per segment — reads like a Strava split table, on-brand with the landmark framing.

> SPM tells us what the user did; HR tells us what it cost. The divergence over a climb (cadence
> flat, HR rising) is itself a fatigue insight.

## Device connectivity — the strategy

The goal is the experience you already get with a Polar H10 on a treadmill: strap on, start
climbing, it just reads. The key realization is that the five devices don't need five
integrations. They collapse into three tiers, and most of them land in one.

**First principle: the iPhone is Bluetooth LE only — it cannot receive ANT+.** Any device that
only broadcasts over ANT+ is invisible to us device-free. This is the single biggest filter, and
it's what makes Garmin hard.

### Tier A — Standard BLE Heart Rate Profile → ONE CoreBluetooth code path

Any device that advertises the standard BLE Heart Rate Service streams live HR the same way. We
implement CoreBluetooth against that one standard service once, and every compliant device works
identically — this is the "treadmill just works" experience, because gym equipment is doing
exactly this.

- **Polar H10 chest strap** — standard BLE HR. Works out of the box.
- **Morpheus chest strap** — Polar-based BLE strap; expected to broadcast standard BLE HR
  (verify the specific model).
- **WHOOP** — has a HR Broadcast mode that makes it a standard BLE HR strap (real-time, no
  backfill). The user must toggle "HR Broadcast" ON in the WHOOP app. No ANT+. When on, it's just
  another Tier A device.
- **Garmin dedicated straps (HRM-Pro, HRM-Dual)** — broadcast standard BLE HR. Tier A.
- *(Bonus: Wahoo TICKR, CooSpo, etc. all fall here for free.)*

### Tier B — Apple Watch → HealthKit

Apple Watch doesn't broadcast standard BLE HR to third-party apps; we get it through HealthKit
instead — and that's the good path, because it's also where session 207's native HR zones come
from. Requires a small watchOS companion app that starts an `HKWorkoutSession`, mirrored to the
iPhone so our existing UI shows live HR + zones. Best experience of the bunch (free Apple zones,
calories, etc.), at the cost of maintaining a watchOS target.

### Tier C — Closed ecosystems via cloud API (delayed, NOT live)

For devices that won't broadcast live BLE, we can only enrich the post-climb summary after the
fact, not drive live zones.

- **Garmin watches** — most broadcast only over ANT+ (unreadable by iPhone); BLE broadcast is
  limited to a few models and sometimes only in "Virtual Run" mode. Live HR from a Garmin watch
  is therefore unreliable-to-impossible device-free. Fallback: the Garmin Health/Connect API
  (OAuth, server-to-server) syncs the activity afterward.
- **WHOOP without broadcast on** — the WHOOP API provides HR/strain after the workout.

### Device summary

| Device | How we read it | Live in-climb zones? |
|---|---|---|
| Apple Watch | HealthKit (`HKWorkoutSession` + mirroring) | Yes — native Apple HR zones (207) |
| Polar H10 | CoreBluetooth, standard BLE HR | Yes |
| Morpheus strap | CoreBluetooth, standard BLE HR (verify) | Yes |
| WHOOP (HR Broadcast on) | CoreBluetooth, standard BLE HR | Yes |
| Garmin HRM strap | CoreBluetooth, standard BLE HR | Yes |
| Garmin watch | Garmin cloud API (or ANT+, which we can't read) | No — summary only, after sync |

So: one CoreBluetooth integration covers every chest strap + Whoop-in-broadcast, the Apple Watch
is a second (and nicest) path, and only Garmin watches are genuinely awkward — and there the
honest answer is "summary data after the climb," not live.

## The seamless experience we're aiming for

User starts a live session inside Ascend. No HR-device fiddling. The app:

1. On session start, scan for a remembered BLE HR peripheral (the strap/Whoop the user paired
   before) and auto-connect silently if it's advertising — exactly the H10-on-a-treadmill
   behavior.
2. Else, if a paired Apple Watch is present → prompt once to start/mirror the watch workout;
   thereafter auto-start so HR + Apple zones appear in the app, and the session shows on the watch.
3. Else, run the session on SPM cadence zones alone — full zone experience, no hardware required.

First-time pairing is the only manual step; after that it's automatic. HR zones layer on top of
the always-present SPM layer whenever a source is connected.

The strap-before-Watch ordering above is a standing rule, not a plan decision - see the
heart-rate tripwire in [CLAUDE.md](../CLAUDE.md), which owns it.

**Already shipped:** live BLE strap sampling, throttling, source selection, and the saved
avg/max/series summary are one shared pipeline (`LiveHeartRateRecorder`) used by Live Climb,
Just Climb, and routine sessions alike.
Apple Watch is declared in `LiveHeartRateSourceKind` as the lower-priority source but has no
implementation yet, so Tier B below is still unbuilt.

## Open items to confirm

- Does the specific Morpheus strap expose the standard BLE Heart Rate Service? (Almost certainly,
  but verify the model.)
- Decide whether the watchOS companion app is in scope for v1 of this feature, or whether we ship
  Tier A (straps) + SPM zones first and add Apple Watch native zones next.
- Confirm whether a fitness/workout App Schema domain exists in iOS 27 (affects the Siri "start a
  climb" integration, tracked separately).
- Garmin/Whoop cloud API enrichment is a later, lower-priority add — live BLE covers the users
  who want real-time.

Source for HR feature: WWDC26 session 207. Device BLE capabilities verified June 2026 (WHOOP HR
Broadcast; Garmin ANT+/BLE broadcast limitations).

---

## Ascend architecture intersections (added at capture — check before building)

How this plan collides with existing CLAUDE.md / project skill rules and the codebase:

1. **Watch companion vs. the no-HealthKit-writes rule.** Per the `ascend-live-climbs` skill, the
   live-session background-execution helper "must not write HealthKit workouts or request new
   Health permissions." A watchOS `HKWorkoutSession` *writes a workout to Health by design*.
   Different component, so not a direct contradiction - and since #437 there is no import facade
   for it to collide with: Ascend never reads a foreign `HKWorkout`, so a watch-written workout
   cannot re-enter as a separate session. What it *would* do is publish `heartRate` and
   `activeEnergyBurned` samples inside the climb's own window, which is exactly what enrichment
   reads - so the risk to design for is Ascend's own writes being read back as enrichment, not a
   duplicate import. See `ascend-apple-health-enrichment`.
2. **BLE HR is a sensor source — use the existing seams.** Sensor capture lives behind the
   shared service layer; checkpoints are source-neutral. Tier A shipped as
   `BluetoothHeartRateClient` / `HeartRateMonitorService` (`CBCentralManager` against Heart Rate
   Service `0x180D`), and its samples flow through the shared `LiveHeartRateRecorder` into the
   existing heart-rate sidecar (`users/{uid}/workout_heart_rate/...`). A new source must reuse
   that recorder rather than grow a parallel pipeline.
3. **Compliance ripple (same-PR rule).** CoreBluetooth requires `NSBluetoothAlwaysUsageDescription`
   in Info.plist — present today, added with the Tier A strap integration.
   Privacy manifest + App Store privacy labels + privacy policy must move in the same PR per the
   `ascend-privacy-manifest` skill. Heart-rate collection is already declared via HealthKit
   types; verify Bluetooth-sourced HR doesn't change the declared sources.
4. **watchOS target = real maintenance surface.** The third target now exists: `AscendWatch`
   landed in #470 as a static face with no HealthKit, no `HKWorkoutSession`, and no connectivity,
   so Tier B is still unbuilt and this note's lean still holds: ship Tier A straps + SPM zones
   first. Most of the maintenance surface is already paid for - the CI platform and runtime guards
   are in place, and signing is wired end to end - while anything Health-related on the watch
   remains outstanding. The watch app is targeted at the 1.0 submission, so its App Store listing
   artwork is the captain's listing work rather than an open question this plan carries.
   `ascend-deploy` owns the CI and signing side.
5. **SPM zone bands must stay absolute.** Per Workout Measurement rules, no user-calibrated
   effort baselines (base level is deprecated). Apple's personalized HR zones are Apple's model —
   fine. Our SPM bands should be product-defined absolute bands (content-driven, tunable
   server-side), not a reintroduction of per-user calibration.
