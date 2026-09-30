#!/bin/bash
# Builds the athlete pack the app draws every look from, per body: one mesh per size without
# hair, one hair pack holding every hairstyle on that body's skeleton, and the body's textures -
# the skin once per muscle level, brightened to the lightest tone so the app tints it to any
# other (`MountainSkinTone`).
#
#   scripts/athlete/build-ascend-athlete-pack.sh "<dir>/Universal Base Characters[Standard]" \
#     AscendApp/Features/AscendMountain/Resources
#
# The sizes build in parallel; only the regular size writes the body's textures, so no two
# builds ever write the same file.
set -euo pipefail

pack="${1:?the Universal Base Characters [Standard] folder}"
out="${2:?the output folder}"
blender="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
script="$(cd "$(dirname "$0")" && pwd)/build-ascend-athlete.py"
logs="$(mktemp -d)"
trap 'rm -f "${logs:?}"/*.log; rmdir "${logs:?}"' EXIT

build() {
  local log="$logs/$1.log"
  shift
  "$blender" -b --python "$script" -- --pack "$pack" --out "$out" "$@" > "$log" 2>&1 || true
  grep -E '^athlete:' "$log" || true
  if grep -qE 'Traceback|^Error' "$log"; then
    cat "$log" >&2
    return 1
  fi
}

for body in male female; do
  pids=()
  for size in slim regular solid big; do
    textures=--no-textures
    [ "$size" = regular ] && textures=--write-textures
    build "$body-$size" --body "$body" --size "$size" --no-hair "$textures" \
      --name "ascend-athlete-$body-$size" --texture-prefix "ascend-athlete-$body" &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do
    wait "$pid"
  done
  build "$body-hair" --body "$body" --hair-pack --no-textures \
    --name "ascend-athlete-$body-hair" --texture-prefix "ascend-athlete-$body"
done
