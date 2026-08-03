# Firebase Config Plists

This folder holds the `GoogleService-Info-*.plist` for each environment.
`GoogleService-Info-Dev.plist` is committed.
The Staging and Production plists are gitignored and live outside git, symlinked in locally.

`scripts/link-firebase-plists.sh` runs from the Xcode build phase and creates those symlinks.
It never writes over a path git tracks, so the committed Dev plist is left exactly as checked out - including when `CONFIGURATION` is unset or unrecognized.
It also leaves any existing real file alone, which is how CI keeps the plists it decodes from base64 secrets into this folder.
If a tracked plist is missing from the working tree the script refuses to link over it; restore it instead:

```sh
git restore -- AscendApp/App/Firebase/GoogleService-Info-Dev.plist
```

You can set a custom secrets folder with:

```sh
export ASCEND_FIREBASE_PLISTS_DIR="$HOME/.config/ascend/firebase"
```

Files the script looks for in that source folder, linking only the ones missing here:

- `GoogleService-Info-Dev.plist`
- `GoogleService-Info-Staging.plist`
- `GoogleService-Info-Production.plist`

Regression coverage lives in `scripts/test/link-firebase-plists.test.mjs` (`node --test scripts/test/*.test.mjs`).
