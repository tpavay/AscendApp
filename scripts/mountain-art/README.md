# Ascend Mountain art sources

Every third-party file Ascend Mountain ships, where it came from, and its licence.
Nothing here was paid for; everything is CC0 (public domain), so no attribution is required, but the record is kept anyway.

| Shipped file(s) | Source | Licence | Built by |
|---|---|---|---|
| `ascend-athlete.json`, `.bin`, `ascend-athlete-skin*.{jpg,png}`, `ascend-athlete-hair.png`, `ascend-athlete-eyes.jpg` | Quaternius, [Universal Base Characters](https://quaternius.itch.io/universal-base-characters) (Standard edition, male body, `Hair_SimpleParted`) | CC0 1.0 | `scripts/athlete/build-ascend-athlete.py` (Blender); the tank, shorts and trainers are modelled by the script |
| `ascend-mountain-stone*.jpg` | Poly Haven, [granite_tile](https://polyhaven.com/a/granite_tile) | CC0 1.0 | `fetch-mountain-textures.sh` |
| `ascend-mountain-kerb*.jpg` | Poly Haven, [castle_wall_slates](https://polyhaven.com/a/castle_wall_slates) | CC0 1.0 | `fetch-mountain-textures.sh` |
| `ascend-mountain-ground-grass*.jpg` | Poly Haven, [rocky_terrain_02](https://polyhaven.com/a/rocky_terrain_02) | CC0 1.0 | `fetch-mountain-textures.sh` (greyed; each area's colour tints it) |
| `ascend-mountain-ground-rock*.jpg` | Poly Haven, [rock_face](https://polyhaven.com/a/rock_face) | CC0 1.0 | `fetch-mountain-textures.sh` (greyed) |
| `ascend-mountain-ground-snow*.jpg` | Poly Haven, [snow_02](https://polyhaven.com/a/snow_02) | CC0 1.0 | `fetch-mountain-textures.sh` (greyed) |

## Rebuilding

- Textures: `scripts/mountain-art/fetch-mountain-textures.sh` (curl, python3, ffmpeg, ImageMagick).
- Athlete: download the Standard pack from itch.io with a price of $0 (the site only serves it to a browser), then run the command at the top of `scripts/athlete/build-ascend-athlete.py` with Blender 5.2 or later (`brew install --cask blender`).
