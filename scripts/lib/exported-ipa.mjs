// `xcodebuild -exportArchive` names the IPA after the scheme, so the export
// directory - never the file name - is what identifies the artifact a given
// export produced. A second IPA sharing that directory is indistinguishable
// from the fresh one, and every downstream check reads the published name, so
// the only safe answer to "which IPA did this export produce" is the single
// candidate or a loud refusal.
export function selectExportedIpa(directoryEntries) {
  const candidates = directoryEntries.filter((entry) => entry.endsWith(".ipa")).sort();

  if (candidates.length === 0) {
    throw new Error("holds no exported .ipa.");
  }

  if (candidates.length > 1) {
    throw new Error(
      `holds ${candidates.length} exported .ipa files (${candidates.join(", ")}); expected exactly one.`
    );
  }

  return candidates[0];
}
