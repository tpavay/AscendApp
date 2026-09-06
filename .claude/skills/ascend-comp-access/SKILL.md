---
name: ascend-comp-access
description: Use whenever the captain wants to give somebody free access to Ascend - "comp Bob Smith", "comp bob@gmail.com", "give this person a free account", "grant them the app", "take that comp back", or "who have we comped". Covers looking a climber up by email or display name, reading their live RevenueCat state, the duration/allowlist rule that decides whether a comp actually works, the confirmation gate, and proving the grant reached the server. Also fires when somebody who "has access" reports that the app opens but every screen fails.
---

# Comping App Access

Ascend has **two** access gates and a comp only works when it satisfies both.

| Gate | Reads | Where |
|---|---|---|
| Client paywall | RevenueCat entitlement `app_access`, directly | `AppRootRoute.swift` |
| Server | The Firestore document `users/{uid}/entitlements/app_access` | `firestore.rules`, `hasPaidAppAccess()` |

Only the RevenueCat webhook writes that Firestore document, and it writes it **only when the entitlement's product identifier is in that environment's `allowedProductIds`** (`functions/src/revenueCat/subscriber.ts`).

## The trap this skill exists to prevent

RevenueCat composes a promotional product identifier as **`rc_promo_{entitlement}_{duration}`**.
Every duration therefore produces a *different* identifier, and an environment allowlists them one at a time.

Granting a duration nobody allowlisted half-works in the worst possible way.
RevenueCat grants it, the client paywall opens, the person believes they have the app - and then the webhook refuses to write the grant document, so every server-guarded screen fails.
The captain hit exactly this on 2026-08-25 by granting "1 year": `rc_promo_app_access_yearly` was not allowlisted, and the person got "Leaderboard stalled" on a paywall they had already cleared.

**Never reason about which durations work from memory, from this file, or from a previous run.**
The allowlist lives in the deployed `REVENUECAT_SERVER_CONFIG` secret and it changes.
`scripts/comp-access.mjs` reads the live one and refuses anything it would not honor, which is why the tool exists instead of two dashboard tabs.

## Use the script

```bash
cd scripts && npm install    # once; firebase-admin
gcloud auth application-default login    # Firestore
gcloud auth login                        # reading the deployed allowlist

# Who is this, and what access do they have right now?
node scripts/comp-access.mjs find "Bob Smith" --env prod --confirm-production ascend-prod-9c8f2

# Show the plan and stop. This NEVER grants.
node scripts/comp-access.mjs grant bob@gmail.com --env prod --confirm-production ascend-prod-9c8f2 \
  --reason "podcast guest"

# Only after the captain has said yes to what that printed:
node scripts/comp-access.mjs grant bob@gmail.com --env prod --confirm-production ascend-prod-9c8f2 \
  --reason "podcast guest" --confirm-grant <uid>

node scripts/comp-access.mjs revoke bob@gmail.com --env prod --confirm-production ascend-prod-9c8f2 \
  --reason "guest window over" --confirm-revoke <uid>

node scripts/comp-access.mjs list --env prod --confirm-production ascend-prod-9c8f2
```

Exit codes are load-bearing: `0` done, `2` usage, `3` refused, `4` needs confirmation, `5` **half-done, act now**.

## The procedure, and where the agent stops

1. **Look them up.** Email or display name; the script also accepts a raw uid.
2. **Read the dossier out to the captain.** Name, email, when they joined, their live RevenueCat state, the live allowlist, and exactly what is about to be granted.
3. **Stop.** The first `grant` run always exits `4` and grants nothing.
4. **Wait for the captain to actually say yes.** Do not self-confirm, and do not treat "comp Bob Smith" as pre-authorization for the second command - the first run exists precisely to show them something they had not seen yet.
5. **Re-run with `--confirm-grant <uid>`.** The uid must match the account the lookup resolved. There is no `--yes`, no batch mode and no force flag, on purpose.
6. **Report the landing verdict, not the RevenueCat response.** Exit `5` means the comp is half done and the person is worse off than before you started.

## Live state is read, never assumed

Before anything is granted the script queries RevenueCat for that app user id and classifies what comes back:

| State | What it means for a comp |
|---|---|
| `NO ACCESS` | Nothing on record. The clean case. |
| `FREE TRIAL` | Mid-trial on a real store subscription. Apple **still** converts and charges them. |
| `PAYING` | Actively billed by Apple. |
| `BILLING RETRY` | Paying, with a billing problem flagged. |
| `LAPSED` | Had access, does not now. |
| `ALREADY COMPED` | Holds an `rc_promo_` entitlement already. Re-granting does not stack or extend. |

Never answer "do they have access" from Firestore, from a cached read, or from what somebody said in chat.
Only RevenueCat knows whether a subscription is a trial, and the answer changes what the comp does to them.

## A comp never cancels a subscription

This is the second warning the tool refuses to let anybody skip.

**A RevenueCat promotional entitlement never cancels, charges, refunds or converts a store subscription.**
It only layers free access on top of one.
Comp somebody who is paying, or mid-trial, and Apple keeps billing them on exactly the same schedule - and a `lifetime` promo permanently shadows their real purchase in RevenueCat's reporting, so the revenue they keep paying gets harder to see behind it.

Only the customer can stop it, in **Settings > Apple Account > Subscriptions** on their own iPhone.

So when the subject is on a live store subscription the script demands a second, separate flag - `--acknowledge-active-subscription` - and the captain has to have heard the warning before you add it.
If the intent was to *stop charging them*, a comp is the wrong tool: have them cancel, or refund through App Store Connect, and comp only what is left.

## Apple's Hide My Email wrinkle

A climber who signed in with Apple and chose Hide My Email has a `@privaterelay.appleid.com` address stored in Firestore - **not** the address they would give the captain.

- Looking them up by the address they told you finds nothing, and that is **not** evidence they have no account.
- **Display-name lookup is the path that works for them.**
- The script flags a relay address in its output so nobody mistakes it for a bad record. A relay address is a real, deliverable address.

The same wrinkle is why `ascend-onboarding` cares about `SuppliedNameAdoption`: an Apple account that supplied no name shows up as `CHANGE ME` or a `Climber A3F9MQ` handle, which makes a name lookup useless. Fall back to the uid.

## Never comp the App Store review account

`ascendstepper.appreview@gmail.com`, uid `bbB1ot2Ix6hZi3duuGSnXbInUKK2`.

Apple holds those credentials and reviews submissions with that account.
Its access is managed through the review flow, never through a comp; #506 already shows what an entitlement surprise during review costs.
The script refuses it by uid and by email and exits `3`.

## Where the record lives

Every grant and revoke appends to **`comp_grants/{uid}`** in the same Firebase project it acted on - who, when, why, which product, and whether it landed.
A comp with no note of who or why was the gap; `--reason` is required and a blank one fails before anything is granted.

Three deliberate choices there:

- **Top-level, not under `users/{uid}`.** Account deletion recursively removes that tree, and the record of what was spent on somebody has to outlive the account it was spent on.
- **Undeclared in `firestore.rules`.** Firestore's default deny already makes it unreachable from every client, and it holds nothing the app reads.
- **Protected in the wipe policy** (`scripts/lib/firestore-wipe-policy.mjs`), beside `_migrations`. An audit trail a database reset can erase is not an audit trail.

`list` reports the ledger **and** scans the live grant documents separately, marking anything comped outside this tool `[NOT IN LEDGER]`, because a dashboard grant leaves no ledger row.

## The three copies of the allowlist, and which one is true

This is the part that will waste an hour if nobody writes it down. `REVENUECAT_SERVER_CONFIG` exists in three places and **they drift**:

| Copy | Authority |
|---|---|
| The `revenuecat-*-server-config` Keychain entry | The API key only. Its `allowedProductIds` goes stale. |
| The latest Secret Manager version | Not necessarily deployed. |
| **The secret version the deployed `revenueCatWebhook` is bound to** | **The only one that decides whether a grant document gets written.** |

On 2026-08-25 the Keychain copy was a full version behind the deployed one - it still said `["ascend_yearly","ascend_monthly"]` while production had already been updated.
Reading the wrong copy would have refused a `lifetime` grant that actually works.

The script takes the API key from the Keychain (inline, never printed, never written to a file, never a command argument) and the allowlist from the deployed binding:

```bash
gcloud functions describe revenueCatWebhook --project <projectId> --region us-central1 \
  --format='value(serviceConfig.secretEnvironmentVariables[0].version)'
gcloud secrets versions access <version> --secret REVENUECAT_SERVER_CONFIG --project <projectId>
```

An allowlist that cannot be read is a **refusal**, never a permission.

## Environments

| Alias | Project | Comping |
|---|---|---|
| `dev` | `ascend-f2e4f` | **Refused.** No Functions deployment and no RevenueCat webhook, so a grant can never land. |
| `staging` | `ascend-staging-fa7d5` | Allowed, but as of 2026-08-25 its allowlist holds no `rc_promo_` identifier at all, so **every** duration is refused there until one is added and Functions redeployed. |
| `prod` | `ascend-prod-9c8f2` | Requires `--confirm-production ascend-prod-9c8f2`, matching `deploy-remote-config.mjs`. |

## When a comp half-worked

Symptom: the person gets past the paywall and every server-guarded screen fails ("Leaderboard stalled", permission errors on climbs and profile).

`users/{uid}/entitlement_status/app_access` is written on **every** webhook delivery, while `users/{uid}/entitlements/app_access` is written only for an allowlisted product. So:

- **status exists, `isActive: false`, no grant document** - the webhook delivered and *refused the product*. The allowlist is the problem, not the delivery. Waiting will never fix it. Revoke, add the identifier to `REVENUECAT_SERVER_CONFIG.allowedProductIds`, redeploy Functions, grant again.
- **neither document** - the webhook has not landed. It normally takes seconds; check the RevenueCat integration's delivery log and the `revenueCatWebhook` logs.

Read those two documents with `ascend-data-investigation`'s wrapper, and honor its absence rule - a read that failed and a document that is missing both print nothing.

## Offer Codes are the better tool for somebody with no account

A comp attaches to a Firebase UID, so the person has to have **signed up already**.
For anyone who has not - a press contact, a giveaway, a bulk promotion - use an **App Store Offer Code** instead: it is redeemed in the App Store, produces a real `ascend_yearly` / `ascend_monthly` subscription, needs no allowlist change because those product ids are already allowlisted, and shows up in reporting as what it is.
`storekit` and `asc-release-flow` own that path.

## Before you tell the captain it worked

- [ ] Did the script exit `0`? `5` means half done - say so plainly.
- [ ] Did you quote the **landing** verdict, not "RevenueCat accepted it"?
- [ ] Did the captain actually say yes between the two commands?
- [ ] Did you name the environment?
- [ ] If they were paying or on a trial, did the captain hear that Apple keeps billing them and only they can cancel?
