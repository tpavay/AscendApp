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

The exported-IPA checks then reported:

```text
Verified IPA contains no Payload/<app>.app/Watch/ directory.
Verified the phone bundle ships its opaque 1024x1024 AppIconStaging rendition.
Skipped the nested icon check because the IPA embeds no watch app.
Verified the Staging bundle resolves its dedicated Mixpanel destination.
Verified CFBundleVersion 2026081103.
```
