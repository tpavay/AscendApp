#!/usr/bin/env bash
set -euo pipefail

ipa_path="${1:-}"
expected_build_number="${2:-}"

if [ -z "$expected_build_number" ]; then
  echo "::error title=Build number handoff missing::BUILD_NUMBER_HANDOFF_MISSING: The build job published no verified build number. Refusing to upload or wait on an invented value." >&2
  exit 1
fi

if [[ ! "$expected_build_number" =~ ^[0-9]+$ ]]; then
  echo "::error title=Build number handoff invalid::BUILD_NUMBER_HANDOFF_INVALID: Expected a numeric build number, got '${expected_build_number}'." >&2
  exit 1
fi

if [ -z "$ipa_path" ] || [ ! -f "$ipa_path" ]; then
  echo "::error title=IPA unavailable::IPA_BUILD_NUMBER_UNAVAILABLE: Cannot inspect IPA at '${ipa_path:-<missing>}'." >&2
  exit 1
fi

info_plist_path=""
while IFS= read -r archived_path; do
  if [[ "$archived_path" =~ ^Payload/[^/]+\.app/Info\.plist$ ]]; then
    if [ -n "$info_plist_path" ]; then
      echo "::error title=IPA structure invalid::IPA_BUILD_NUMBER_UNAVAILABLE: The IPA contains more than one main app Info.plist." >&2
      exit 1
    fi
    info_plist_path="$archived_path"
  fi
done < <(zipinfo -1 "$ipa_path")

if [ -z "$info_plist_path" ]; then
  echo "::error title=IPA structure invalid::IPA_BUILD_NUMBER_UNAVAILABLE: The IPA contains no main app Info.plist." >&2
  exit 1
fi

if ! embedded_build_number="$(unzip -p "$ipa_path" "$info_plist_path" | plutil -extract CFBundleVersion raw -o - -- - 2>/dev/null)"; then
  echo "::error title=IPA build number unreadable::IPA_BUILD_NUMBER_UNAVAILABLE: Could not read CFBundleVersion from the IPA's main app Info.plist." >&2
  exit 1
fi

if [[ ! "$embedded_build_number" =~ ^[0-9]+$ ]]; then
  echo "::error title=IPA build number invalid::IPA_BUILD_NUMBER_INVALID: The IPA embeds non-numeric CFBundleVersion '${embedded_build_number}'." >&2
  exit 1
fi

if [ "$embedded_build_number" != "$expected_build_number" ]; then
  echo "::error title=Build number handoff mismatch::BUILD_NUMBER_HANDOFF_MISMATCH: The build job published '${expected_build_number}', but the IPA embeds '${embedded_build_number}'. Refusing to upload or wait on the wrong build." >&2
  exit 1
fi

printf '%s\n' "$embedded_build_number"
