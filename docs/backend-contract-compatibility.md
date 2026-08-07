# Backend and client contract compatibility

Ascend's production backend always serves more than the newest source tree.
Apple review separates a merge from delivery, and people install updates on their own schedules.
An app version that shipped weeks or months ago can therefore share the backend with today's version.

The governing invariant is simple: **the production backend must satisfy the union of the contracts required by every live app version.**

## What the contract is

The contract is the backend surface that an installed binary can observe or depend on:

- Firestore collection paths, document shapes, field names, field types, required and optional fields, and field meanings.
- Firestore and Storage security rules that authorize an operation and accept its payload.
- Callable Function names, request fields, response fields, types, error behavior, and meanings.
- Remote Config parameter keys, types, defaults, and meanings.

The client source code is not part of this compatibility contract.
New source is free to delete old models, repositories, decoders, and feature code when the new app no longer uses them.
Keeping a released client's source code in the newest app does nothing for the binary already installed on a phone.
Compatibility comes from preserving the backend behavior that binary calls, not from preserving dead client code in the current branch.

## Additive changes are the default

Every backend contract change is additive until the retirement loop below is complete.

- Add fields, paths, callable parameters, response fields, and Remote Config keys without removing or repurposing existing ones.
- Make new request fields optional for old callers, or introduce a new callable or document version when the new value is genuinely required.
- Preserve the type and meaning of every existing field and key because reusing a name for a different concept is a removal hidden inside a rename-free diff.
- Widen security rules to admit the new valid operation or shape while continuing to admit every valid operation and shape used by a live client.
- Preserve old required-field sets when widening strict `hasOnly` and `hasAll` validation, so an old client can still write a document that omits the new field.
- Keep old callable entry points and old Remote Config keys live even after the newest app stops using them.
- Keep a callable that any shipped client still needs exported from `functions/src/index.ts`, and keep it accepting its old request signature and returning its old response contract, because `scripts/verify-deployed-functions.mjs` reconciles the deployed function set exactly against this ref's exports and both deploy workflows run it.

Changing an optional field to required, narrowing an accepted enum, rejecting a previously accepted document version, changing a callable response type, or changing a Remote Config key's meaning is a narrowing.
Each one can break a released binary even when the newest source compiles and every current test passes.

### Security rules are the one surface where additive checks are not free

Firestore aborts rule evaluation once a request exceeds its expression budget, and the abort arrives as a bare `PERMISSION_DENIED` that is indistinguishable from a rule which deliberately refused the write, so an over-budget rule reads as a correct denial and can go undiagnosed.
The [`ascend-firebase-data` skill](../.claude/skills/ascend-firebase-data/SKILL.md) owns that budget, its measured per-check costs, and the hoisting rules that keep a validator affordable.
Every widening that adds validation therefore has to be measured, not assumed, with `tests/firebase-rules/workout-expression-budget.test.mjs` as the pattern to follow.
Measure every maximum valid document shape the affected rule can be asked to evaluate, including the largest shape each live client version can legitimately build, because a rule that still accepts small documents can already be refusing large ones.
If the additive validation cannot fit inside the budget, the change must move the new contract to a separately matched path or document version with its own evaluation budget, or complete the retirement loop below before narrowing the old contract.
Never break an active snapshot to buy room, and never assume checks can accumulate on a single matched path without cost.

### Worked replacement example

Suppose Ascend replaces the cloud-sync format for a completed stair-stepper climb.
Version 1 writes and reads `users/{uid}/workouts/{workoutId}`, while version 2 will write and read only `users/{uid}/climb_records/{climbId}`.

The safe end-to-end rollout is:

1. Add the `climb_records` model, its rules, its Functions, and any indexes alongside the existing workout backend.
2. Copy existing workout history into the new model without deleting or rewriting the original workout documents.
3. If both versions must see climbs created by the other version, deploy an idempotent server-side compatibility projection before version 2 ships.
4. Ship version 2 with only the new client model and repository, so the current source reads and writes `climb_records` and carries no obsolete version 1 client implementation.
5. Leave the version 1 path, fields, callable entry points, documents, and rules valid because a climber on version 1 can still finish a workout and sync through that contract.
6. Keep both backend surfaces until version 1 has completed the retirement loop.

This approach replaces the client subsystem cleanly while the backend serves both generations.
Deleting the version 1 Swift code is safe because version 1 already contains its own copy, but deleting or narrowing the version 1 backend is not safe while that copy can still run.

## Deploy ordering and the widening asymmetry

Security rules and Functions deploy from the repository and take effect for the whole Firebase project within seconds.
An App Store binary reaches users days later and then spreads unevenly.
These timelines make widening and narrowing fundamentally asymmetric.

A widening must reach the backend before or with the first app build that needs it.
Deploying the app first creates a window in which the new client sends a valid new field or calls a new Function and the old backend rejects it.
A narrowing has the opposite and larger blast radius because it breaks every live client that needs the removed behavior as soon as the backend deploy completes.
Waiting to ship a matching new app does not protect the clients already installed.

The standing rule is therefore not "make the backend match the newest app."
The standing rule is "make the backend accept everything required by all live apps, including the newest one."

### What the current workflows actually do

[Deploy Staging](../.github/workflows/deploy-staging.yml) runs on manual dispatch and on pushes to `develop` that touch one of its listed app, Functions, web, Firebase, rules, scripts, signing, or workflow paths.
Once triggered, its Firebase job always deploys indexes, waits for them, deploys Functions, verifies Functions, deploys Firestore rules, deploys Storage rules, and deploys Hosting in that order.
The Firebase job has no dependency on the iOS build and runs in parallel with it, so staging can change before the archive finishes or even when the archive fails.
That parallelism is a known CI safety gap tracked by [issue #202](https://github.com/tpavay/AscendApp/issues/202) rather than settled design, and the `ascend-deploy` skill owns the job graph it belongs to.
The TestFlight upload depends on both jobs, so a successful staging binary is not uploaded until the compatible backend deployment has succeeded.

[Deploy Production](../.github/workflows/deploy-production.yml) runs on manual dispatch and on pushes to `main` that touch one of its listed app, Functions, web, Firebase, rules, scripts, signing, or workflow paths.
It first checks `PRODUCTION_READY`, then requests the workflow's single protected-environment approval before any build or deploy work begins.
After approval, it builds the production IPA, deploys indexes, Functions, Firestore rules, Storage rules, and Hosting in dependency order, and only then uploads the IPA to TestFlight.
The production widening therefore lands after the artifact is built but before that artifact is uploaded.
The summary above is deliberately short, and [the production backend rollout runbook](production-backend-rollout-runbook.md) is the authoritative deploy procedure with the full step-by-step ordering.

Both workflows deploy rules when any path in their push allowlist triggers the workflow, not only when a rules file changed.
A documentation-only push does not trigger either deploy workflow because `docs/**`, `CLAUDE.md`, and its `AGENTS.md` symlink are not in those allowlists.

Remote Config has a separate release path.
Staging additively publishes new parameters to dev and staging before its archive begins, while no workflow publishes Remote Config to production.
A new production parameter must be published through the captain-only process in [the production backend rollout runbook](production-backend-rollout-runbook.md) before the production archive preflight will pass.

## Per-version contract snapshots

Every shipped app version should have a checked-in snapshot describing the backend surface that version requires.
A snapshot should identify the app version and build and record its Firestore paths, operations, accepted document shapes, callable request and response contracts, and Remote Config dependencies.
It should describe observable requirements rather than preserve or copy the old client source.

CI can consume every non-retired snapshot as a compatibility floor.
For each proposed backend diff, the gate can verify that current rules still permit the recorded operations and shapes, callable contracts remain compatible, and Remote Config keys retain their recorded types and meanings.
A removal, newly required field, narrower accepted value set, deleted callable, incompatible response, or missing Remote Config key should fail the pull request when any active snapshot still depends on it.

This document defines the policy but does not build that gate or choose the snapshot format.
[Issue #421](https://github.com/tpavay/AscendApp/issues/421) owns that implementation.

## The retirement loop

Retirement is the only supported exit from additive-only compatibility.

1. Measure adoption until the versions that depend on the old contract are understood and the intended cutoff is acceptable.
2. Raise the minimum supported app version to the first version that no longer needs the old contract.
3. Verify that older builds can no longer continue into backend-dependent product behavior.
4. Narrow the backend contract, remove the retired data or compatibility projection, and delete only the snapshots below the enforced minimum.

[Issue #319](https://github.com/tpavay/AscendApp/issues/319) owns the minimum-supported-version lever required for this loop.
Until that lever exists and has been used for the retiring versions, their backend contracts remain live.

Without this loop, old fields, rules, callables, keys, data, and snapshots accumulate forever.
That accumulation is the deliberate cost of continuing to support old clients, not permission to guess that nobody still runs them.
