# Verified real stair counts

This file is the source record for every `realStairCount` in the climb catalogue.

A climb's step count is its race distance, so each number here is a claim that needs a citable source.
Populate `realStairCount` only from a source listed below or added below in the same change.
Never derive a race distance from architectural height.

## Why the catalogue carries two step numbers

`totalSteps` is the architectural-height derivation, `round(totalHeightMeters * 5.5)`.
It is not a route: for a tower it includes antenna spire nobody climbs, and for a mountain it converts elevation above sea level rather than any ascent.
It stays in the catalogue because it is an honest answer to "how tall is this", and it is what the globe and card art frame against.

`realStairCount` is the number of steps on the route people actually climb.
`Climb.referenceStepCount` resolves `realStairCount ?? totalSteps`, and that single value is what Ascend races on, ranks on, and derives `ClimbTier` from.

Correcting a distance therefore means populating `realStairCount`.
It never means rewriting `totalSteps`.

## Rules for adding a number

- Cite a primary source: the venue owner, the event organiser, the custodian body, or the Towerrunning World Association race record.
- Where published figures disagree materially, record the disagreement in the Conflicts section rather than silently picking one.
- Where no defensible figure exists, leave `realStairCount` null.
  A height-derived guess shipped as a race distance is worse than an admitted gap.
- Recompute `tier` from the corrected `referenceStepCount` against the thresholds in `AscendApp/Features/Climbs/Models/ClimbTier.swift`.
- Apply the same change to both catalogue files; `AscendAppTests/ClimbCatalogStairCountTests.swift` enforces that they stay byte-identical and that every tier matches its reference count.

Confidence levels used below:

- **High** - the venue owner or event organiser publishes the figure, and at least one independent source agrees.
- **Medium** - a single authoritative source, with no contradiction found.
- **Low** - sources disagree materially; the number ships with the conflict recorded.

## Raced venues

The figure is the sanctioned race distance, from the organiser and/or the Towerrunning World Association archive.

| Climb | `realStairCount` | Route | Confidence | Source |
|---|---:|---|---|---|
| Shanghai Tower | 3,398 | 119F, 552 m | High | <https://www.towerrunning.com/races/r1372/>, corroborated by the Towerrunning Tour Final previews |
| Lotte World Tower | 2,917 | 123F, 498 m | High | Lotte World Tower Skyrun, <https://www.towerrunning.com/races/r3212/>, plus Korean press |
| Merdeka 118 | 2,845 | 118F | High | The Sky Race, <https://theskyrace.com/>, plus Malaysian press |
| Canton Tower | 2,738 | 112F, 450 m gain | Medium | Canton Tower Run Up, <https://www.towerrunning.com/races/r2871/> |
| One World Trade Center | 2,226 | level -2 to 102 | High | T2T Climb New York City, <https://www.towerrunning.com/races/r2460/> |
| Willis Tower | 2,149 | 105 flights | High | SkyRise Chicago organiser figure, <https://theskydeck.com/skyrise-chicago/>; see Conflicts |
| Taipei 101 | 2,046 | 1F to 91F observatory | High | CTBC Taipei 101 Run Up, <https://www.taipei101-runup.com.tw/2024/en/en_introduction.aspx> |
| CN Tower | 1,776 | 144 flights | High | WWF Climb for Nature, <https://wwf.ca/climb-for-nature/> |
| Empire State Building | 1,576 | 86 flights to the 86F deck, 1,050 ft | High | <https://www.esbnyc.com/2025-esb-run-up> |
| Oriental Pearl Tower | 1,566 | 90F | Medium | Shanghai Citizen Oriental Pearl New Year Run-Up Challenge, <https://www.towerrunning.com/races/r3138/> |
| Q1 Tower | 1,331 | 77F | High | SkyPoint Sea to Sky Q1 Stair Challenge, <https://www.towerrunning.com/races/r2987/> |
| Sky Tower (Auckland) | 1,103 | 51F | High | Step Up Sky Tower Challenge, <https://www.stepupchallenge.org.nz/> |
| Reunion Tower | 837 | ground to GeO-Deck, 61 landings | High | Reunion Tower fact sheet, plus Dash to the Deck, <https://www.towerrunning.com/races/r3210/> |
| Space Needle | 832 | 98 flights to the 520 ft deck | High | <https://www.spaceneedle.com/base2space> |
| Torre Latinoamericana | 720 | 42F | High | Carrera Vertical Torre Latino, <https://www.towerrunning.com/races/r3202/> |
| Farol Santander | 578 | 26F of the Edificio Altino Arantes | High | Santander Track&Field Run Series, plus <https://www.towerrunning.com/races/r3075/> |
| Tokyo Tower | 500 | stair race, 150 m height gain | Medium | <https://www.towerrunning.com/races/r2457/>, 14 editions; see Conflicts |

## Published stair routes

Not a sanctioned race, but a documented staircase with a published count.

| Climb | `realStairCount` | Route | Confidence | Source |
|---|---:|---|---|---|
| Burj Khalifa | 2,909 | 160F fire stairwell | High | Figure used by every sanctioned Burj Khalifa climb and by Emaar; <https://www.towerrunning.com/2020/05/15/charity-challenge-burj-khalifa-virtual-climb/> |
| Eiffel Tower | 1,665 | ground to the summit, 279 m | High | <https://www.toureiffel.paris/en/news/events/eiffel-tower-vertical> |
| Eureka Tower | 1,642 | 88F to Melbourne Skydeck | High | Eureka Climb, run annually since 2008 |
| Monserrate | 1,605 | IDRD sendero peatonal | High | <https://www.idrd.gov.co/parques-y-escenarios/sendero-de-monserrate>, plus <https://bogota.gov.co> |
| Sydney Tower | 1,504 | ground to the Sydney Tower Eye platform | High | Sydney Tower Eye Stair Challenge, <https://www.sydneytowereye.com.au/plan-your-day/information/news/sydney-tower-eye-stair-challenge/> |
| Gateway Arch | 1,076 | emergency stairway, one leg | High | <https://www.nps.gov/jeff/planyourvisit/gateway-arch-fact-sheet.htm>; **public access forbidden** |
| Berlin TV Tower | 986 | ground to the 203 m deck | Medium | <https://tv-turm.de/>; service and emergency stair, not normally public |
| Washington Monument | 897 | ground to the observation level | High | National Park Service; **closed to the public since 1971** |
| El Penon de Guatape | 740 | masonry staircase plus the summit tower | Low | Guatape tourism and the count painted at the summit; see Conflicts |
| St. Peter's Basilica | 551 | ground to the top of the dome | High | <https://www.basilicasanpietro.va/en/help/the-dome> |
| Statue of Liberty | 377 | 215 to the pedestal top + 162 to the crown | High | <https://www.nps.gov/stli/planyourvisit/visiting-the-pedestal.htm> |
| Elizabeth Tower | 334 | ground to the belfry | High | <https://www.parliament.uk/visiting/visiting-and-tours/big-ben-tour/> |
| Sacre-Coeur | 300 | ground to the dome | Medium | Basilica dome visit; see Conflicts |
| Leaning Tower of Pisa | 296 | ground to the belfry, south stair | Low | Opera della Primaziale Pisana visitor material; see Conflicts |
| Charminar | 149 | ground to the upper floor | High | Telangana state tourism, <https://hyderabad.telangana.gov.in/tourist-place/charminar/> |

## Climbed vertical

`realClimbableHeightMeters` is populated only where a source pairs the stair route with its own vertical figure.
`Climb.referenceHeightMeters` resolves `realClimbableHeightMeters ?? totalHeightMeters`, and today that value only drives globe and card camera framing.
Where the climbed vertical is not published, the field stays null rather than carrying an inferred number.

| Climb | Metres | Feet | Source |
|---|---:|---:|---|
| Shanghai Tower | 552 | 1,811.0 | TWA race record, 119F |
| Lotte World Tower | 498 | 1,633.9 | TWA race record, 123F |
| Canton Tower | 450 | 1,476.4 | TWA race record, elevation gain |
| Empire State Building | 320 | 1,050.0 | ESB Run-Up, 86F deck at 1,050 ft |
| Eiffel Tower | 279 | 915.4 | Verticale de la Tour Eiffel, ground to summit |
| Berlin TV Tower | 203 | 666.0 | Observation deck height |
| Space Needle | 158.5 | 520.0 | Base 2 Space, 520 ft deck |
| Tokyo Tower | 150 | 492.1 | Race height gain; the Main Deck stair ends at the same 150 m |

## Floor counts

`calculatedFloors` renders as FLOORS directly beside STEPS on climb detail, so it has to answer for the same route the step count answers for.
It was originally `round(totalHeightMeters / 3.6)`, the same architectural-height derivation as `totalSteps`, which put a corrected step count next to an uncorrected floor count: Monserrate read 1,605 steps over 876 floors, Tokyo Tower 500 over 93.

Every climb carrying a `realStairCount` now takes its floor count from one of two places, in this order:

1. **The route's published storey count**, where a source in the tables above states one.
2. **`round(referenceStepCount / 19.8)`** otherwise.

19.8 is the ratio the height derivation already implied (`5.5` steps per metre over `3.6` metres per floor), so the 43 climbs with no verified stair count keep the floor counts they had - their reference count is still `totalSteps`, and the two rules agree there.

A published **flight** count is not a storey count and is not used as one, unless a second independent source states the same figure as storeys.
A flight is a run of stairs between landings; a tower can have several per storey, or none at all.
So the figure alone never qualifies a route for the published table - a source has to say the word.

Willis Tower is the one climb that clears that bar.
SkyRise Chicago words its own figure as 105 flights, and the Towerrunning World Association record for the same race states it as storeys: "since 2018 start at level -2 making it 105 stories to climb".
Level -2 to 103 is consistent with that count, so 105 ships as the storey count rather than being derived.

`AscendAppTests/ClimbCatalogStairCountTests.swift` enforces that every climb's steps-per-floor stays inside a plausible band, which is what stops a height-derived floor count from coming back.

### Published storey counts

| Climb | `calculatedFloors` | Source |
|---|---:|---|
| Burj Khalifa | 160 | 160F fire stairwell, per the Raced venues and Published stair routes tables above |
| Lotte World Tower | 123 | 123F, Lotte World Tower Skyrun |
| Shanghai Tower | 119 | 119F, TWA race record |
| Merdeka 118 | 118 | 118F, The Sky Race |
| Canton Tower | 112 | 112F, Canton Tower Run Up |
| Willis Tower | 105 | SkyRise Chicago's 105 flights, level -2 to 103, corroborated as storeys by the TWA race record: "105 stories to climb"; see Conflicts |
| One World Trade Center | 104 | level -2 to 102, T2T Climb New York City |
| Taipei 101 | 91 | 1F to 91F observatory |
| Oriental Pearl Tower | 90 | 90F, Oriental Pearl New Year Run-Up |
| Eureka Tower | 88 | 88F to Melbourne Skydeck |
| Empire State Building | 86 | 86F observation deck, ESB Run-Up |
| Q1 Tower | 77 | 77F, SkyPoint Sea to Sky |
| Sky Tower (Auckland) | 51 | 51F, Step Up Sky Tower Challenge |
| Torre Latinoamericana | 42 | 42F, Carrera Vertical Torre Latino |
| Farol Santander | 26 | 26F of the Edificio Altino Arantes |

### Derived floor counts

These carry no published storey count for the route, so `calculatedFloors` is `round(referenceStepCount / 19.8)` and is derived, not sourced.

CN Tower 90, Eiffel Tower 84, Monserrate 81, Sydney Tower 76, Gateway Arch 54, Berlin TV Tower 50, Washington Monument 45, Space Needle 42, Reunion Tower 42, El Penon de Guatape 37, St. Peter's Basilica 28, Tokyo Tower 25, Statue of Liberty 19, Elizabeth Tower 17, Leaning Tower of Pisa 15, Sacre-Coeur 15, Charminar 8.

Three of these do have a published count, but of flights or landings rather than storeys, and no second source restates it as storeys the way the TWA record does for Willis Tower.
So it is recorded here and not shipped as a floor count:
CN Tower is 144 flights to the LookOut, Space Needle is 98 flights to the 520 ft deck, and Reunion Tower is 61 landings to the GeO-Deck.
The Space Needle figure is the clearest case - 832 steps over 98 flights is 8.5 steps each, and 98 storeys would put a 184 m tower above 350 m.

## Conflicts, stated rather than silently resolved

**Willis Tower. 2,149 / 2,159 / 2,109.**
SkyRise Chicago's own page says 2,149 stairs over 105 flights.
The Towerrunning World Association record says 2,159 over 105 floors, noting "since 2018 start at level -2 making it 105 stories to climb".
The older 2,109 figure is the count to the 103rd floor, before the start moved two levels down.
The catalogue ships the organiser's own current number, 2,149, and the 10-step gap against TWA is unresolved.

**Tokyo Tower. 500 raced / about 600 public.**
The TWA record for the Tokyo Tower stair race is 500 stairs over a 150 m height gain, across 14 editions.
Tokyo Tower's own site advertises the Open-Air Outdoor Stairs Walk as about 600 steps to the 150 m Main Deck: <https://en.tokyotower.co.jp/plan/open_air_stair/>.
Both routes end at 150 m; they start in different places.
Ascend is a racing app, so the catalogue ships the sanctioned race distance, 500.
The catalogue's previous 1,832 came from the 333 m antenna height and corresponds to no route at all.

**El Penon de Guatape. 649 / 659 / 708 / 740.**
The staircase built into the rock face in 1954 is cited at 649 steps.
The full ascent to the top of the summit viewing tower is cited at 740, and one commonly repeated breakdown is 659 on the rock plus 81 inside the tower.
The catalogue ships 740 as the complete climb, at low confidence.
At any of those values it is a sprint, against the catalogue's previous 1,210.

**Sacre-Coeur. 280 / 292 / 300.**
Published figures for the dome climb range from 280 to 300 depending on where the count starts.
The catalogue ships 300, the most commonly published figure, which sits exactly on the `bronze` threshold.
If a stricter source settles this lower, the tier moves to `common`.

**Leaning Tower of Pisa. 251 / 273 / 294 / 296.**
The tower has two staircases of slightly different length, and sources disagree on whether the count stops at the bell chamber or the top.
Commonly cited: 251 to the bell chamber, 294 on the north stair, 296 on the south stair.
The catalogue ships 296 and the tower lands in `common` rather than `bronze` at any of those values below 300.

## Climbs deliberately left null

These carry no `realStairCount`, so `referenceStepCount` still falls back to the height-derived `totalSteps`.
That fallback is a known gap, not a verified distance.

**Plausible stair route, no published count found (7).**
The Shard, Sagrada Familia, Petronas Towers, N Seoul Tower, Marina Bay Sands, Osaka Castle, Voortrekker Monument.

**No public or competitive stair route found (8).**
Hallgrimskirkja, Palacio Salvo, Cairo Tower, Moscow State University Main Building, Transamerica Pyramid, Gran Torre Santiago, Chrysler Building, Tokyo Skytree.

**Not a stair ascent (28).**
The 21 mountains and volcanoes, plus Machu Picchu, Acropolis of Athens, Alhambra, Neuschwanstein Castle, Abuna Yemata Guh, Sugarloaf Mountain and Table Mountain.
No stair count exists to verify, because there is no staircase.

Whether any of these should stay in a racing catalogue is a curation question, tracked separately in [issue #440](https://github.com/tpavay/AscendApp/issues/440).
This file only records numbers.
