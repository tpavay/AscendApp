# Seasonal unlocks

October (Halloween) and November (Thanksgiving) are the first instance of Ascend's unlock system: items a climber earns by climbing and carries or wears up Ascend Mountain.
Earned only, never bought, cosmetic only, and drawn for everyone who races with you.

An athlete has five slots (`AthleteGear.Slot`): one carried item (`carry`), one on the head (`head`), a costume over the whole athlete (`costume`), and kit worn in place of the colours the climber picked (`shorts`, `trainers`).
A carried item sits on the right shoulder, is pressed overhead with both hands, or is held up on the palm out at the side like a waiter's platter; every hold is placed so the race camera, which films from behind, can see it, and the arms reach it with IK (`MountainCarryHold`).
Carried, head and costume items are shapes of their own riding the skeleton; kit is the athlete's own body redrawn in a colour that glows (`MountainKitColor`), since the shorts' texture coordinates are cut small across seams and the trainers have none.
A printed tank was tried and dropped: on the athlete it read as one colour, not a design.
Each slot is stored under its own name on `users/{uid}/athlete_look/current`, and `firestore.rules` lists the items each slot accepts.

## What a climber sees

The design is the captain's round-20 approval of 2026-10-02; the build handoff with its reference prototype is kept with the firstmate design record.

- Home carries a card for the running event right after Today's Climb (`HomeEventCard`): days left, "Halloween is on.", how much is earned ("4 of 15 earned. Climb for the rest."), and three of the event's items, never a photo of the athlete.
  Which three is the event's `showcase` in the catalogue.
  The card pushes the event's page.
- The event page (`UnlockEventPage`) has the haunted stairwell art for a haunted event, a back button and the days left, "Halloween is on." over "Every climb and every step in October earns something new.", then one ladder per way of earning (`UnlockLadder`): climbs (the open-app item first), steps, and days.
  Each ladder is a row of tiles showing the item itself, its name and its threshold as a bare count ("5 climbs", "10K steps", "7 days"), with a lime EARNED sash on earned tiles, an ON pill on what is worn, a dashed outline on the next item, and a small lock on the rest (`UnlockItemTile`).
  It ends on a Your Athlete row and a pinned START CLIMBING, which opens Home's start sheet.
- Tapping a tile opens the item (`UnlockItemView`): the climber's whole athlete, head to feet, wearing it where it really goes - a shoulder item on the shoulder, a giant pressed overhead - whether it is earned or not, with where it goes ("HELD OVER YOUR HEAD"), its rule ("50K steps in October"), and either "Earned in October" with EQUIP, or how far is left ("25,000 of 50,000 steps", "25,000 to go") with START CLIMBING.
  EQUIP saves the look and says so: "<Item> equipped / Everyone on the stairs sees it."
- Your Athlete (`AthleteEditorView`) is the one place a climber's gear lives: rows above the body choices for CARRIED, HEAD, KIT and FEET, each with an owned count, owned items first (`AthleteGearRows`).
  Tapping an earned item puts it on the preview straight away and tapping the worn one takes it off; tapping a locked one opens a line under its row with its rule and progress.
  Nothing is kept until SAVE ATHLETE, which reads SAVED.
  There is no separate Locker and no item page from here.
- An earned item reads NEW until the climber looks at it in Your Athlete, opens its page or equips it from anywhere (`UnlockStore.seen`), and the Your Athlete card on Profile shows a lime "<n> NEW" pill while any are waiting.
  The pill counts exactly the items whose Your Athlete cell reads NEW: never one the athlete is wearing, and never one Your Athlete does not draw (`UnlockStore.newItems(wearing:)`).
- The first open during an event still shows `UnlockEventIntroView`, in the page's words: the item everybody gets for opening Ascend that month, revealed on the climber's own athlete (`UnlockRevealView`), and the ladder of what climbing earns as bare counts.
  It is shown once per event per account, after the period recap and never over it (`MainTabView.presentUnlockIntroIfNeeded`).
- Every climb saved during an event shows `UnlockFinishCard` on the summary: the item that climb earned, revealed the same way, with EQUIP ON YOUR ATHLETE, or how far the next item is.
- What an athlete has on is drawn on the climber's athlete and on every rival wearing something (`MountainAthleteRig.wear`).
- During Halloween the first steps of every climb are the haunted stretch (below).

## The catalogue

One file, hosted beside the climb catalogue and bundled as a fallback:

- Hosted: `web/public/unlocks/catalog.json`, served at `https://<project>.web.app/unlocks/catalog.json` with a five-minute cache.
- Bundled: `AscendApp/Features/Athlete/Resources/unlock-catalog.json`, which must be byte-identical to the hosted file (`UnlockTests.theBundledCatalogueIsTheHostedOne`).

Each event has an id, a title ("Halloween"), a month name ("October") and its days (`startsOn`, `endsBefore`, read in the climber's own time zone).
Each item names the shape it is drawn as, its slot, a rarity, a status (`hidden`, `live`, `retired`) and how it is earned (`path: event`, the event id, `metric` of `visits`, `climbs`, `days`, `onDay` or `steps`, and a threshold).
Every climb saved with progress counts toward `climbs`, `days`, `onDay` and `steps`, whether it reached the top or not: a live climb stopped short and saved, a routine stopped partway, a session recovered after the app closed.
A climb with no steps is not progress and never counts (`UnlockClimbQuery`).
Climbs saved before the climber had this build count too: progress is derived from every climb in the local store inside the event's days, never from a tally that starts at install, so a climber who updates mid-October gets every October climb already saved, on every ladder, the first time the new build opens.
That first open recounts before the event intro shows, and the intro says what those climbs already earned ("Your October climbs already earned 4 more.") with those rungs marked earned, rather than leaving them to be found later.
`days` counts different days with a saved climb, so a threshold of the event's length is "every day"; `onDay` is a climb on one day of the event, counted from 1, so 31 is Halloween itself.
An event may also carry a `theme`, how it dresses the mountain, and a `showcase`, the ids of the three items its Home card shows (its first three items when absent).

Without a build, the file can move an event's dates, change a threshold, or switch a shipped item live ("ship dark, drop live").
Setting an item `retired` stops new earning only: the event page, the intro and the finish card drop it, while Your Athlete keeps it, earned and wearable, for every climber who already earned it (`UnlockCatalog.gearItems`).
A retired item may carry a `retiredOn` day: a new phone earns it back from the climbs before that day and never from a climb on or after it (`UnlockCatalog.retiredItems`).
A retired item with no `retiredOn` is never re-derived, so only the device that remembered it keeps it.
An item the athlete is wearing always shows in Your Athlete as owned, so it can be taken off.
A new shape needs a build: `AthleteGear` and `MountainGearModel` draw it.
An item whose shape, slot or way of earning a build does not know is skipped by that build, never fatal (`UnlockTests.anItemThisBuildCannotDrawIsSkippedNotFatal`).
`firestore.rules` lists the items each slot accepts, so a new shape also needs a rules deploy before the build that offers it.

## How an item is earned

The climber's own phone counts it, from Ascend-recorded climbs (`WorkoutSource.headphoneMotion`) inside the event's days (`UnlockClimbQuery`, bounded by the event, never the whole history).
A reinstall restores those climbs from the cloud backup, so a new phone earns the same climbing items back.
Opening Ascend during an event earns its `visits` item (`UnlockStore.recordVisit`).
That visit is remembered only on this device for the signed-in account, so the open-app item is scoped to the device and the account session: after a sign-out or a reinstall it comes back only from a climb in the event, since any climb in the event also counts as a visit.
A climber who opened Ascend during October but never climbed, then signs out or reinstalls after the event, loses the Pumpkin; keeping it would need the visit stored on the account, which `users/{uid}/athlete_look/current`'s key list does not allow without a rules change.
What was earned is remembered on the device per account (`UnlockStore.earnedKey`) and cleared on sign-out, so an unlock outlives a later change to an event's dates.
No surface shows the day an item was earned: an earned item reads "Earned in October".

This is a deliberate first step.
The general unlock plan moves deciding who earned what to a server job that writes where only the server can, and checks ownership before publishing an outfit.
Until that exists, what a look wears on `users/{uid}/athlete_look/current` is bounded to the known items but not to what the climber earned: a cosmetic, so the rule bounds the value rather than the evidence.

## The haunted stretch

Halloween's `theme` (`{"style": "haunted", "steps": 5000}`) dresses the first steps of every climb, starting wherever the climber's journey resumes, so a climber high up the mountain sees it as surely as a new one (`MountainHauntedStretch`).
The regions inside it keep their slopes and take a night palette and a purple sky; lit jack-o'-lanterns stand on the kerb every ten steps, alternating sides, with a ghost drifting beside one in six; gates inside it carry a lantern on each pillar, one lit orange and one purple, webs in the corners and spiders on threads (`MountainHauntedProps`).
Changing the length, or dropping the theme, is a catalogue edit.

## Off switch

`unlocks_enabled` (`RemoteFeatureFlag.unlocks`) hides every unlock surface: nothing worn is drawn, no Home card, no event page, no intro, no finish card, no gear rows, no NEW pill, no haunted stretch.
It writes and deletes nothing, and earned items come back with it (`docs/remote-config-kill-switches.md`).

## Cost on the mountain

Each item is one mesh of a few thousand triangles at most (`UnlockTests.everyItemIsCheapAndRestsOnItsSeat`), made once and shared by every climber carrying it, with no skeleton of its own.
Only the climber's own glowing item carries a point light (`MountainRigFactory.Request.castsLight`); a rival's carved face glows from an unlit decal.
The haunted stretch's lanterns and ghosts are the same shared meshes with no lights of their own; only its gates carry two lights each, and at most two gates stand in view.

## The seasonal app icon

This build ships the jack-o'-lantern A as the primary icon (`AppIcon`) and the lime A as an alternate (`AppIconClassic`, `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`).
A climber can switch back any time in Settings -> App Icon (`AppIconSelectionView`).
iOS shows a system alert whenever an app changes its own icon, so Ascend never switches it automatically.

To end the season, in the first release after October:

1. Copy `AppIconClassic.appiconset`'s image into `AppIcon.appiconset` (named `AscendAppIcon.png`, updating its `Contents.json`).
2. Remove the alternate (`AppIconClassic`, the build setting, `AppIconChoice.classic` and the Halloween preview image), or keep the jack-o'-lantern as an alternate if climbers ask for it.

A climber who picked the classic alternate keeps an icon iOS can no longer find if the alternate is deleted; iOS falls back to the primary, which is then the lime A again.

## App Store In-App Event copy (drafts, not created)

Create these in App Store Connect by hand; nothing here creates them.
Limits: name 30 characters, short description 50, long description 120.

**Halloween, October 1-31**

- Name: October Pumpkin Climbs
- Short description: Climb in October. Earn pumpkins to carry up.
- Long description: Open Ascend in October: your pumpkin is in. Climb for a witch hat, a ghost sheet, and the Giant Jack-o'-Lantern.
- Badge: Challenge.
- Event card and detail art: the race-camera stills of the Giant Pumpkin and the Jack-o'-Lantern.

**Thanksgiving, November 1-30**

- Name: November Harvest Climbs
- Short description: Climb in November. Carry the harvest up.
- Long description: Open Ascend in November: your Harvest Gourd is in. Climb for the Pumpkin Pie, the Cornucopia and the Giant Turkey.
- Badge: Challenge.
