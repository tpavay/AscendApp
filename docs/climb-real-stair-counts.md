# Verified real stair counts

This file is the source record for every `realStairCount` in the climb catalogue.

Catalogue facts that are not step counts - a climb's pinned coordinate and its optional `commonName` - are recorded in [`docs/climb-coordinate-and-name-sources.md`](climb-coordinate-and-name-sources.md).

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
| Ping An Finance Centre | 3,201 | 116F, 541 m gain | Medium | Towerrunning World Tour race report, <https://www.towerrunning.com/2026/01/10/tea-faber-wai-ching-soh-pingan-champions/> |
| Guangzhou CTF Finance Centre | 3,160 | 109F | Medium | Towerrunning World Association race record, <https://www.towerrunning.com/races/r3103/> |
| Shanghai World Financial Center | 2,726 | 100F | Medium | Towerrunning World Association race record, <https://www.towerrunning.com/races/r2854/> |
| Sommerbergbahn Stair | 1,987 | 720 m outdoor stair, 300 m gain | Medium | Württemberg Athletics Association event announcement, <https://calw.wlv-sport.de/home/details/news/17-bad-wildbader-staeffeleslauf-entlang-der-bergbahntrasse-am-freitag-19-juni-2026-auf-deutschland-laengster-treppe> |
| Central Plaza | 1,688 | ground to 75F | Medium | Hong Chi Climbathon competition details, <https://www.hongchi.org.hk/en/climbathon/page/competition-details> |
| 875 North Michigan Avenue | 1,632 | 94F | Medium | Towerrunning World Association race record, <https://www.towerrunning.com/races/r3137/> |
| Torre Reforma | 1,487 | 56F | Low | 2024 Mexico City firefighter race announcement, <https://www.publimetro.com.mx/noticias/2024/09/21/esto-es-lo-que-tienes-que-saber-de-la-carrera-vertical-del-cuerpo-de-bomberos-de-la-cdmx/>; see Conflicts |
| DC Tower 1 | 1,412 | 58F, 210 m gain | Medium | Towerrunning World Association race record, <https://www.towerrunning.com/races/r3181/> |
| R&F Yingkai Square | 1,390 | 52F, 220 m gain | Medium | Towerrunning World Association race record, <https://www.towerrunning.com/races/r3278/> |
| TK Elevator Test Tower | 1,390 | 232 m gain | Medium | Towerrunning World Association race record, <https://www.towerrunning.com/races/r2703/> |
| Varso Tower | 1,382 | 53F, 230 m gain | Medium | Towerrunning World Association race record, <https://www.towerrunning.com/races/r2704/> |
| Tianjin TV Tower | 1,340 | 253 m gain after a 350 m ground loop | Medium | Xinhua event report syndicated by Sohu, <https://www.sohu.com/a/844232355_267106> |
| Macau Tower | 1,298 | 61F, 233 m gain | Medium | Towerrunning World Association race record, <https://www.towerrunning.com/races/r2806/> |
| Frasers Tower | 1,256 | 39F | Medium | Towerrunning World Association race record, <https://www.towerrunning.com/races/r3037/> |
| Messeturm Frankfurt | 1,200 | 61F | Medium | Towerrunning World Association race record, <https://www.towerrunning.com/races/r3182/> |
| Sky Tower Wroclaw | 1,142 | level -5 to 49F | Medium | Towerrunning World Association race record, <https://www.towerrunning.com/races/r2714/> |
| Gran Hotel Bali | 936 | 52F, 180 m gain | Low | Towerrunning World Association race record, <https://www.towerrunning.com/races/r3068/>; see Conflicts |
| Tallinn TV Tower | 870 | tower stair | Medium | Towerrunning World Association race record, <https://www.towerrunning.com/races/r2433/> |
| Rondo 1 | 836 | 38F, 142 m gain | Medium | Towerrunning World Tour event announcement, <https://www.towerrunning.com/2026/02/02/announcement-towerrunning-120-bieg-na-szczyt-rondo-1-warsaw-march-28-2026/> |
| Post Tower | 828 | 41F | Medium | Towerrunning World Association race record, <https://www.towerrunning.com/races/r3207/> |
| KölnTurm | 732 | ground to 40F, 135 m gain | Low | KölnTurm Treppenlauf organiser, <https://www.koelner-treppenlauf.de/infos_en/>; see Conflicts |
| Sky Tower Bucharest | 720 | 36F, 126 m gain | Medium | Towerrunning World Association race record, <https://www.towerrunning.com/races/r2937/> |
| Torre Glòries | 686 | 34F | Medium | Towerrunning World Tour event announcement, <https://www.towerrunning.com/2025/11/26/announcement-towerrunning-120-cupra-barcelona-tower-running-challenge-barcelona-fanuary-17-2026/> |
| AZ Tower | 631 | 29F | Low | Towerrunning World Association race record, <https://www.towerrunning.com/races/r2867/>; see Conflicts |
| Hyatt Regency Barcelona Tower | 569 | outdoor stair, 29F, 105 m gain | Medium | Metropolitan Sky Run organiser, <https://metropolitanskyrun.com/> |
| Messeturm Basel | 542 | 31F | Medium | Towerrunning World Association race record, <https://www.towerrunning.com/races/r3024/> |
| Pyramidenkogel | 441 | finish at 71 m platform | Medium | Towerrunning World Tour event announcement, <https://www.towerrunning.com/2025/07/27/announcement-towerrunning-120-pyramidenkogel-turmlauf-september-14/> |
| UFO Tower Bratislava | 430 | 23F | Medium | Towerrunning World Association race record, <https://www.towerrunning.com/races/r3235/> |

## Published stair routes

Not a sanctioned race, but a documented staircase with a published count.

| Climb | `realStairCount` | Route | Confidence | Source |
|---|---:|---|---|---|
| Burj Khalifa | 2,909 | 160F fire stairwell | High | Figure used by every sanctioned Burj Khalifa climb and by Emaar; <https://www.towerrunning.com/2020/05/15/charity-challenge-burj-khalifa-virtual-climb/> |
| Petronas Towers | 2,170 | ground to the top of Tower 2, 88F | Low | Captain-supplied, 2026-09-02; corroborated by the Mercedes AMG PETRONAS training ascent, <https://www.motorsport.com/f1/video/nico-rosberg-training-at-the-petronas-towers-malaysia/19471/> ("2,170 stairs to the top of the PETRONAS towers"). Not a venue-published figure; see the note below |
| Eiffel Tower | 1,665 | ground to the summit, 279 m | High | <https://www.toureiffel.paris/en/news/events/eiffel-tower-vertical> |
| Eureka Tower | 1,642 | 88F to Melbourne Skydeck | High | Eureka Climb, run annually since 2008 |
| Monserrate | 1,605 | IDRD sendero peatonal | High | <https://www.idrd.gov.co/parques-y-escenarios/sendero-de-monserrate>, plus <https://bogota.gov.co> |
| Sydney Tower | 1,504 | ground to the Sydney Tower Eye platform | High | Sydney Tower Eye Stair Challenge, <https://www.sydneytowereye.com.au/plan-your-day/information/news/sydney-tower-eye-stair-challenge/> |
| Berlin TV Tower | 986 | ground to the 203 m deck | Medium | <https://tv-turm.de/>; service and emergency stair, not normally public |
| El Penon de Guatape | 740 | masonry staircase plus the summit tower | Low | Guatape tourism and the count painted at the summit; see Conflicts |
| St. Peter's Basilica | 551 | ground to the top of the dome | High | <https://www.basilicasanpietro.va/en/help/the-dome> |
| Statue of Liberty | 377 | 215 to the pedestal top + 162 to the crown | High | <https://www.nps.gov/stli/planyourvisit/visiting-the-pedestal.htm> |
| Elizabeth Tower | 334 | ground to the belfry | High | <https://www.parliament.uk/visiting/visiting-and-tours/big-ben-tour/> |
| Sacre-Coeur | 300 | ground to the dome | Medium | Basilica dome visit; see Conflicts |
| Leaning Tower of Pisa | 296 | ground to the belfry, south stair | Low | Opera della Primaziale Pisana visitor material; see Conflicts |
| Charminar | 149 | ground to the upper floor | High | Telangana state tourism, <https://hyderabad.telangana.gov.in/tourist-place/charminar/> |

Petronas Towers is the one row here whose figure did not come from the venue, an organiser, or a race record.
The 2,170 is the captain's number, supplied and recorded as his on 2026-09-02.
It is corroborated by a media report of a documented training ascent of the tower's own staircase: motorsport.com's coverage of the Mercedes AMG PETRONAS session, worded "2,170 stairs to the top of the PETRONAS towers".
No primary source backs it.
PETRONAS publishes no stair count, and the towers hold no sanctioned tower run - the Kuala Lumpur race with a published 2,058-step course is at KL Tower, a different landmark, and must never be attached to this entry.
Nothing meeting the primary-source bar this file sets - the venue owner, the event organiser, the custodian body, or the Towerrunning World Association race record - exists for this staircase.

The row therefore ships at Low, and the reason is not the one the Low legend names.
Nothing contradicts 2,170; no conflicting figure has been found, and none is recorded in the Conflicts section for this entry.
Low is the honest label because the number clears no source bar in this file at all: Medium requires a single authoritative source, and a media report of an ascent is not the venue-, organiser-, or custodian-published figure the rules ask for.
The rules are left exactly as written, and this row is recorded against them rather than accommodated by them.
It is the number to revisit first if PETRONAS or an organiser ever publishes one.

### Verified counts for climbs no longer in the catalogue

The racing curation ([#440](https://github.com/tpavay/AscendApp/issues/440)) removed these two entries because their staircases are not open to anyone, so no climber can verify a time against them.
The research is kept here, not deleted, so a future reversal does not have to redo it.

| Climb | `realStairCount` | Route | Confidence | Source |
|---|---:|---|---|---|
| Gateway Arch | 1,076 | emergency stairway, one leg | High | <https://www.nps.gov/jeff/planyourvisit/gateway-arch-fact-sheet.htm>; **public access forbidden** |
| Washington Monument | 897 | ground to the observation level | High | National Park Service; **closed to the public since 1971** |

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
| Ping An Finance Centre | 541 | 1,774.9 | Towerrunning World Tour race report |
| Sommerbergbahn Stair | 300 | 984.3 | Württemberg Athletics Association event announcement |
| DC Tower 1 | 210 | 689.0 | TWA race record |
| R&F Yingkai Square | 220 | 721.8 | TWA race record |
| TK Elevator Test Tower | 232 | 761.2 | TWA race record |
| Varso Tower | 230 | 754.6 | TWA race record |
| Tianjin TV Tower | 253 | 830.1 | Xinhua event report |
| Macau Tower | 233 | 764.4 | TWA race record |
| Gran Hotel Bali | 180 | 590.6 | TWA race record |
| Rondo 1 | 142 | 465.9 | Towerrunning World Tour event announcement |
| Sky Tower Bucharest | 126 | 413.4 | TWA race record |
| KölnTurm | 135 | 442.9 | Race organiser |
| Hyatt Regency Barcelona Tower | 105 | 344.5 | Race organiser |
| Pyramidenkogel | 71 | 232.9 | Towerrunning World Tour event announcement |

## Floor counts

`calculatedFloors` renders as FLOORS directly beside STEPS on climb detail, so it has to answer for the same route the step count answers for.
It was originally `round(totalHeightMeters / 3.6)`, the same architectural-height derivation as `totalSteps`, which put a corrected step count next to an uncorrected floor count: Monserrate read 1,605 steps over 876 floors, Tokyo Tower 500 over 93.

Every climb carrying a `realStairCount` now takes its floor count from one of two places, in this order:

1. **The route's published storey count**, where a source in the tables above states one.
2. **`round(referenceStepCount / 19.8)`** otherwise.

19.8 is the ratio the height derivation already implied (`5.5` steps per metre over `3.6` metres per floor), so the 28 climbs the catalogue currently ships with a null `realStairCount` - the ones enumerated under [Climbs deliberately left null](#climbs-deliberately-left-null) - keep the floor counts they had, because their reference count is still `totalSteps` and the two rules agree there.

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
| Petronas Towers | 88 | 88F, the topmost occupied storey and the top of the ascent the step count covers; the 452 m architectural height above it is spire, <https://en.wikipedia.org/wiki/Petronas_Towers> |
| Empire State Building | 86 | 86F observation deck, ESB Run-Up |
| Q1 Tower | 77 | 77F, SkyPoint Sea to Sky |
| Sky Tower (Auckland) | 51 | 51F, Step Up Sky Tower Challenge |
| Torre Latinoamericana | 42 | 42F, Carrera Vertical Torre Latino |
| Farol Santander | 26 | 26F of the Edificio Altino Arantes |
| Ping An Finance Centre | 116 | 116F, Towerrunning World Tour race report |
| Guangzhou CTF Finance Centre | 109 | 109F, TWA race record |
| Shanghai World Financial Center | 100 | 100F, TWA race record |
| Central Plaza | 75 | ground to 75F, Hong Chi Climbathon |
| 875 North Michigan Avenue | 94 | 94F, TWA race record |
| Torre Reforma | 56 | 56F, 2024 Mexico City firefighter race; see Conflicts |
| DC Tower 1 | 58 | 58F, TWA race record |
| R&F Yingkai Square | 52 | 52F, TWA race record |
| Varso Tower | 53 | 53F, TWA race record |
| Macau Tower | 61 | 61F, TWA race record |
| Frasers Tower | 39 | 39F, TWA race record |
| Messeturm Frankfurt | 61 | 61F, TWA race record |
| Sky Tower Wroclaw | 49 | level -5 to 49F, TWA race record |
| Gran Hotel Bali | 52 | 52F, TWA race record; see Conflicts |
| Rondo 1 | 38 | 38F, Towerrunning World Tour event announcement |
| Post Tower | 41 | 41F, TWA race record |
| Sky Tower Bucharest | 36 | 36F, TWA race record |
| KölnTurm | 40 | ground to 40F, race organiser; see Conflicts |
| Torre Glòries | 34 | 34F, Towerrunning World Tour event announcement |
| AZ Tower | 29 | 29F, current TWA race record; see Conflicts |
| Hyatt Regency Barcelona Tower | 29 | 29F, race organiser |
| Messeturm Basel | 31 | 31F, TWA race record |
| UFO Tower Bratislava | 23 | 23F, TWA race record |

### Derived floor counts

These carry no published storey count for the route, so `calculatedFloors` is `round(referenceStepCount / 19.8)` and is derived, not sourced.

Sommerbergbahn Stair 100, TK Elevator Test Tower 70, Tianjin TV Tower 68, Tallinn TV Tower 44, Pyramidenkogel 22, CN Tower 90, Eiffel Tower 84, Monserrate 81, Sydney Tower 76, Berlin TV Tower 50, Space Needle 42, Reunion Tower 42, El Penon de Guatape 37, St. Peter's Basilica 28, Tokyo Tower 25, Statue of Liberty 19, Elizabeth Tower 17, Leaning Tower of Pisa 15, Sacre-Coeur 15, Charminar 8.

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

**Torre Reforma. 1,421 over 53 floors / 1,487 over 56 floors.**
The 2022 firefighter race published 1,421 stairs to floor 53.
The latest sourced route, the 2024 race, extended the finish to floor 56 and published 1,487 stairs.
The catalogue ships the current 2024 route, 1,487, rather than averaging distinct editions.

**KölnTurm. 705 over 39 floors / 732 over 40 floors.**
The Towerrunning World Association 2026 archive lists 705 stairs and 39 floors.
The current race organiser's course page lists 732 stairs from ground level to the 40th floor.
The catalogue ships the organiser's current full course, 732.

**Gran Hotel Bali. 924 / 936.**
The 2025 event announcement listed 924 stairs over 52 floors.
The current Towerrunning World Association race record lists 936 stairs over the same 52-floor course.
The catalogue ships the current race record, 936.

**AZ Tower. 700 over 30 floors / 631 over 29 floors.**
An older race report listed 700 stairs and 30 floors.
The current Towerrunning World Association race record lists 631 stairs and 29 floors.
The catalogue ships the current route, 631.

## Climbs deliberately left null

These carry no `realStairCount`, so `referenceStepCount` still falls back to the height-derived `totalSteps`.
That fallback is a known gap, not a verified distance.

**Plausible stair route, no published count found (6).**
The Shard, Sagrada Familia, N Seoul Tower, Marina Bay Sands, Osaka Castle, Voortrekker Monument.
These ship as `comingSoon`, so nobody races an unverified distance.

**Announced race with no published course distance yet (1).**
CapitaMall ONE is scheduled for December 2026, but the venue and Towerrunning World Tour material publish no defensible stair count yet.
It is held at `comingSoon` while the other 28 Towerrunning World Tour venues added beside it race, because a raceable climb ranks against a published route and the only number left here is the height derivation.

**Not a stair ascent (21).**
The 21 mountains and volcanoes, which ship as `hidden` for a future endurance ladder.
No stair count exists to verify, because there is no staircase.

The curation question these entries used to raise is settled.
[Issue #440](https://github.com/tpavay/AscendApp/issues/440) deleted seventeen entries from the catalogue: the eight with no public or competitive stair route (Hallgrimskirkja, Palacio Salvo, Cairo Tower, Moscow State University Main Building, Transamerica Pyramid, Gran Torre Santiago, Chrysler Building, Tokyo Skytree), the seven that are not staircases (Machu Picchu, Acropolis of Athens, Alhambra, Neuschwanstein Castle, Abuna Yemata Guh, Sugarloaf Mountain, Table Mountain), and the two whose verified staircases are closed to the public, recorded above under Published stair routes.
This file only records numbers.
