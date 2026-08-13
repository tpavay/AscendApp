# Watch 1.0 Packaging Evidence

The release split is owned by [`docs/heart-rate-zones-plan.md`](../../../heart-rate-zones-plan.md).

This evidence was captured on 2026-08-13 with Xcode 26.3 build 17C528.

## Before the packaging change

A signed `AscendApp-Staging` archive and App Store Connect IPA export succeeded.
The exported IPA contained these entries:

```text
Payload/AscendApp.app/Watch/
Payload/AscendApp.app/Watch/AscendWatch.app/
Payload/AscendApp.app/Watch/AscendWatch.app/Info.plist
Payload/AscendApp.app/Watch/AscendWatch.app/AscendWatch
```

## After the packaging change

A clean signed `AscendApp-Staging` archive succeeded.
The build graph still compiled `AscendWatch` as an explicit dependency.
The archived phone product had no `AscendApp.app/Watch/` directory.
The App Store Connect IPA export succeeded.

This command returned no entries:

```bash
zipinfo -1 AscendApp.ipa | rg '^Payload/[^/]+\.app/Watch/'
```

That `zipinfo` command is the artifact-level proof that the IPA carries no watch app.
No CI check asserts that fact against an IPA; the only automated guard is source-side, over `project.pbxproj`, in `scripts/test/watch-target-configuration.test.mjs`.
`scripts/ci/assert-app-icon-present.mjs` treats zero embedded watch bundles as the normal 1.0 warning path rather than a failure, which is what it did here.

Summary of the exported-IPA checks that were run (paraphrased, not tool output):

- `assert-app-icon-present.mjs` passed on the phone bundle's opaque 1024x1024 `AppIconStaging` rendition, and emitted its `::warning::` for the skipped nested watch-icon check.
- `assert-mixpanel-bundle.mjs Staging` passed, resolving the Staging bundle's dedicated Mixpanel destination.
- `verify-ipa-build-number.sh` reported build number `2026081103`.
