# Functions secret versions

How a Cloud Functions secret changes in staging or production, and the checks that stop an unreviewed version from shipping.

Read "The rule" before creating any secret version, in any project.

## What went wrong

A Functions deploy binds every function to the **latest** version of each secret it declares (`defineSecret`), whatever the deploy was for.
Creating a secret version therefore changes nothing until the next Functions deploy, and then it ships with that deploy, unreviewed.

On 2026-09-08 `REVENUECAT_SERVER_CONFIG` version 3 was created in `ascend-prod-9c8f2` from a stale local copy of the config.
That copy predated `rc_promo_app_access_lifetime`, the product id every RevenueCat comp carries, so version 3 dropped it from `allowedProductIds`.
Version 3 was deliberately left undeployed.

On 2026-09-25 the 1.1 production deploy (Deploy Production run 36179234290) redeployed every function and rebound `revenueCatWebhook` and `reconcileAppAccess` from version 2 to version 3.
Nothing in `functions/src/revenueCat/` had changed; the break was the rebind alone.
From then on, every reconciliation projected comped climbers inactive and deleted their `users/{uid}/entitlements/app_access` grant, so every paid screen failed for them while the paywall, which reads RevenueCat directly, still let them in.
Two climbers lost access 32 and 64 minutes after the deploy, and four more were one app launch away.
Version 4 (version 3 plus the promo id) and a redeploy of those two functions fixed it.

## The rule

**Never create a secret version from a local copy.**
Build it from the version the deployed functions are bound to, change only the field you mean to change, and pin the new version in `functions/secret-versions.json` in the same reviewed pull request.

A local copy - the Keychain entry, a file, a paste from a previous session - goes stale silently.
The Keychain `revenuecat-*-server-config` entries exist so `scripts/comp-access.mjs` can read the RevenueCat API key; their `allowedProductIds` is known to lag the deployed one.
Only the version the deployed functions are bound to is the truth.

Do not try to undo an unwanted version by disabling it.
Secret Manager's `latest` alias still resolves to a disabled version (measured on 2026-09-25), and the deploy then refuses to bind anything at all.
The way back is a newer version rebuilt from the bound one.

## The pin

`functions/secret-versions.json` pins, for staging and production, the version each secret the functions source declares must be bound to after a deploy of that commit.
It is the acknowledgement: a version is safe to deploy only once a reviewed commit names it.

```json
{
  "ascend-prod-9c8f2": {
    "REVENUECAT_SERVER_CONFIG": 4
  }
}
```

The suite `scripts/test/functions-secret-guard.test.mjs` fails when a secret declared in `functions/src` has no pin in either project, or a pin names a secret nothing declares.
Adding a `defineSecret` therefore means creating the secret in both projects and pinning both.

## What the deploys check

Both `deploy-staging.yml` and `deploy-production.yml` run `scripts/verify-functions-secrets.mjs` twice inside the Firebase job.
Both runs are read-only, and neither prints a secret value: a changed secret is reported by the names of the keys that changed.

**Before any backend change** (`preflight`, ahead of the index deploy), the deploy stops unless:

- every declared secret's latest version is `ENABLED` and is exactly the version the manifest pins for that project at the commit being deployed, and
- the latest `REVENUECAT_SERVER_CONFIG` names the app's entitlement and allowlists every product that grants access.

The preflight also records every live grant and the `comp_grants` ledger for the second run.

**After the Functions deploy and before rules** (`verify-deploy`), the deploy stops unless:

- every function is bound to exactly the pinned versions, which catches a version created while the deploy ran,
- the bound `REVENUECAT_SERVER_CONFIG` still passes the invariant, and
- every grant the preflight recorded, comped or paid, still exists and is still allowlisted by the version the functions now run.

A grant is only deleted when that climber's next webhook delivery or `reconcileAppAccess` call runs, which can be minutes or days later.
That is why a grant that still exists is not enough, and the second condition is what would have stopped the 1.1 deploy.

A comp in `comp_grants` whose climber held no grant before the deploy is reported as a warning, not a failure, because the gap predates the deploy.

`.github/workflows/functions-secret-drift.yml` runs the same preflight against both projects every day and on dispatch, so a version nobody pinned turns red the day after it is created rather than on release day.

Exit codes: `0` safe, `1` the deploy must not proceed, `2` the check could not read something.
A `2` is never a pass; re-run the job, and never bypass the step.

### Which products the allowlist must keep

The required set is derived, not remembered:

- every `ASCEND_REVENUECAT_*_PRODUCT_ID` the environment's build configuration sets in `AscendApp.xcodeproj/project.pbxproj` (`Release` for production, `Staging` for staging),
- in production, the product `scripts/comp-access.mjs` grants by default, `rc_promo_{entitlement}_{DEFAULT_COMP_DURATION}` from `scripts/lib/comp-access-policy.mjs`, even while nobody holds one, and
- every product a live `users/{uid}/entitlements/app_access` grant holds, read from the project itself.

`entitlementId` must equal the default `revenueCatEntitlementID` in `MonetizationConfiguration.swift`.
`GUARDED_PROJECTS` in `scripts/lib/functions-secret-guard.mjs` owns the per-project choices.

Retiring a product that live grants still hold means revoking those grants first; the invariant refuses to drop it while anybody holds it.

### The credential

The checks read Secret Manager, the Cloud Functions API and Firestore with the deploy's own `FIREBASE_TOKEN`, minted into a Google access token through the pinned firebase-tools CLI (`scripts/lib/pinned-firebase-tools.mjs`).
That adds no privilege the deploy did not already hold, where a service account for these reads would be a new standing credential with production secret access.
Locally the same command uses your logged-in Firebase CLI session.

## Changing a secret

The worked example adds a product id to production's allowlist; the same shape applies to any field and to staging.

1. **Find the bound version.**
   The preflight prints the pinned, latest and bound version of every secret.

   ```sh
   node scripts/verify-functions-secrets.mjs preflight --project ascend-prod-9c8f2
   ```

   Stop if latest and bound differ: somebody already created a version, and it has to be understood first.

2. **Build the new version from the bound one, in memory.**
   The value never touches a file, the shell history or a command argument.

   ```sh
   set -o pipefail
   P=ascend-prod-9c8f2 S=REVENUECAT_SERVER_CONFIG BOUND=4 ADD=rc_promo_app_access_yearly
   NEW="$(gcloud secrets versions access "$BOUND" --secret "$S" --project "$P" | ADD="$ADD" node -e '
     let raw = "";
     process.stdin.on("data", (chunk) => (raw += chunk)).on("end", () => {
       const config = JSON.parse(raw);
       const keys = Object.keys(config).sort().join();
       if (config.allowedProductIds.includes(process.env.ADD)) throw new Error("already allowlisted");
       config.allowedProductIds.push(process.env.ADD);
       if (Object.keys(config).sort().join() !== keys) throw new Error("key set changed");
       process.stdout.write(JSON.stringify(config));
     });')" \
     && [ -n "$NEW" ] \
     && printf '%s' "$NEW" | gcloud secrets versions add "$S" --project "$P" --data-file=-
   unset NEW
   ```

   To replace a credential instead, read the new value with `read -rs` and set that one field the same way.

3. **Confirm only the intended key changed.**
   Re-run the preflight.
   It now fails with `version 5 was never acknowledged` and names the keys that changed against the bound version, which must be exactly the one you edited.

4. **Pin it.**
   Set the version in `functions/secret-versions.json` in a pull request to `develop`, including production pins, so the pin rides the same merge to `main` as everything else.
   Until that merge lands, every deploy of that project, and the daily drift check, fails on the unpinned version; that is the intended pressure, so do not leave a version unpinned.

5. **Deploy.**
   The merge to `develop` deploys staging and the merge to `main` deploys production; each preflight reports the acknowledged move as a notice naming the changed keys, and `verify-deploy` proves every grant survived it.

Do not create a version while a deploy of that project is running; `verify-deploy` would fail it.

### A hand deploy

An operator deploy (`firebase deploy --only functions:...`, as in the incident fix) binds the latest version exactly as CI does and runs neither check.
It is the path for a change that cannot wait for a merge, such as a lost webhook signing secret.
Edit the pin in the working tree first, so the preflight passes against the version you are about to bind, and land that edit in a pull request straight after; until it lands, every CI deploy refuses a version that is already live.
Run `verify-deploy` after the deploy with the snapshot the preflight wrote:

```sh
node scripts/verify-functions-secrets.mjs preflight --project ascend-prod-9c8f2 --snapshot /tmp/grants.json
# ... the deploy ...
node scripts/verify-functions-secrets.mjs verify-deploy --project ascend-prod-9c8f2 --snapshot /tmp/grants.json
```

## When a check fails

**`version N was never acknowledged`**
Somebody created a version and no commit pins it.
Compare the named keys with what was intended.
If it is right, pin it.
If it is not, or nobody knows where it came from, add a newer version rebuilt from the bound one (an exact copy is fine) and pin that.

**`does not allowlist <product>`**
The version the deploy would bind drops a product that the app sells, that comps are granted with, or that live grants hold.
Build a newer version from the bound one with the product restored, and pin it.

**`LOST` or `WILL BE LOST` after the Functions deploy**
The job stopped before rules, Storage, Hosting and the TestFlight upload.
The message quotes the lost climber's `entitlement_status`.
A refund or an expiry is legitimate: re-run the failed job, whose preflight takes a fresh snapshot.
Anything else is this incident again: build a newer version from the last good one, pin it, redeploy `revenueCatWebhook` and `reconcileAppAccess`, and confirm each climber's grant with `scripts/comp-access.mjs find` (the app reconciles on its next launch).

**Exit `2`**
A read failed or the repository inputs could not be parsed, so nothing was verified.
Re-run; if it persists, fix the read rather than the step.
