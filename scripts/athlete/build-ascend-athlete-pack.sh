#!/bin/bash
# Builds the athlete pack the app draws every look from: one mesh per body and size, without
# hair, and one hair pack per body holding every hairstyle on that body's skeleton. Muscle is not
# baked here - the app softens the skin textures itself (`MountainSkinDefinition`).
#
#   scripts/athlete/build-ascend-athlete-pack.sh "<dir>/Universal Base Characters[Standard]" \
#     AscendApp/Features/AscendMountain/Resources
set -euo pipefail

pack="${1:?the Universal Base Characters [Standard] folder}"
out="${2:?the output folder}"
blender="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
script="$(cd "$(dirname "$0")" && pwd)/build-ascend-athlete.py"

build() {
  "$blender" -b --python "$script" -- --pack "$pack" --out "$out" "$@" 2>&1 | grep -E '^athlete:|Traceback|Error' || true
}

for body in male female; do
  for size in slim regular solid big; do
    build --body "$body" --size "$size" --no-hair \
      --name "ascend-athlete-$body-$size" --texture-prefix "ascend-athlete-$body" &
  done
  wait
  build --body "$body" --hair-pack --name "ascend-athlete-$body-hair" --texture-prefix "ascend-athlete-$body"
done
