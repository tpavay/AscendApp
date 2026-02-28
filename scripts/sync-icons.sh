#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_PATH="$SCRIPT_DIR/icon-manifest.txt"
CATALOG_PATH="$REPO_ROOT/AscendApp/Resources/Assets.xcassets"
REMOTE_BASE_URL="${PHOSPHOR_BASE_URL:-https://raw.githubusercontent.com/phosphor-icons/swift/main/Sources/PhosphorSwift/Resources/Assets.xcassets/SVG}"
GENERATED_PREFIX="ph-"
PRUNE_STALE=1

for arg in "$@"; do
    case "$arg" in
        --no-prune)
            PRUNE_STALE=0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: ./scripts/sync-icons.sh [--no-prune]"
            exit 1
            ;;
    esac
done

if [[ ! -f "$MANIFEST_PATH" ]]; then
    echo "Manifest not found: $MANIFEST_PATH"
    exit 1
fi

if [[ ! -d "$CATALOG_PATH" ]]; then
    echo "Asset catalog not found: $CATALOG_PATH"
    exit 1
fi

trim() {
    printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

token_to_asset_name() {
    local token="$1"
    local kebab
    kebab="$(printf '%s' "$token" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')"
    printf '%s%s' "$GENERATED_PREFIX" "$kebab"
}

resolve_local_source_catalog() {
    if [[ -n "${PHOSPHOR_SOURCE_DIR:-}" && -d "$PHOSPHOR_SOURCE_DIR" ]]; then
        if [[ -d "$PHOSPHOR_SOURCE_DIR/SVG" ]]; then
            printf '%s' "$PHOSPHOR_SOURCE_DIR/SVG"
        else
            printf '%s' "$PHOSPHOR_SOURCE_DIR"
        fi
        return
    fi

    find "$HOME/Library/Developer/Xcode/DerivedData" \
        -type d \
        -path '*SourcePackages/checkouts/swift/Sources/PhosphorSwift/Resources/Assets.xcassets/SVG' \
        2>/dev/null | head -n 1
}

LOCAL_SOURCE_CATALOG="$(resolve_local_source_catalog || true)"
if [[ -n "$LOCAL_SOURCE_CATALOG" ]]; then
    echo "Using local Phosphor source: $LOCAL_SOURCE_CATALOG"
else
    echo "Using remote Phosphor source: $REMOTE_BASE_URL"
fi

expected_assets_file="$(mktemp)"
trap 'rm -f "$expected_assets_file"' EXIT

processed_count=0

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line="${raw_line%%#*}"
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue

    IFS='|' read -r raw_token raw_icon raw_weight extra <<< "$line"
    if [[ -n "${extra:-}" ]]; then
        echo "Invalid manifest line: $raw_line"
        exit 1
    fi

    token="$(trim "${raw_token:-}")"
    icon="$(trim "${raw_icon:-}")"
    weight="$(trim "${raw_weight:-regular}")"

    if [[ -z "$token" || -z "$icon" ]]; then
        echo "Invalid manifest line: $raw_line"
        exit 1
    fi

    case "$weight" in
        regular|thin|light|bold|fill|duotone)
            ;;
        *)
            echo "Invalid weight '$weight' for token '$token'"
            exit 1
            ;;
    esac

    asset_name="$(token_to_asset_name "$token")"
    echo "$asset_name" >> "$expected_assets_file"

    icon_variant="$icon"
    if [[ "$weight" != "regular" ]]; then
        icon_variant="${icon}-${weight}"
    fi

    source_relative_path="${icon_variant}.imageset/${icon_variant}.svg"
    downloaded_svg="$(mktemp)"

    if [[ -n "$LOCAL_SOURCE_CATALOG" && -f "$LOCAL_SOURCE_CATALOG/$source_relative_path" ]]; then
        cp "$LOCAL_SOURCE_CATALOG/$source_relative_path" "$downloaded_svg"
    else
        if ! curl -fsSL "$REMOTE_BASE_URL/$source_relative_path" -o "$downloaded_svg"; then
            echo "Failed to fetch icon source: $source_relative_path"
            rm -f "$downloaded_svg"
            exit 1
        fi
    fi

    output_imageset_dir="$CATALOG_PATH/${asset_name}.imageset"
    mkdir -p "$output_imageset_dir"
    cp "$downloaded_svg" "$output_imageset_dir/${asset_name}.svg"
    chmod 644 "$output_imageset_dir/${asset_name}.svg"

    # Ensure UIKit gets a predictable intrinsic size for tab bar icons.
    if ! grep -q 'width=' "$output_imageset_dir/${asset_name}.svg"; then
        perl -0777 -i -pe 's/<svg\b/<svg width="24" height="24"/ unless /<svg\b[^>]*\bwidth=/' "$output_imageset_dir/${asset_name}.svg"
    fi

    cat > "$output_imageset_dir/Contents.json" <<EOF
{
  "images" : [
    {
      "filename" : "${asset_name}.svg",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "template-rendering-intent" : "template"
  }
}
EOF
    chmod 644 "$output_imageset_dir/Contents.json"

    rm -f "$downloaded_svg"
    processed_count=$((processed_count + 1))
done < "$MANIFEST_PATH"

if [[ "$PRUNE_STALE" -eq 1 ]]; then
    while IFS= read -r existing_imageset; do
        set_name="$(basename "$existing_imageset" .imageset)"
        if ! grep -Fxq "$set_name" "$expected_assets_file"; then
            rm -rf "$existing_imageset"
            echo "Removed stale generated icon set: $set_name"
        fi
    done < <(find "$CATALOG_PATH" -maxdepth 1 -type d -name "${GENERATED_PREFIX}*.imageset" | sort)
fi

echo "Synced $processed_count icon assets from manifest."
