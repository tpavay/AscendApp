# App Store screenshot review

Review date: July 29, 2026.

The final rendered contact sheet was reviewed as one horizontal storefront sequence.
The seven screens form a coherent progression from stair-stepper effort, to Everest-scale ambition, to landmark discovery, live racing, ranking, First Ascent prestige, and durable records.

## Composition

- All seven screenshots use the same phone geometry, inset height, inset width, and vertical placement.
- The phone screen is 1012 x 2192, the 19.5:9 proportion of the device the captures came from, so every capture lands at its true shape.
- The whole device sits inside the canvas: 1048 x 2228 at (136, 585) ends 55px above the bottom edge, so nothing is sliced by the canvas.
- Every app body is scaled by width only. No screen loses a column of app UI, so no header, card corner, icon, wreath, row background, or control is cut off sideways.
- Screens 03 and 05 fill the phone body from their captures with no crop at all; screens 02, 06 and 07 give up 9 rows at the very bottom of the capture; screen 04 gives up its blank leading padding and its home indicator.
- Where app content meets the bottom of the phone screen - the Easiest carousel on 03, the fourth leaderboard row on 05 - it is the capture's own scroll edge, framed by the device bezel, exactly as the running app renders it.
- Screens 01 and 02 have equal visual weight and identical device framing.
- The two approved photographs are full-bleed and byte-identical to the preserved source files; the canvas is within half a percent of their aspect, so the fit is effectively uncropped.
- Both photographic screens carry genuine Ascend UI.
- No source is letterboxed.
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
- Screen 01's phone body is the widest chrome-free window of the real share capture - the card and the app background around it - centred on the card, with the window's own edge tone continuing to the top and bottom of the screen. There is no invented gradient and no invented app surface.
- Screen 01 contains no share-sheet title, dismissal control, explanatory copy, or share-destination buttons.
- Screen 02 pairs its Everest headline with an app surface that visibly includes the Everest card and names Mt. Everest in its supporting copy. All six landmark cards are whole.
- Screen 03 shows the live globe and real landmark catalog, with the Popular header, its See all action, and the Machu Picchu card complete.
- Screen 04 shows an in-progress replay leaderboard with the current climber highlighted and the real, enabled End attempt control. Nothing below the list is painted in.
- Screen 05 shows the per-climb completion leaderboard and does not use the known-bad split-summary capture.
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
- The renderer refuses to run if the phone frame would bleed past the canvas, and refuses to build a body from a capture that is too short to fill the screen without cropping sideways.
