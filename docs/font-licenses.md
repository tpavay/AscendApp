# Bundled font licences

Every font Ascend ships is an open-licence family distributed under the SIL Open Font License 1.1.
The full licence text, with each family's copyright notice, is `docs/licenses/OFL-1.1.txt`; the licence is also at https://openfontlicense.org.
The licence allows bundling and embedding in an app, and forbids selling a font on its own.
None of the four families declares a Reserved Font Name, and Ascend loads every file unmodified.

## Credits

| Family | Copyright notice, as embedded in the font files | Designers | Used for |
|---|---|---|---|
| Montserrat | Copyright 2011 The Montserrat Project Authors (https://github.com/JulietaUla/Montserrat) | Julieta Ulanovsky and contributors | Every `montserrat*` face in the app, and the share sheet Bold face |
| Barlow Condensed | Copyright 2017 The Barlow Project Authors (https://github.com/jpt/barlow) | Jeremy Tribby | Share sheet Condensed face |
| JetBrains Mono | Copyright 2020 The JetBrains Mono Project Authors (https://github.com/JetBrains/JetBrainsMono) | Philipp Nurullin, Konstantin Bulenkov | Share sheet Mono face |
| Instrument Serif | Copyright 2022 The Instrument Serif Project Authors (https://github.com/Instrument/instrument-serif) | Rodrigo Fuenzalida, Jordan Egstad | Share sheet Serif face |

## Files

| File | Family |
|---|---|
| `Resources/Fonts/Montserrat/Montserrat-Regular.ttf`, `-Medium.ttf`, `-SemiBold.ttf`, `-Bold.ttf`, `-ExtraBold.ttf`, `-Black.ttf` | Montserrat |
| `Resources/Fonts/BarlowCondensed/BarlowCondensed-ExtraBold.ttf` | Barlow Condensed |
| `Resources/Fonts/JetBrainsMono/JetBrainsMono-ExtraBold.ttf` | JetBrains Mono |
| `Resources/Fonts/InstrumentSerif/InstrumentSerif-Regular.ttf` | Instrument Serif |

The copyright notices above are read from each file's own name table, so they are the notices the authors embedded rather than a paraphrase.
Check them again whenever a font file is replaced.

## In the app

Ascend has no in-app acknowledgements page.
If one is added, it lists these four families with their copyright notice and the licence name and link above.

## Adding a font

Every new font file is registered in `AscendApp/Info.plist` under `UIAppFonts`, and `PresetFont.postScriptName(weight:)` is the one place that names the faces.
A new family also gets a row in both tables above, its copyright line in `docs/licenses/OFL-1.1.txt`, and a licence check: a font under any other licence needs the captain's say before it is bundled.
