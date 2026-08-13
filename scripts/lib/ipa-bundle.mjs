// Watch apps and other nested bundles have their own plists. The installable
// iOS app is the one app bundle directly beneath Payload.
const MAIN_APP_INFO_PLIST_PATTERN = /^Payload\/[^/]+\.app\/Info\.plist$/;

export function mainAppInfoPlistPath(archiveEntries) {
  const candidates = archiveEntries.filter((entry) => MAIN_APP_INFO_PLIST_PATTERN.test(entry));

  if (candidates.length === 0) {
    throw new Error(
      "contains no root-level iOS app Info.plist at Payload/<app>.app/Info.plist."
    );
  }

  if (candidates.length > 1) {
    throw new Error(
      `contains ${candidates.length} root-level iOS app Info.plists (${candidates.join(", ")}); expected exactly one.`
    );
  }

  return candidates[0];
}
