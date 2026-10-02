# Seasonal unlocks

October (Halloween) and November (Thanksgiving) are the first instance of Ascend's unlock system: items a climber earns by climbing and carries or wears up Ascend Mountain.
Earned only, never bought, cosmetic only, and drawn for everyone who races with you.

An athlete has six slots (`AthleteGear.Slot`): an item carried on the right shoulder, pressed overhead or held out like a tray (`carry`), one on the head (`head`), a costume over the whole athlete (`costume`), and kit worn in place of the colours the climber picked (`tank`, `shorts`, `trainers`).
Carried, head and costume items are shapes of their own riding the skeleton; kit is the athlete's own body redrawn (`MountainKitPrint`): the tank carries clean texture coordinates and takes a tiled print, while the shorts' are cut across seams and the trainers have none, so theirs is a colour that glows.
Each slot is stored under its own name on `users/{uid}/athlete_look/current`, and `firestore.rules` lists the items each slot accepts.

## What a climber sees

- The first open during an event shows `UnlockEventIntroView`: the item everybody gets for opening Ascend that month, revealed on the climber's own athlete (`UnlockRevealView`: the athlete faces you, the item bursts in, hovers, and lands where it is worn), and the ladder of what climbing earns.
  It is shown once per event per account, after the period recap and never over it (`MainTabView.presentUnlockIntroIfNeeded`).
- Every climb finished during an event shows `UnlockFinishCard` on the summary: the item that climb earned, revealed the same way, with EQUIP ON YOUR ATHLETE, or how far the next item is.
- The Locker (`LockerView`, opened from the athlete editor) holds every item of every event that has opened, by where it goes - carry, head, costume, kit, feet - earned ones ready to wear and the rest showing how far the climber is; tapping an earned item puts it on, tapping it again takes it off.
- What an athlete has on is drawn on the climber's athlete and on every rival wearing something (`MountainAthleteRig.wear`).
- During Halloween the first steps of every climb are the haunted stretch (below).

## The catalogue

One file, hosted beside the climb catalogue and bundled as a fallback:

- Hosted: `web/public/unlocks/catalog.json`, served at `https://<project>.web.app/unlocks/catalog.json` with a five-minute cache.
- Bundled: `AscendApp/Features/Athlete/Resources/unlock-catalog.json`, which must be byte-identical to the hosted file (`UnlockTests.theBundledCatalogueIsTheHostedOne`).

Each event has an id, a title ("Halloween"), a month name ("October") and its days (`startsOn`, `endsBefore`, read in the climber's own time zone).
Each item names the shape it is drawn as, its slot, a rarity, a status (`hidden`, `live`, `retired`) and how it is earned (`path: event`, the event id, `metric` of `visits`, `climbs`, `days` or `steps`, and a threshold).
`days` counts different days with a finished climb, so a threshold of the event's length is "every day"; `onDay` is a climb on one day of the event, counted from 1, so 31 is Halloween itself.
An event may also carry a `theme`, how it dresses the mountain.

Without a build, the file can move an event's dates, change a threshold, or switch a shipped item live ("ship dark, drop live").
A new shape needs a build: `AthleteGear` and `MountainGearModel` draw it.
An item whose shape, slot or way of earning a build does not know is skipped by that build, never fatal (`UnlockTests.anItemThisBuildCannotDrawIsSkippedNotFatal`).
`firestore.rules` lists the shapes a look may carry, so a new shape also needs a rules deploy before the build that offers it.

## How an item is earned

The climber's own phone counts it, from Ascend-recorded climbs (`WorkoutSource.headphoneMotion`) inside the event's days (`UnlockClimbQuery`, bounded by the event, never the whole history).
A reinstall restores those climbs from the cloud backup, so a new phone earns the same items back.
Opening Ascend during an event earns its `visits` item (`UnlockStore.recordVisit`).
What was earned is remembered on the device per account (`UnlockStore.earnedKey`) and cleared on sign-out, so an unlock outlives a later change to an event's dates.

This is a deliberate first step.
The general unlock plan moves deciding who earned what to a server job that writes where only the server can, and checks ownership before publishing an outfit.
Until that exists, `carry` on `users/{uid}/athlete_look/current` is bounded to the known shapes but not to what the climber earned: a cosmetic, so the rule bounds the value rather than the evidence.

## The haunted stretch

Halloween's `theme` (`{"style": "haunted", "steps": 5000}`) dresses the first steps of every climb, starting wherever the climber's journey resumes, so a climber high up the mountain sees it as surely as a new one (`MountainHauntedStretch`).
The regions inside it keep their slopes and take a night palette and a purple sky; lit jack-o'-lanterns stand on the kerb every ten steps, alternating sides, with a ghost drifting beside one in six; gates inside it carry a lantern on each pillar, one lit orange and one purple, webs in the corners and spiders on threads (`MountainHauntedProps`).
Changing the length, or dropping the theme, is a catalogue edit.

## Off switch

`unlocks_enabled` (`RemoteFeatureFlag.unlocks`) hides every unlock surface: nothing worn is drawn, no intro, no finish card, no editor row, no haunted stretch.
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
- Long description: Open Ascend in November: your Harvest Gourd is in. Climb for the Pie, Cornucopia, Roast Turkey and the Giant Turkey.
- Badge: Challenge.
