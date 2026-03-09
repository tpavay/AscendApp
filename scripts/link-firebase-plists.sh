#!/bin/sh
set -eu

# Optional override for custom secret location
# Example:
#   export ASCEND_FIREBASE_PLISTS_DIR="$HOME/.config/ascend/firebase"
PLIST_SOURCE_DIR="${ASCEND_FIREBASE_PLISTS_DIR:-}"

PROJECT_ROOT="${SRCROOT:-$(pwd)}"
TARGET_DIR="${PROJECT_ROOT}/AscendApp/App/Firebase"
mkdir -p "$TARGET_DIR"

# On CI the decode step places real plist files directly into TARGET_DIR.
# If the required plist for the current configuration already exists there,
# skip the source-directory search entirely so CI archives succeed.
required_plist=""
case "${CONFIGURATION:-}" in
  Debug)   required_plist="GoogleService-Info-Dev.plist" ;;
  Staging) required_plist="GoogleService-Info-Staging.plist" ;;
  Release) required_plist="GoogleService-Info-Production.plist" ;;
esac

if [ -n "$required_plist" ] && [ -f "$TARGET_DIR/$required_plist" ]; then
  echo "Firebase plist already present at $TARGET_DIR/$required_plist — skipping link."
  exit 0
fi

find_first_existing_source_dir() {
  if [ -n "$PLIST_SOURCE_DIR" ] && [ -d "$PLIST_SOURCE_DIR" ]; then
    echo "$PLIST_SOURCE_DIR"
    return 0
  fi

  if [ -d "$HOME/.config/ascend/firebase" ]; then
    echo "$HOME/.config/ascend/firebase"
    return 0
  fi

  # Fallback: locate another local Ascend worktree that already has plists.
  found_dir="$(find "$HOME/.codex/worktrees" -path '*/AscendApp/AscendApp/App/Firebase' -type d 2>/dev/null | head -n 1 || true)"
  if [ -n "$found_dir" ]; then
    echo "$found_dir"
    return 0
  fi

  return 1
}

if ! source_dir="$(find_first_existing_source_dir)"; then
  cat <<MSG
error: Could not locate Firebase plist source directory.
Set ASCEND_FIREBASE_PLISTS_DIR to a folder containing:
- GoogleService-Info-Dev.plist
- GoogleService-Info-Staging.plist
- GoogleService-Info-Production.plist
MSG
  exit 1
fi

link_plist() {
  file_name="$1"
  source_file="$source_dir/$file_name"
  target_file="$TARGET_DIR/$file_name"
  required="${2:-0}"

  if [ ! -f "$source_file" ]; then
    if [ "$required" = "1" ]; then
      echo "error: Missing required $file_name in source dir: $source_dir"
      exit 1
    fi
    echo "warning: Skipping missing optional $file_name"
    return 0
  fi

  ln -sfn "$source_file" "$target_file"
}

required_dev=0
required_staging=0
required_production=0

case "${CONFIGURATION:-}" in
  Debug)
    required_dev=1
    ;;
  Staging)
    required_staging=1
    ;;
  Release)
    required_production=1
    ;;
esac

link_plist "GoogleService-Info-Dev.plist" "$required_dev"
link_plist "GoogleService-Info-Staging.plist" "$required_staging"
link_plist "GoogleService-Info-Production.plist" "$required_production"

echo "Linked Firebase plists from: $source_dir"
