# Bundled font licences

The share sheet ships four open-licence families on top of the Montserrat weights the app already used.
Each is distributed under the SIL Open Font License 1.1, whose full text is at https://openfontlicense.org.
The licence allows bundling and embedding in an app, and forbids selling a font on its own.

| File | Family | Used for |
|---|---|---|
| `Resources/Fonts/Montserrat/Montserrat-ExtraBold.ttf`, `Montserrat-Black.ttf` | Montserrat (Julieta Ulanovsky and contributors) | Share sheet Bold face |
| `Resources/Fonts/BarlowCondensed/BarlowCondensed-ExtraBold.ttf` | Barlow Condensed (Jeremy Tribby) | Share sheet Condensed face |
| `Resources/Fonts/JetBrainsMono/JetBrainsMono-ExtraBold.ttf` | JetBrains Mono (JetBrains) | Share sheet Mono face |
| `Resources/Fonts/InstrumentSerif/InstrumentSerif-Regular.ttf` | Instrument Serif (Rodrigo Fuenzalida, Jordan Egstad) | Share sheet Serif face |

Ascend has no in-app acknowledgements page.
If one is added, it lists these four families with the licence name and link above.

Every new font file is registered in `AscendApp/Info.plist` under `UIAppFonts`, and `PresetFont.postScriptName(weight:)` is the one place that names the faces.
