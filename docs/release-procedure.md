# Releasing Ascend

How a change gets from a merged pull request to a build sitting in App Store Connect, ready for you to submit.

Read the two facts below first.
They are the ones that have actually cost a release.

## The two facts that bite

**1. A version train closes the moment that version goes live.**
Ascend 1.0 is on the App Store, so Apple refuses every further upload that declares `CFBundleShortVersionString` as `1.0`:

> Invalid Pre-Release Train. The train version '1.0' is closed for new build submissions.

`MARKETING_VERSION` in `AscendApp.xcodeproj/project.pbxproj` must be **above the last released version before the merge to `main`**, not after the deploy fails.
Build numbers take care of themselves (`scripts/ci/derive-build-number.sh` allocates them from App Store Connect); the marketing version is the one number a human still moves.

**2. A merge to `main` deploys the server immediately, and only then tries to upload the app.**
`deploy-production.yml` deploys Firestore indexes, Cloud Functions, rules, Storage, and Hosting, and *then* uploads the IPA.
If the upload fails, everything before it has already shipped.

That is the silent half-release: the backend is live on the new contract, the app in users' hands is still the old binary, and the run's failure email is the only sign.
On 2026-08-25, run 32886787708 did exactly this because the marketing version was still `1.0`.

Both facts point at the same habit: **bump the version in the pull request, not in a follow-up.**

## Version numbering

| Change | Next version |
|---|---|
| Fixes, copy, tuning, no new user-visible capability | patch: `1.0` to `1.0.1` |
| A new feature users can see and use | minor: `1.0.1` to `1.1` |

`1.1` is spoken for.
`docs/heart-rate-zones-plan.md` reserves it for the release that embeds the watch app, and `deploy-production.yml` refers to "the 1.1 release" in the same sense.
Do not spend `1.1` on something else without moving that plan first.

Apple accepts one to three numeric components.
`SemanticAppVersion` compares missing components as zero, so `1.0.1` sorts above `1.0` and below `1.1`, and the Remote Config version thresholds in `remoteconfig.template.json` keep working across the change.

## What is automatic, and what is not

| Step | Who |
|---|---|
| Bump `MARKETING_VERSION` | **You**, in the pull request |
| Allocate the build number | Automatic (`derive-build-number.sh`) |
| Archive, sign, export the IPA | Automatic (`fastlane build_production`) |
| Deploy Firebase: indexes, functions, rules, storage, hosting | Automatic |
| Upload the build to TestFlight | Automatic (`fastlane upload_testflight`) |
| Create the App Store version record | Automatic (`prepare-app-store-version.yml`) |
| Attach the processed build to it | Automatic (same workflow) |
| Write the "What's New" release notes | **You** |
| Check App Privacy, age rating, pricing | **You** |
| **Press Submit for Review** | **You. Always.** |
| Release the approved build to users | **You.** Version records are created with `releaseType: MANUAL` |

The pipeline deliberately writes **no listing metadata**.
`data/ascend-support-page-and-product-page-package/app-store-copy.md` records the listing that is already live; it is a transcript, not a source of truth, so pushing it would overwrite your listing from a stale document.
The preparation step reads the version's localizations and tells you which locales still have empty release notes, and stops there.

### Why submission is not automated

This is a decision, not a gap.
An iOS binary cannot be rolled back once it is live, and the captain wants to read the version himself before it goes in front of App Review.

`scripts/test/app-store-submission-guard.test.mjs` enforces it mechanically: it fails the build if any workflow, Fastlane lane, or pipeline script gains the power to submit for review, release automatically, or steer a phased rollout.
If you are tempted to "finish the job", that test is the answer, and the answer is no.

## The walkthrough

1. **Open the pull request against `develop`**, with `MARKETING_VERSION` already at the next version if this work is going out.
   CI runs the verification jobs the changed paths select.

2. **Merge `develop` into `main`** when the release is ready.
   That push triggers **Deploy Production**, which pauses on a single approval gate (`environment: production`).
   Approve it once; the pipeline requests approval before any work starts, deliberately, so a late second request cannot sit unnoticed.

3. **Deploy Production runs**, in this order: production readiness gate, approval, build and sign the IPA, deploy Firebase, upload to TestFlight, deploy status.
   A run that deploys nothing concludes `failure` rather than a green no-op (`assert-deploy-outcome.sh`).
   A cancelled run is caught from outside by `deploy-production-watchdog.yml`.

4. **Prepare App Store Version runs by itself** once Deploy Production concludes successfully.
   It waits for Apple to finish processing the build, creates the App Store version record for the marketing version that was archived, and attaches the build.
   It is a separate workflow on purpose: build processing takes far longer than the upload, and waiting inside `deploy-production`'s concurrency group would displace a queued production deploy.

5. **You open App Store Connect.**
   Write the release notes, read the version, and press Submit for Review.
   The workflow's run summary links straight to the app's distribution page.

## Running the preparation step by hand

The workflow is a thin wrapper around a script you can run yourself, with the same App Store Connect API key CI uses (`APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY`).

```bash
# Report what it would do. Writes nothing.
npm --prefix scripts run appstore:prepare-version

# Create the version record and attach the newest build in the train, once it is processed.
npm --prefix scripts run appstore:prepare-version:confirm

# Pin the version and the build explicitly.
node scripts/appstore-prepare-version.mjs --confirm --version 1.0.1 --build 2026082801
```

Without `--version` it reads `MARKETING_VERSION` from the checked-out Xcode project, and refuses if the targets disagree.
Without `--build` it takes the **newest** build in that version's train and waits until Apple has processed it.
Not the newest build that happens to be processed already: this workflow starts seconds after the deploy uploads, so an earlier build in the same train is very often ready first, and attaching it would hand you the previous binary and call it success.
Waiting is a loud failure if it times out; attaching the wrong binary is a silent wrong result.

The dry run reports which locales still have empty "What's New", once the version record exists to read localizations from.
It sends no POST and no PATCH.

If the version record already has a **different** build attached, the run refuses rather than swapping the binary under a version you may be part-way through preparing.
Re-run with `--build <number>` to say that is what you mean.

You can also re-run it from the Actions tab: **Prepare App Store Version** accepts an optional version and build number.

## When to submit

**Early in the week, and small.**

Ship one change rather than a week of them, and submit on a Monday or a Tuesday.
A rejection then costs an afternoon.
The same rejection on a Friday costs the weekend, and you find out about it on Saturday morning.

This is the captain's standing preference, decided 2026-08-28.

## When something goes wrong

**"The train version 'X' is closed for new build submissions"**
The marketing version is at or below a version that already shipped.
Bump `MARKETING_VERSION`, merge, and re-run.
The Firebase half of that failed run already deployed; nothing needs undoing, but the app in the store is still the previous build.

**The deploy went green but no version record appeared**
Check the **Prepare App Store Version** workflow, not Deploy Production.
It only runs when Deploy Production concluded `success`.
If Apple was still processing the build when its budget ran out, re-run it from the Actions tab; it is idempotent, and reuses the version record if one already exists.

**The prepare run says there is nothing to prepare**
The version for that marketing version is already with Apple, or already released, so it cannot take a build.
On the run chained off Deploy Production that is a clean green no-op with a run summary saying so, because a backend-only merge to `main` still uploads a build while the previous version is in review, and a red run for a correct outcome only teaches everyone to ignore red runs.
Either you meant to bump `MARKETING_VERSION` for the next release, or you want to cancel the submission in App Store Connect first.

Running **Prepare App Store Version** from the Actions tab yourself still fails loudly on the same state (`App Store version X is IN_REVIEW, which this script may not write to`), because there you asked for that version by name.
The script never writes to a version mid-review; that is not recoverable from a script.

**"App Store version X already has a different build attached"**
Somebody, or an earlier run, already attached a build to that version record.
The run will not swap it out silently.
Decide which binary goes to review and re-run with `--build <number>`, or attach it in App Store Connect.

**The prepare run timed out waiting for a build**
It waits for the *newest* build in the train, deliberately, so a stale build that processed first is never attached instead.
Re-run it from the Actions tab once App Store Connect shows the build as ready; it is idempotent.

**A bad build is already live**
Neither this pipeline nor a resubmission is the fast lever.
Flip the relevant Remote Config kill switch first (`docs/remote-config-kill-switches.md`), then pause the rollout with `scripts/appstore-phased-release.mjs pause --confirm`.
Pausing stops further users being moved onto the build; it does not remove it from anyone who already updated.

## Related

- `.claude/skills/ascend-deploy/SKILL.md` - the job graph, secrets, and build-number allocator in full
- `docs/remote-config-kill-switches.md` - the two undo levers a shipped binary has
- `docs/production-backend-rollout-runbook.md` - what production actually holds
- `data/ascend-support-page-and-product-page-package/app-store-copy.md` - a record of the live listing, not a source the pipeline pushes from
