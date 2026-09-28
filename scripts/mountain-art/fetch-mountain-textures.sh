#!/usr/bin/env bash
# Fetches the CC0 Poly Haven materials Ascend Mountain draws its stairs and kerbs with, and
# prepares them for the phone: 1K colour with the ambient occlusion multiplied in, a 1K normal
# map, and a roughness map. Needs curl, python3 and ffmpeg.
#
#   scripts/mountain-art/fetch-mountain-textures.sh
#
# Sources and licences are listed in scripts/mountain-art/README.md.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="AscendApp/Features/AscendMountain/Resources"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mountain-art.XXXXXX")"
trap 'rm -r "$WORK"' EXIT

url() { # asset map -> 1K jpg URL from the Poly Haven API
  curl -fsSL "https://api.polyhaven.com/files/$1" | python3 -c "import json,sys;print(json.load(sys.stdin)['$2']['1k']['jpg']['url'])"
}
get() { curl -fsSL -o "$WORK/$2" "$(url "$1" "$3")"; }

# Treads and risers: granite slabs.
get granite_tile stone-diff.jpg Diffuse
get granite_tile stone-nor.jpg nor_gl
get granite_tile stone-arm.jpg arm
ffmpeg -loglevel error -y -i "$WORK/stone-arm.jpg" -vf "format=gbrp,extractplanes=r" "$WORK/stone-ao.png"
ffmpeg -loglevel error -y -i "$WORK/stone-diff.jpg" -i "$WORK/stone-ao.png" -filter_complex "[0]format=gbrp[d];[1]format=gray,format=gbrp[ao];[d][ao]blend=all_mode=multiply" -q:v 3 "$OUT/ascend-mountain-stone.jpg"
ffmpeg -loglevel error -y -i "$WORK/stone-nor.jpg" -q:v 2 "$OUT/ascend-mountain-stone-normal.jpg"
ffmpeg -loglevel error -y -i "$WORK/stone-arm.jpg" -vf "format=gbrp,extractplanes=g,scale=512:512" -q:v 3 "$OUT/ascend-mountain-stone-roughness.jpg"

# Kerbs: laid slate.
get castle_wall_slates kerb-diff.jpg Diffuse
get castle_wall_slates kerb-nor.jpg nor_gl
get castle_wall_slates kerb-rough.jpg Rough
ffmpeg -loglevel error -y -i "$WORK/kerb-diff.jpg" -q:v 3 "$OUT/ascend-mountain-kerb.jpg"
ffmpeg -loglevel error -y -i "$WORK/kerb-nor.jpg" -q:v 2 "$OUT/ascend-mountain-kerb-normal.jpg"
ffmpeg -loglevel error -y -i "$WORK/kerb-rough.jpg" -vf "format=gray,scale=512:512" -q:v 3 "$OUT/ascend-mountain-kerb-roughness.jpg"

ls -la "$OUT"/ascend-mountain-stone* "$OUT"/ascend-mountain-kerb*
