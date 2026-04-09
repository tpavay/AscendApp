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

skip_linking=0
if [ -n "$required_plist" ] && [ -f "$TARGET_DIR/$required_plist" ]; then
  echo "Firebase plist already present at $TARGET_DIR/$required_plist — skipping link."
  skip_linking=1
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

source_dir=""
if [ "$skip_linking" != "1" ]; then
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

if [ "$skip_linking" != "1" ]; then
  link_plist "GoogleService-Info-Dev.plist" "$required_dev"
  link_plist "GoogleService-Info-Staging.plist" "$required_staging"
  link_plist "GoogleService-Info-Production.plist" "$required_production"

  echo "Linked Firebase plists from: $source_dir"
fi

copy_selected_plist_into_bundle() {
  if [ -z "$required_plist" ]; then
    return 0
  fi

  if [ -z "${TARGET_BUILD_DIR:-}" ] || [ -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]; then
    return 0
  fi

  selected_plist="$TARGET_DIR/$required_plist"
  if [ ! -f "$selected_plist" ]; then
    echo "error: Selected Firebase plist not found: $selected_plist"
    exit 1
  fi

  bundle_resources_dir="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
  bundle_plist="${bundle_resources_dir}/GoogleService-Info.plist"
  mkdir -p "$bundle_resources_dir"
  cp "$selected_plist" "$bundle_plist"

  echo "Copied $required_plist to $bundle_plist"
}

validate_selected_plist_bundle_id() {
  if [ -z "$required_plist" ] || [ -z "${PRODUCT_BUNDLE_IDENTIFIER:-}" ]; then
    return 0
  fi

  selected_plist="$TARGET_DIR/$required_plist"
  if [ ! -f "$selected_plist" ]; then
    echo "error: Selected Firebase plist not found: $selected_plist"
    exit 1
  fi

  plist_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$selected_plist" 2>/dev/null || true)"
  if [ -z "$plist_bundle_id" ]; then
    echo "error: Could not read BUNDLE_ID from Firebase plist: $selected_plist"
    exit 1
  fi

  if [ "$plist_bundle_id" != "$PRODUCT_BUNDLE_IDENTIFIER" ]; then
    cat <<MSG
error: Firebase plist bundle ID mismatch.
  plist:   $plist_bundle_id
  target:  $PRODUCT_BUNDLE_IDENTIFIER
  file:    $selected_plist
MSG
    exit 1
  fi
}

validate_selected_plist_google_url_scheme() {
  if [ -z "$required_plist" ] || [ -z "${INFOPLIST_FILE:-}" ]; then
    return 0
  fi

  selected_plist="$TARGET_DIR/$required_plist"
  if [ ! -f "$selected_plist" ]; then
    echo "error: Selected Firebase plist not found: $selected_plist"
    exit 1
  fi

  info_plist_path="${PROJECT_ROOT}/${INFOPLIST_FILE}"
  if [ ! -f "$info_plist_path" ]; then
    echo "error: App Info.plist not found: $info_plist_path"
    exit 1
  fi

  reversed_client_id="$(/usr/libexec/PlistBuddy -c 'Print :REVERSED_CLIENT_ID' "$selected_plist" 2>/dev/null || true)"
  if [ -z "$reversed_client_id" ]; then
    echo "error: Could not read REVERSED_CLIENT_ID from Firebase plist: $selected_plist"
    exit 1
  fi

  if ! /usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes' "$info_plist_path" 2>/dev/null | grep -Fq "$reversed_client_id"; then
    cat <<MSG
error: Missing Google Sign-In URL scheme for selected Firebase plist.
  required scheme: $reversed_client_id
  info plist:      $info_plist_path
  firebase plist:  $selected_plist
MSG
    exit 1
  fi
}

validate_selected_plist_bundle_id
validate_selected_plist_google_url_scheme
copy_selected_plist_into_bundle
