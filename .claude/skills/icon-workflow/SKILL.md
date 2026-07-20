---
name: icon-workflow
description: Use when adding, changing, or syncing Ascend app icons - editing the icon manifest, running the icon sync script, adding AppIconToken mappings, or picking regular vs fill icon weights for tab bars, settings, and empty states.
---

# Icon Workflow Skill

Use this workflow whenever adding or changing app icons.

All paths below are repo-relative; run commands from the repo root.

## Goal
- Keep icon usage consistent through `AppIconToken`.
- Avoid manual SVG downloads.
- Avoid heavy package dependencies.

## Source of Truth
- Manifest: `scripts/icon-manifest.txt`
- Sync script: `scripts/sync-icons.sh`

Manifest format:
```txt
token|icon-name|weight
```
Example:
```txt
tabHome|house-simple|regular
tabHomeSelected|house-simple|fill
```

## Workflow
1. Update manifest entries for tokens/icons/weights.
2. Run:
```bash
./scripts/sync-icons.sh
```
3. If new token names were introduced, add/update mappings in:
   - `AscendApp/Shared/Models/AppIconToken.swift`
4. Use `AppIcon(token: ...)` in UI where practical for consistency.
5. Verify in app (especially tab bar selected vs unselected states).
6. Commit manifest + generated assets + Swift mapping updates together.

## Conventions
- Default/inactive state: `regular`
- Active/selected state: `fill`
- Prefer reusing existing tokens before creating new ones.
- Keep icon names and semantics consistent across tabs/settings/empty states.

## Notes
- The sync script is run only when icons change, not on every app build.
- Generated assets are `ph-*.imageset` in the app asset catalog.
