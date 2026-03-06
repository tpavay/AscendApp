# Firebase Local Config (Not Committed)

This folder stores local symlinks to `GoogleService-Info-*.plist` files.

The actual plist files should live outside git and are linked by:

- `scripts/link-firebase-plists.sh`

You can set a custom secrets folder with:

```sh
export ASCEND_FIREBASE_PLISTS_DIR="$HOME/.config/ascend/firebase"
```

Expected files in the source folder:

- `GoogleService-Info-Dev.plist`
- `GoogleService-Info-Staging.plist`
- `GoogleService-Info-Production.plist`
