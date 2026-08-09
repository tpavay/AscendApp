# Climb Candidate Research

This is a research backlog for future climb catalog expansion. Do not add these
directly to `climbs.json` until each row is verified and product-approved.

## Target

Ascend should move toward a balanced worldwide pool of real stair-climb venues,
not height-only landmark equivalents.

The clean year-sized target is `366` climbs: six inhabited continents with `61`
climbs each. That gives a daily climb for a year plus one spare.

| Continent     | Current catalog count | Target for 252 | Add for 252 | Target for 366 | Add for 366 |
| ------------- | --------------------: | -------------: | ----------: | -------------: | ----------: |
| Africa        |                     7 |             42 |          35 |             61 |          54 |
| Asia          |                    26 |             42 |          16 |             61 |          35 |
| Europe        |                    34 |             42 |           8 |             61 |          27 |
| North America |                    18 |             42 |          24 |             61 |          43 |
| Oceania       |                     8 |             42 |          34 |             61 |          53 |
| South America |                    11 |             42 |          31 |             61 |          50 |

Counts are catalog rows in `web/public/climbs/catalog-v1.json`, `comingSoon` included;
recount from that file rather than trusting this table after a catalog change.

If V1 becomes "verified real stair-climb venues only," audit the current catalog too.
Many current climbs are climb-equivalent targets, not known public stair venues.

## Eligibility Rules

A candidate should pass all of these before becoming catalog data:

- Real man-made venue: skyscraper, tower, stadium, public stair structure, or
  other built landmark.
- Actual climbable stair route: official stair race, charity stair climb,
  public stair access, guided stair challenge, or a documented recurring event.
- Source confirms the route, not just the building height.
- A source-confirmed `realStairCount`, recorded per the rules in
  `docs/climb-real-stair-counts.md`. A height-derived step count is never a race
  distance, so a candidate with no citable count is left null rather than
  estimated from floors or height.
- No proposed buildings, elevator-only landmarks, roof-access-only attractions,
  or height-only iconic venues.

Reject examples until proven otherwise: Lotus Tower, Burj Al Arab, Great Pyramid
of Giza, Taj Mahal, and similar landmarks where we only have height or visual
interest, not evidence people climb the stairs.

## Verification Status

- `confirmed`: source shows the venue is climbed and gives a citable stair count
  for the route.
- `needs_metrics`: source shows a climb exists, but the stair count is missing or
  inconsistent.
- `needs_access`: venue is plausible but no reliable public/event climb source
  is known yet.
- `reject`: not a real public/event climb for Ascend's purposes.

## Source Strategy

Start with governing bodies and official event pages:

- Towerrunning World Association race archive and tour pages.
- International Skyrunning Federation stairclimbing qualified race list.
- National towerrunning associations.
- Official building-run, charity stair climb, and venue event pages.
- Local event organizers only when they provide concrete route details.

## Seed Candidates

These are not final catalog rows. They are the first high-confidence places to
research into normalized candidate JSON/CSV.

### North America

| Venue                  | City        | Country | Known climb data                                                 | Status        | Source                                                                                                           |
| ---------------------- | ----------- | ------- | ---------------------------------------------------------------- | ------------- | ---------------------------------------------------------------------------------------------------------------- |
| One World Trade Center | New York    | USA     | 2,226 stairs, 104 floors                                         | confirmed     | https://www.towerrunning.com/races/r2460/                                                                        |
| 875 N Michigan Avenue  | Chicago     | USA     | in current catalog; count verified, see `docs/climb-real-stair-counts.md` | confirmed     | https://www.towerrunning.com/races/r2115/                                                                        |
| Empire State Building  | New York    | USA     | 1,576 stairs, 86 flights                                         | confirmed     | https://www.esbnyc.com/2025-esb-run-up                                                                           |
| Republic Plaza         | Denver      | USA     | 1,098 stairs, 56 flights                                         | confirmed     | https://www.milehighstairclimb.com/                                                                              |
| U.S. Bank Tower        | Los Angeles | USA     | 1,664 steps, 75 stories                                          | confirmed     | https://raceroster.com/events/2025/110229/ymca-stair-climb-and-urban-hike                                        |
| Space Needle           | Seattle     | USA     | in current catalog; count verified, see `docs/climb-real-stair-counts.md` | confirmed | https://www.spaceneedle.com/base2space                                                                           |
| Tower of the Americas  | San Antonio | USA     | annual stair climb; 65 flights climbed twice for memorial format | needs_metrics | https://www.ksat.com/news/local/2023/09/11/annual-stair-climb-at-tower-of-the-americas-stirs-up-memories-of-911/ |

### South America

| Venue               | City       | Country  | Known climb data                                                    | Status       | Source                                                                                       |
| ------------------- | ---------- | -------- | ------------------------------------------------------------------- | ------------ | -------------------------------------------------------------------------------------------- |
| Torre Colpatria     | Bogota     | Colombia | 980 stairs, 50 floors                                               | confirmed    | https://www.towerrunning.com/races/r1400/                                                    |
| We Apartments       | Chapeco    | Brazil   | 508 race steps, 100 m race height                                   | confirmed    | https://www.skyrunning.com/qualified-race-label/                                             |
| Gran Torre Santiago | Santiago   | Chile    | building exists in current catalog; stair climb access not verified | needs_access | https://group.schindler.com/en/media/stories/costanera-center-delivering-on-every-level.html |
| Farol Santander     | Sao Paulo  | Brazil   | in current catalog; route and count verified, see `docs/climb-real-stair-counts.md` | confirmed | https://www.towerrunning.com/races/r3075/                                                    |
| Palacio Salvo       | Montevideo | Uruguay  | in current catalog; stair climb route not verified                  | needs_access | Current catalog                                                                              |

South America needs deeper research. The first pass should focus on Colombia,
Brazil, Chile, Argentina, Uruguay, and Peru tower-run organizers and charity
climbs.

### Europe

| Venue                  | City       | Country        | Known climb data                       | Status    | Source                                                                                                                                |
| ---------------------- | ---------- | -------------- | -------------------------------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| TK Elevator Test Tower | Rottweil   | Germany        | in current catalog; count verified, see `docs/climb-real-stair-counts.md` | confirmed | https://towerrun.tkelevator.com/infos_en/                                                                                             |
| MesseTurm              | Frankfurt  | Germany        | in current catalog; count verified, see `docs/climb-real-stair-counts.md` | confirmed | https://www.towerrunning.com/races/                                                                                                   |
| Post Tower             | Bonn       | Germany        | in current catalog; count verified, see `docs/climb-real-stair-counts.md` | confirmed | https://www.towerrunning.com/races/r2489/                                                                                             |
| KoelnTurm              | Cologne    | Germany        | in current catalog; sources disagree, see `docs/climb-real-stair-counts.md` | confirmed | https://www.towerrunning.com/races/r1470/                                                                                             |
| UFO Tower              | Bratislava | Slovakia       | in current catalog; count verified, see `docs/climb-real-stair-counts.md` | confirmed | https://www.towerrunning.com/races/                                                                                                   |
| 22 Bishopsgate         | London     | United Kingdom | over 1,500 stairs, 58 floors           | confirmed | https://fundraise.rnli.org/event/tower-run/home                                                                                       |
| Broadgate Tower        | London     | United Kingdom | 877 steps, 35 stories                  | confirmed | https://www.theguardian.com/lifeandstyle/the-running-blog/2017/dec/06/a-step-up-what-is-it-like-tower-running-up-a-35-storey-building |

### Asia

| Venue                          | City         | Country              | Known climb data                                                    | Status        | Source                                                     |
| ------------------------------ | ------------ | -------------------- | ------------------------------------------------------------------- | ------------- | ---------------------------------------------------------- |
| Abeno Harukas                  | Osaka        | Japan                | 1,610 stairs                                                        | confirmed     | https://verticalworldcircuit.com/                          |
| Jumeirah Emirates Towers       | Dubai        | United Arab Emirates | 1,334 steps, 52 floors                                              | confirmed     | https://verticalworldcircuit.com/                          |
| Macau Tower                    | Macau        | China                | in current catalog; count verified, see `docs/climb-real-stair-counts.md` | confirmed     | https://www.oxfam.org.hk/en/join-our-events/oxfam-towerrun |
| Canton Tower                   | Guangzhou    | China                | 2,738 stairs, 112 floors                                            | confirmed     | https://www.towerrunning.com/races/r1739/                  |
| Shimao Global Financial Center | Changsha     | China                | 2,238 stairs, 78 floors                                             | confirmed     | https://www.towerrunning.com/races/                        |
| Taipei 101                     | Taipei       | Taiwan               | in current catalog; count verified, see `docs/climb-real-stair-counts.md` | confirmed | https://www.taipei101-runup.com.tw/2024/en/en_introduction.aspx |
| KL Tower                       | Kuala Lumpur | Malaysia             | race confirmed; stair count needs source confirmation               | needs_metrics | https://www.towerrunning.com/towerrunning-tour-2026/       |

### Africa

| Venue                                    | City         | Country      | Known climb data                        | Status        | Source                                                                                             |
| ---------------------------------------- | ------------ | ------------ | --------------------------------------- | ------------- | -------------------------------------------------------------------------------------------------- |
| Ponte City                               | Johannesburg | South Africa | 948 stairs, 54 stories                  | confirmed     | https://wordpress.dlalanje.org/ponte-challenge/                                                    |
| Kenyatta International Convention Centre | Nairobi      | Kenya        | 33-storey recurring staircase challenge | needs_metrics | https://www.kenyans.co.ke/news/89282-kenyans-start-challenge-climb-33-storeys-kicc-stairs-how-join |

Africa is the limiting continent for a 366-climb target. To keep the continent
balanced, the research scope likely needs to include public stadium stair
events, civic towers, guided stair challenges, hotels, and office towers with
charity climbs, not just internationally ranked towerrunning races.

### Oceania

| Venue                    | City       | Country   | Known climb data              | Status    | Source                                                                                    |
| ------------------------ | ---------- | --------- | ----------------------------- | --------- | ----------------------------------------------------------------------------------------- |
| Australia 108            | Melbourne  | Australia | 1,700 stairs, 96 floors       | confirmed | https://www.towerrunning.com/races/r2628/                                                 |
| Eureka Tower             | Melbourne  | Australia | 1,642 stairs, 88 floors       | confirmed | https://www.stairclimbing.com.au/blog/2018/10/19/eureka-tower-melbourne                   |
| Q1                       | Gold Coast | Australia | 1,331 steps, 77 floors        | confirmed | https://myracehub.com.au/race/1242/skypoint-sea-to-sky-q1-stair-challenge                 |
| Tower One                | Sydney     | Australia | 1,000 stairs, 40 floors       | confirmed | https://www.towerrunning.com/races/r2455/                                                 |
| ONE ONE ONE Eagle Street | Brisbane   | Australia | 1,040 stairs, about 43 floors | confirmed | https://myracehub.com.au/race/1577/river-to-rooftop-stair-climb-challenge                 |
| West Side Place Tower 2  | Melbourne  | Australia | 1,152 stairs, 64 floors       | confirmed | https://www.stairclimbing.com.au/blog/2025/5/17/towers-4-change-west-side-place-melbourne |

Oceania will also need stadiums and smaller venues unless the target is reduced
or Australia-heavy.

## Next Research Pass

1. Build `docs/climb-candidates.csv` or JSON with normalized fields.
2. Deduplicate against the current catalog.
3. Mark current catalog rows as `verified_real_climb`, `equivalent_only`, or
   `needs_access`.
4. Fill continent gaps in this order: Africa, Oceania, South America, North
   America, Europe, Asia.
5. Promote only `confirmed` candidates into `climbs.json`.
