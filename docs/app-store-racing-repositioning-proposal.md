# App Store listing proposal: racing repositioning

Locale: en-US.
Status: **proposal**, not applied.

This file is a proposal for issue [#439](https://github.com/tpavay/AscendApp/issues/439).
Nothing here has been written to App Store Connect.
Firstmate owns App Store Connect metadata and applies it.

The currently-live listing copy is recorded in `data/ascend-support-page-and-product-page-package/app-store-copy.md`.
That file still describes the tracking product.
It should be updated to match whatever is actually applied to App Store Connect, and only then, so the repo keeps exactly one record of what is live.

## What this copy assumes about the app

Written against the app **after** [#437](https://github.com/tpavay/AscendApp/issues/437) lands.

Gone: Apple Health workout import, manual workout logging, and any framing of Ascend as a place to log or import training.
Kept: connecting Apple Health to enrich a climb performed *in Ascend*, live heart rate from a Bluetooth chest strap, Live Climbs, leaderboards, First Ascents, Best Efforts, guided routines, and the share composer.
For that enrichment, Ascend reads heart-rate samples, active and resting energy, and step count around the climb's own time window.
It may match Apple Health workout entries to find the right samples, which is why iOS still lists Workouts in the Health permission sheet.
The enrichment can attach available heart rate, active-energy calories, and average METs; it does not attach Apple Health step count or resting energy to the climb.
The legal pages describe the same read and attachment sets.

Do not apply this listing before #437 ships.
Until then the description would understate the app, which is harmless, but the App Review notes would still describe manual logging, which is not.

## App name

```text
Ascend: Stair Stepper Racing
```

28 characters of 30.
Settled by the captain on 2026-08-08.

## Subtitle

```text
Race real towers from any gym
```

29 characters of 30.
Settled by the captain on 2026-08-08.

## Keywords

```text
climber,stepmill,climb,steps,cardio,leaderboard,running,vertical,workout,compete,records,stairs,hiit
```

100 bytes of 100.

### How this set was derived

Apple indexes the app name and subtitle alongside the keyword field and combines tokens across all three into phrases.
The name supplies `ascend`, `stair`, `stepper`, `racing`; the subtitle supplies `race`, `real`, `towers`, `gym`.
None of those are repeated here, because a repeat buys nothing and costs bytes.

| Keyword | Why it earns its bytes |
|---|---|
| `climber` | Combines with the name's `stair` to cover "stair climber", the second most common name for the machine after StairMaster. |
| `stepmill` | The third common name for the machine, and a term nobody searching for a general fitness app types. |
| `climb` | The product's own verb, and the root of the queries that describe what Ascend does rather than what it runs on. |
| `steps` | Ascend's canonical metric, and the unit every climb target is expressed in. |
| `cardio` | The broadest term where a stair-stepper app has any legitimate claim, and the category a stepper user self-identifies with. |
| `leaderboard` | The differentiator. Anyone searching this is searching for competition, which is exactly the customer. |
| `running` | Only here to form "tower running" with the subtitle's `towers`, which is the name of the real sport this product is. |
| `vertical` | Forms "vertical climb" and reaches the Vertical World Circuit vocabulary that tower-running athletes already use. |
| `workout` | Discovery, not positioning. Machine queries are habitually phrased as "stairmaster workout" or "stair workout", and losing that traffic buys nothing. |
| `compete` | The intent word. Pairs with `climb`, `steps`, and the name to reach competitive rather than passive searchers. |
| `records` | Covers Best Efforts intent, "stair records" and "climb records". The weakest term in the set and the first to cut if something better appears. |
| `stairs` | Apple's plural handling is inconsistent, and `stairs` is how people actually type the query. Cheap insurance on the single most important token. |
| `hiit` | Four bytes for the routines feature and a high-volume interval-training query. Fills the field exactly. |

### Deliberately excluded

**`stairmaster`.** This is the highest-volume query in the category and the single biggest judgment call in the set.
It is also a registered trademark of Core Health & Fitness, which Ascend does not own.
Third-party marks in metadata are a routine App Review rejection under Guideline 5.2.1, and a metadata rejection on a first submission costs a review cycle at exactly the wrong moment.
Recommendation: launch without it.

If the captain accepts that risk, swap it in for `leaderboard`, which is the same 11 bytes:

```text
climber,stepmill,climb,steps,cardio,stairmaster,running,vertical,workout,compete,records,stairs,hiit
```

100 bytes of 100.

**`everest`, and mountain names generally.**
[#440](https://github.com/tpavay/AscendApp/issues/440) is curating unraceable mountains out of the catalogue.
Indexing on content that is being removed is a keyword spent on a promise the app will stop keeping.

**`treadmill`, `elliptical`, `peloton`.**
Adjacent-machine terms attract the wrong intent and dilute a listing whose whole strategy is being unmistakably about one machine.

**`fitness`, `training`, `gym` equivalents, `heart rate`, `intervals`, `routines`.**
Each of these is either too generic for a new app to rank on, already covered by a stronger token in the set, or a secondary feature Ascend would not win a search on.
`intervals` in particular loses to `hiit`, which is shorter and higher volume.

**Phrases with spaces.**
A space costs a byte and buys nothing, because Apple already forms phrases by combining single tokens across the name, subtitle, and keyword field.

### Dropped from the existing keyword set, and why

The live set is `workout,leaderboard,steps,cardio,gym,fitness,intervals,records,heart rate,training,routines`.
It was derived for a tracking product, and it reads like one: every term describes what the app stores rather than what the user does.

- `gym` moves into the subtitle, so it is free.
- `fitness` and `training` are generic category terms a launch app cannot rank on.
- `heart rate` spends 11 bytes including a space on a secondary feature.
- `intervals` and `routines` are replaced by the shorter, higher-volume `hiit`.

That frees the bytes for `climber`, `stepmill`, `climb`, `stairs`, `running`, `vertical`, and `compete`, which are the terms that describe racing a stair machine.

## Description

```text
Tower running is a real sport. Ascend puts it on the machine in front of you.

Athletes race the stairwells of the world's tallest buildings. Getting into one of those races takes a skyscraper, an event date, a travel budget, and a place in a limited field.

Ascend is that sport, on a stair stepper, on any day, from any gym.

Pick a tower. Race its real step count. Take your rank.

RACE REAL TOWERS

Choose a landmark and attack its actual step count: the Empire State Building, Taipei 101, the Eiffel Tower, Burj Khalifa, and more.
Motion sensors in compatible AirPods or Beats count your steps in real time.
Every attempt ever posted on that tower is the field you are racing.
Watch your position move while you climb.

CLIMB THE LEADERBOARDS

Every tower keeps its own rankings.
Compare finish times, cadence, and steps against real climbers.
Reach the podium, then defend it.

CLAIM FIRST ASCENTS

Every new tower opens with one permanent prize: the First Ascent.
The first finisher claims it forever, even after someone posts a faster time.
Be ready when the next tower drops.

BREAK YOUR OWN RECORDS

Best Efforts turns the races you finish into a record book only you can break.
Most steps, longest climb, strongest pace, and more, each tied back to the session that set it.
See the work stack up instead of disappearing when the session ends.

TRAIN BETWEEN RACES

Guided routines build structured intervals and changing intensity into a stair session.
Pair a Bluetooth chest strap for live heart rate and effort zones.
Every finished routine lands in the same history as your races.

SHARE THE CLIMB

Build a share card from the tower you raced and the result you posted.

Ascend is built for people who take the stair stepper seriously.
It is not a generic activity tracker and it is not a social feed.
Every climb and every record in Ascend comes from a session you performed in Ascend. There is no manual entry and no importing from other apps.

An auto-renewing subscription is required after onboarding.
Available plans, billing terms, and any eligible trial are shown before purchase.
Subscriptions can be managed through your Apple Account, and eligible purchases can be restored in Ascend.

Live Climbs and guided routines require compatible motion-equipped AirPods or Beats.
Apple Health is optional and is used only to attach heart-rate and energy data recorded while you were climbing in Ascend.
A Bluetooth heart-rate monitor is optional.
Ascend is not a medical device and does not provide medical advice.
```

2,530 characters of 4,000.

### What changed from the live description, and why

The live description opens with "Your stair-stepper work should count", which is a tracker's promise: it says the app will hold your effort for you.

This one opens by naming the sport.
Tower running exists, it is organised, and the only thing standing between a stepper user and it is a skyscraper they cannot get into.
That framing names the customer and answers "why does this not already exist" in the same breath, which "nobody does this" does not.

Three other changes carry the repositioning:

- The **KEEP YOUR HISTORY TOGETHER** section is gone. It promised logging and Apple Health import, both of which #437 removes. Its replacement is an explicit statement that everything in Ascend comes from a session performed in Ascend, which turns the removal into a credibility claim about the leaderboard rather than a missing feature.
- **Mt. Everest is gone** from the landmark examples, ahead of #440.
- The Apple Health footnote now says what Apple Health is actually for after #437: attaching heart-rate and energy data to a climb performed in Ascend, from an Apple Watch or any wearable that writes to Apple Health.

## Out of scope for this proposal

- **App Review notes.** They currently tell the reviewer that sessions can be logged manually, which becomes false the moment #437 lands. Replacing them with the hardware demo-video path is tracked in #437 and #439 and is not proposed here.
- **Screenshots.** Tracked separately in [#390](https://github.com/tpavay/AscendApp/issues/390).
- **In-app copy.** Tracked in #437.
- **The Superwall onboarding paywall** (`web/public/superwall/onboarding-paywall.html`). It promises nothing that #437 removes, but it does hard-code "Choose from 75 landmarks to climb", which #440 will make wrong. Worth a look when #440 lands.
