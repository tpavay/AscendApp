# Climb coordinate and name sources

This file is the source record for catalogue facts that are not step counts: a climb's pinned coordinate and its optional `commonName`.
Verified race distances live in [`docs/climb-real-stair-counts.md`](climb-real-stair-counts.md); that file records numbers only.

A pin is a claim about where a climber is racing, so it needs the same citable-source discipline as a distance.
Prefer a mapped building footprint carrying the landmark's own identifiers over a bare point coordinate, because a point can sit anywhere and a footprint cannot.
Where sources disagree materially, record the disagreement here rather than silently picking one.

## Coordinate verifications

| Climb | Shipped coordinate | Sources | Result |
| --- | --- | --- | --- |
| Guangzhou CTF Finance Centre (`ctf-finance-centre-guangzhou`) | 23.12052, 113.32076 | OpenStreetMap building `广州周大福金融中心, 6, 珠江东路` at 23.1205531, 113.3208773 (<https://nominatim.openstreetmap.org/search?q=Guangzhou+CTF+Finance+Centre&format=json>); Wikidata [Q168575](https://www.wikidata.org/wiki/Q168575) at 23°7′13″N 113°19′14″E | Unchanged. The shipped pin sits 13 m from the mapped building and 34 m from the Wikidata point, both inside the tower's own footprint. |
| R&F Yingkai Square (`yingkai-square`) | 23.1211804, 113.3163659 | OpenStreetMap building `富力盈凯广场` on 华夏路 (Huaxia Road), tagged `wikidata=Q17637389`, `wikipedia=en:R&F Yingkai Square`, `height=296.5`, at 23.1211804, 113.3163659; Wikidata [Q17637389](https://www.wikidata.org/wiki/Q17637389) and [English Wikipedia](https://en.wikipedia.org/wiki/R%26F_Yingkai_Square) at 23°7′7.1364″N 113°19′10.5636″E | **Corrected.** The previously shipped 23.1197725, 113.3218333 reverse-geocodes to Xiancun Road, roughly 460 m east of the tower and on an unrelated building. |

### Conflict: R&F Yingkai Square

The Wikidata point (23.118649, 113.319601) and the OpenStreetMap footprint (23.1211804, 113.3163659) disagree by about 430 m.
The catalogue ships the footprint: it carries the building's own `wikidata`, `wikipedia` and `height=296.5` tags, and it sits on Huaxia Road, matching the tower's published address at 16 Huaxia Road.
The Wikidata point reverse-geocodes to the Xinzhongzhou tunnel parking area and lands on no building at all.

## Common names

`commonName` is the name a city still uses for a renamed landmark.
It never replaces `name`, which stays the official one, and it is populated only where the former name is the name people actually say.
The field is data-only: no surface renders it yet.

| Climb | `commonName` | Source |
| --- | --- | --- |
| 875 North Michigan Avenue (`875-north-michigan-avenue`) | John Hancock Center | John Hancock Insurance asked for its name and logos to be removed on 12 February 2018 and the tower took its street address as its name; Chicago still calls it the John Hancock Center. <https://en.wikipedia.org/wiki/875_North_Michigan_Avenue> |
