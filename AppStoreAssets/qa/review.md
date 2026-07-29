# App Store screenshot review

Review date: July 29, 2026.

The final rendered contact sheet was reviewed as one horizontal storefront sequence.
The seven screens form a coherent progression from stair-stepper effort, to Everest-scale ambition, to landmark discovery, live racing, ranking, First Ascent prestige, and durable records.

## Genuine pixels

- Every pixel inside every phone screen comes from a real Ascend capture. Nothing is padded, stretched, averaged, tiled, or filled with an invented surface, and no gradient stands in for app UI.
- The only composited layers are the two approved photographs, the headline type, the accent rule, and the device frame.
- The status band is the one exception by design: a single real capture's status bar is reused on all seven screens so the clock, signal, Wi-Fi and battery match.

## Composition

- All seven screens use the same device: 1048 x 2218 with an 18px bezel and a 1012 x 2182 screen, the 19.5:9 proportion of the device the captures came from, so every capture lands at its true shape.
- Every app body is scaled by width only. No screen loses a column of app UI, so no header, card corner, icon, wreath, row background, or control is cut off sideways.
- Screens 02 through 07 place the device at (136, 585), ending 65px above the bottom of the canvas with the whole frame visible.
- Screen 01 runs its device off the bottom of the canvas, so its visible screen is 1012 x 1418. This is what lets the lead screenshot be entirely real: the recap card is about half a screen tall, and the capture has no further chrome-free surface below it, so a fully framed device could only have been completed with invented pixels.
- The lead pair share the same device width, bezel, corner radius, status bar and headline block. Screen 01 gives more of its canvas to the photograph and less to the device; screen 02 the reverse. Their masses read as a matched pair rather than a repeat.
- The two approved photographs are full-bleed and byte-identical to the preserved source files; the canvas is within half a percent of their aspect, so the fit is effectively uncropped.
- Both photographic screens carry genuine Ascend UI.
- No source is letterboxed.

## Bottom boundaries

Each screen declares the last capture row that must be whole and the first row that must not appear at all, and the renderer refuses to build a body whose bottom edge falls outside that gap.

| Screen | Last whole element | Bottom edge | First excluded element |
|---|---|---|---|
| 01 | recap card, row 1339 | row 1346 | page dots, row 1351 |
| 02 | supporting copy, row 2107 | row 2601 | end of capture, row 2622 |
| 03 | Easiest section header, row 1546 | row 1565 | first Easiest card, row 1570 |
| 04 | End attempt control, row 1766 | row 1774 | home indicator, row 1816 |
| 05 | rule under the third leaderboard row, row 1550 | row 1565 | fourth row's avatar, row 1574 |
| 06 | Skip control, row 2380 | row 2601 | end of capture, row 2622 |
| 07 | chart card's rounded bottom, row 2621 | row 2622 | end of capture, row 2622 |

- No card, row, glyph, icon, or control is sliced at any edge on any screen.
- Screen 03's Machu Picchu card runs off the right of the phone screen because that carousel scrolls horizontally in the running app; that is the capture's own state, not a crop.
- Screen 07 shows the Best Effort chart card complete, including its rounded bottom corners.
- No action, primary or secondary, is partially visible at any edge.
- Every app body begins below the status bar at a complete UI boundary.

## Status bar

- Every screenshot shows 9:41.
- Every screenshot shows full cellular signal, full Wi-Fi, and full battery.
- Every screenshot shows the same correctly proportioned Dynamic Island pill.
- The status-bar master is extracted at 1206 x 155 and scaled to 1012 x 130, the same proportion, so the pill and glyphs are not distorted.
- The shared interior status-bar pixels are hash-identical across all seven outputs, which is the renderer's guard against a later layer overdrawing that band.

## Content coherence

- Screen 01 pairs stair-stepper effort photography with the genuine Live Climb recap card: 15th global rank, 2,096 steps, 98 SPM, 23:53, 110 floors, and Empire State Building.
- Screen 01 contains no share-sheet title, dismissal control, explanatory copy, page dots, or share-destination buttons.
- Screen 02 pairs its Everest headline with an app surface that visibly includes the Everest card and names Mt. Everest in its supporting copy. All six landmark cards are whole.
- Screen 03 shows the live globe and real landmark catalog, with the Popular header, its See all action, and all three Popular cards complete.
- Screen 04 shows an in-progress replay leaderboard with the current climber highlighted and the real, enabled End attempt control. Nothing below the list is painted in.
- Screen 05 shows the per-climb completion leaderboard, its top three finishers complete, and does not use the known-bad split-summary capture.
- Screen 06 shows the real First Ascent badge, First Ascent copy, a genuinely enabled notification action, and its complete Skip control.
- Screen 07 shows a real Best Effort record, its whole laurel wreath, and its progression chart with a complete axis.
- No disabled primary action appears anywhere in the set.
- No control was recolored or rebuilt to imply a state the app was not in.

## Cross-screen numbers

- Empire State Building is 2,096 steps on screens 01, 03, 04 and 05.
- Screen 01's "15th out of 20" and screen 05's "83 completed" measure different things and coexist in one dataset. The recap card's denominator is `completedCountAtCompletion`, frozen when that climb was published (`LiveReplayPublishStatus`), while the climb leaderboard shows the count today. Finishing 15th of the 20 who had completed the climb, with 63 finishing since, is one consistent history.
- Screen 04's live window ranks the same climber 15th among the replay field, which is the same standing the recap froze.
- Screen 05's top times check out against the step count: 12:18 at 170 avg SPM, 13:22 at 157, and 13:27 at 156 all resolve to 2,096 steps.
- Screen 01's 98 SPM is over moving time and 23:53 is elapsed time, which is why the two do not multiply to 2,096.
- Screen 07's 10,849 steps at +1,471 over the previous record matches its chart, which ends just above 10,000 on a Mar 2026 axis.

## Output validation

- The upload directory contains exactly seven PNG files.
- Every file is exactly 1320 x 2868.
- Every file is sRGB.
- No file has an alpha channel.
- The renderer refuses to run if a device would fall outside the band between the headline rule and the bottom of the canvas, if a capture is too short to fill the screen without cropping sideways, or if a body's bottom edge would slice a declared element.
