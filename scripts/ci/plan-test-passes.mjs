#!/usr/bin/env node
/**
 * Writes the `xcodebuild` argument list for every test pass `iOS Verify
 * (Staging)` runs, one file per pass, without enumerating the suite first.
 *
 * The passes are named, never balanced: each isolated group is an
 * `-only-testing:` list, the static half of the remainder is an
 * `-only-testing:` list, and the last pass is `-skip-testing:` of exactly the
 * same names, so `xcodebuild` computes the complement itself and a suite that
 * did not exist when this file was written lands in the last pass by
 * construction. That is the property the old `-enumerate-tests` run existed to
 * protect, and it held it at the price of a whole host launch that executed
 * zero tests and absorbed the runner's cold simulator boot - 4.5 minutes of a
 * 40-minute job, measured 2026-09-02 on job 100376172708.
 *
 * What enumeration also caught - a name in this file that no longer matches a
 * real suite - is now caught after the pass instead: `run-ios-test-passes.sh`
 * reads every pass's `.xcresult` and fails when a named suite executed nothing,
 * and again when the job's executed total falls under `EXECUTED_TEST_FLOOR`.
 * A misspelled name here is therefore still a red check, never a suite that
 * quietly stops running.
 *
 * The split is by suite, never by individual test: a suite is the unit
 * `-only-testing` addresses cheaply, and `.serialized` suites assume their own
 * cases run together.
 */

import {realpathSync, writeFileSync} from "node:fs";
import {fileURLToPath} from "node:url";

const TEST_TARGET = "AscendAppTests";

/**
 * Suites that do not fit in a shared host process, as passes: every inner
 * array is one host process, every name in it is one suite.
 *
 * WHY, measured 2026-09-01 and again 2026-09-03 on `iOS Verify (Staging)`:
 * memory, never minutes. The first killed runs died with `EXC_BREAKPOINT` /
 * "mach_vm_allocate_kernel failed within call to vm_map_enter" - an allocation
 * failure, not a logic defect. The 2026-09-03 runs died quieter: pass 2 of
 * the two-way split completed 928 of 997 tests in four minutes, then produced
 * nothing for 27 minutes with the host alive, 13 screen-render suites still
 * in flight and 67 MB free on the runner, until the job hit its cap - which
 * GitHub reports as cancelled, not failed. Raising the cap changed nothing.
 *
 * What a 10 Hz RSS sampler shows about the suites in that pass (peak MB of
 * the host, a fresh process per suite, floor ~545 MB for a suite that renders
 * nothing): the screen-render evidence suites each hold 1,000-1,434 MB, and
 * they hold it - a suite's RSS climbs as each screenshot is rendered and never
 * comes back down (`SentryMaskingEvidenceTests` climbs 549 -> 1,074 MB and
 * stays there; `EmailPreferencesScreenSnapshotTests` settles at 1,174 MB after
 * peaking at 1,415). Swift Testing starts every suite in the pass at once, so
 * a shared host accumulates every rendered screen in it, which is why the
 * balanced passes die at their tail rather than on any one test, and why
 * splitting them finer collects the heavy suites together and measured a
 * HIGHER peak (2,881 MB four ways against 2,020 two ways).
 *
 * The remedy is to take the suites that dominate that accumulation out of the
 * shared hosts. One suite, `ShareComposerBackgroundFillEvidenceTests`, peaks
 * at 2,355 MB across five tests because three of them each export a real
 * movie through the AVFoundation pipeline at the 1080x2340 story frame - the
 * cost is the assertion, so it keeps a host entirely to itself. The other
 * heavy suites share one isolated host: each costs a fraction of that alone,
 * the pass holds a few dozen tests so there is little to accumulate, and each
 * extra host process costs the job ~2 minutes of simulator and `xcodebuild`
 * overhead, so one pass per suite is not affordable.
 *
 * Per-suite peaks behind the second group, MB, measured 2026-09-03:
 * EmailPreferencesScreenSnapshotTests 1,434 ·
 * AppAccessPaywallPlaceholderSnapshotTests 1,253 ·
 * SettingsReorganizationEvidenceTests 1,195 ·
 * PostAuthOnboardingNoNameStepEvidenceTests 1,187 ·
 * LiveReplayFieldPopulationRenderEvidenceTests 1,129 ·
 * SentryMaskingEvidenceTests 1,128 ·
 * PaywallDeleteAccountFromHostedPaywallEvidenceTests 1,122 ·
 * ManualLoggingAndImportRemovalEvidenceTests 1,114 ·
 * WorldTour2026CatalogueEvidenceTests 1,104 ·
 * LiveClimbSummaryRankHeroRenderEvidenceTests 1,099 ·
 * CompletedClimbRankSummaryEvidenceTests 1,063 ·
 * ClimbCurationSurfaceEvidenceTests 1,043 ·
 * LiveClimbRatingPromptPlacementEvidenceTests 1,005 ·
 * LockedOutSubscriberRecoveryEvidenceTests 1,000 ·
 * AppUpdateLockoutRootRouteEvidenceTests 996 ·
 * RankingGhostRenderEvidenceTests 957 ·
 * ShareStatClusterPresetEvidenceTests 951 ·
 * SentryMaskInteractionTests 916 ·
 * WorkoutDetailHeartRateVisibilityTests 915 ·
 * LiveClimbPaceSplitRowLayoutEvidenceTests 896.
 * The next suite down is 882 MB and the median render suite is ~600. Lifting
 * only the fourteen at 1,000 MB and above left one balanced pass at 1,916 MB;
 * lifting these twenty is what levelled both remainder passes.
 *
 * The second suite in the first group is there for ordering, not memory.
 * `ShareStatClusterPickerEvidenceTests` (701 MB, two tests, 6 s alone)
 * poisons the host it runs in for every hosted test that saves to SwiftData
 * after it: the next save posts a `ModelContext` notification, a SwiftData
 * SwiftUI observer the picker left behind traps on it (`EXC_BREAKPOINT` on
 * the main thread, SwiftData -> NotificationCenter -> _SwiftData_SwiftUI,
 * seven crash reports on 2026-09-03), and the host either dies - the pass
 * restarts and records the crash - or, worse, hangs inside the in-process
 * crash handler with every other test frozen behind it, which is the wedge
 * signature. Four local runs stalled every concurrent host that held it, a
 * `-skip-testing` bisect of the complement pass (attempts A-F) cleared the
 * moment it was skipped (1,755 tests in 66 s), and put in the serial group it
 * took `WorkoutDetailHeartRateVisibilityTests` down with it, the first suite
 * after it in source order. Swift Testing runs serial suites in source-file
 * order, so it goes after the movie suite in a pass where nothing follows it.
 * On the runner it completed in 62-99 s on all three 2026-09-02 jobs, which
 * is the same defect resolving slowly rather than never. It is a test defect
 * and is filed as one, not fixed here.
 *
 * Add a suite only with a measurement, and remove it the moment it stops
 * needing a host of its own. A name that no longer matches a real suite is
 * fatal on purpose, through the post-pass `.xcresult` check: a silently
 * dropped entry sends the suite back into a shared host, which is exactly how
 * this job started exhausting its runner.
 */
export const ISOLATED_PASSES = [
    ["ShareComposerBackgroundFillEvidenceTests", "ShareStatClusterPickerEvidenceTests"],
    [
        "AppAccessPaywallPlaceholderSnapshotTests",
        "ClimbCurationSurfaceEvidenceTests",
        "CompletedClimbRankSummaryEvidenceTests",
        "EmailPreferencesScreenSnapshotTests",
        "LiveClimbRatingPromptPlacementEvidenceTests",
        "LiveClimbSummaryRankHeroRenderEvidenceTests",
        "LiveReplayFieldPopulationRenderEvidenceTests",
        "LockedOutSubscriberRecoveryEvidenceTests",
        "ManualLoggingAndImportRemovalEvidenceTests",
        "PaywallDeleteAccountFromHostedPaywallEvidenceTests",
        "PostAuthOnboardingNoNameStepEvidenceTests",
        "SentryMaskingEvidenceTests",
        "SettingsReorganizationEvidenceTests",
        "WorldTour2026CatalogueEvidenceTests",
        "AppUpdateLockoutRootRouteEvidenceTests",
        "RankingGhostRenderEvidenceTests",
        "ShareStatClusterPresetEvidenceTests",
        "SentryMaskInteractionTests",
        "WorkoutDetailHeartRateVisibilityTests",
        "LiveClimbPaceSplitRowLayoutEvidenceTests",
    ],
];

/**
 * The static half of the remainder: the suites named here run in one shared
 * host, and everything not named anywhere in this file runs in the other.
 *
 * The remainder still needs two hosts. With the isolated groups lifted out,
 * one balanced half of it measured 1,523 MB peak locally (131 suites, 945
 * tests, 2026-09-03), so the whole remainder in one host would sit at the
 * 2,100-2,200 MB that wedged the runner.
 *
 * The line between the two halves balances the screen-render suites, not the
 * test count: every `.hostsAWindow` suite serialises on one shared gate, so a
 * remainder pass takes as long as the sum of its hosted renders whatever else
 * it holds, and a test's reported duration is mostly its wait in that queue.
 * The first cut of this list put the thirty heaviest render suites together
 * and measured it (2026-09-03, M4 Max, `-Onone` build): that pass took 365 s
 * against 46 s for the complement, two tests waited past the 300 s per-test
 * allowance, and the restart that allowance triggers dropped nine tests from
 * the record. So this list is the remaining render suites ranked by the same
 * 10 Hz RSS measurement, heaviest first (882 MB down to 535 MB; the floor for
 * a suite that renders nothing is ~545 MB), taking every other rank (the
 * gate-holding suite named above was an even rank and is isolated). Each
 * remainder pass then carries about half of the hosted rendering; the
 * complement also carries every logic suite, which is cheap, and every suite
 * added later.
 *
 * `RevenueCatPurchaseControllerRestoreTests` is here for a different reason:
 * run in the same host as `PaywallPurchaseAnalyticsContractTests`, five of
 * their tests fail with the restore coordinator never invoked (measured
 * 2026-09-03, whole suite in one host, `restoreCount -> 0`). The two-way
 * split had hidden that shared-state coupling by chance; naming one of the
 * pair here keeps them apart on purpose until the test defect is fixed.
 *
 * Move a suite across the line only with a measurement, and never let a name
 * appear both here and in an isolated pass: the planner refuses to write a
 * plan that names a suite twice.
 */
export const STATIC_REMAINDER_SUITES = [
    "RankingGhostFinishCardJourneyEvidenceTests",
    "PostAuthGenderQuestionCopySnapshotTests",
    "LiveClimbCompletionSummaryHealthPromptEvidenceTests",
    "ShareComposerWalkthroughEvidenceTests",
    "ClimbDetailHeadphoneAffordanceEvidenceTests",
    "PublicProfileAchievementsVisualEvidenceTests",
    "OnboardingNotificationsSkipTests",
    "FinalizedShareCardSetEvidenceTests",
    "EmailPreferenceLiveWindowEvidenceTests",
    "ClimbDetailHeadphoneAffordanceTests",
    "PublicProfileAchievementSnapshotWiringEvidenceTests",
    "ShareCardRenderingTests",
    "PublicProfileAchievementRenderingTests",
    "AccountRestoreAlertEvidenceTests",
    "LockedOutSubscriberRecoveryHostingTests",
    "ClimbLeaderboardTabVisualEvidenceTests",
    "WorkoutSyncListBadgeEvidenceTests",
    "TiedRankRenderEvidenceTests",
    "RouteScreenViewEvidenceTests",
    "RoutineTimelineDragEvidenceTests",
    "ClimbDropNotificationStateTests",
    "ShareComposerCaptainJourneyEvidenceTests",
    "WorkoutSyncStatusSectionHostingTests",
    "HeartRateSparseCopyDeviceWidthEvidenceTests",
    "RemoteMediaLoaderTests",
    "ClimbDetailRankStripTests",
    "HeartRateChartDropoutSnapshotTests",
    "RoutineHeartRateEvidenceTests",
    "LiveHeartRateStatusChipSnapshotTests",
    "LiveClimbHeartRateChartSnapshotTests",
    "RevenueCatPurchaseControllerRestoreTests",
];

/**
 * The fewest tests a green job may have executed across all of its passes.
 *
 * The suite executed 1,999 tests on the last enumerated run (job
 * 100376172708, 2026-09-02); that is the coverage baseline. The floor sits
 * under it so that ordinary churn - a deleted suite, a merged pair - does not
 * turn the check red, while a pass shape that silently drops a hundred tests
 * does. Moving it is a deliberate act: raise it when the suite grows, lower it
 * only with the deletion that justifies it named in the same change.
 */
export const EXECUTED_TEST_FLOOR = 1900;

/** Every suite this file names, each exactly once. */
export function namedSuites() {
    return [...ISOLATED_PASSES.flat(), ...STATIC_REMAINDER_SUITES];
}

/**
 * The passes in the order they run, each as the `xcodebuild` arguments it adds
 * to the common set and the suites it is expected to execute.
 *
 * Isolated passes run first so their memory is released before the long
 * passes start, and so a failure in one is reported against a five-test pass
 * rather than buried in a nine-hundred-test one. Isolated passes also run
 * serially: their suites are there because each rendered screen is retained
 * for the life of the host, and Swift Testing starts every suite at once, so
 * run in parallel their transient render peaks stack on top of that (the first
 * fourteen of the render group measured 2,491 MB parallel against 1,640 MB
 * serial; all twenty measure 2,011 MB serial, 2026-09-03).
 * The remainder passes stay parallel: serial measured within ~130 MB of
 * parallel there and costs the long passes their concurrency for nothing.
 */
export function planTestPasses() {
    const suites = namedSuites();
    const duplicates = suites.filter((suite, index) => suites.indexOf(suite) !== index);

    if (duplicates.length > 0) {
        throw new Error(
            `A suite may be named in only one pass: ${[...new Set(duplicates)].join(", ")}`
        );
    }

    const identifier = (suite) => `${TEST_TARGET}/${suite}`;
    const passes = ISOLATED_PASSES.map((group, index) => ({
        label: `isolated group ${index + 1}, serial`,
        arguments: [
            "-parallel-testing-enabled",
            "NO",
            ...[...group].sort().map((suite) => `-only-testing:${identifier(suite)}`),
        ],
        expectedSuites: [...group].sort().map(identifier),
    }));

    passes.push({
        label: "remainder, static half",
        arguments: [...STATIC_REMAINDER_SUITES]
            .sort()
            .map((suite) => `-only-testing:${identifier(suite)}`),
        expectedSuites: [...STATIC_REMAINDER_SUITES].sort().map(identifier),
    });

    passes.push({
        label: "remainder, everything not named",
        arguments: [...suites].sort().map((suite) => `-skip-testing:${identifier(suite)}`),
        expectedSuites: [],
    });

    return passes;
}

function main() {
    const [outputPrefix] = process.argv.slice(2);

    if (!outputPrefix) {
        console.error("usage: plan-test-passes.mjs <output-prefix>");
        process.exit(2);
    }

    const passes = planTestPasses();

    passes.forEach((pass, index) => {
        const path = `${outputPrefix}${index + 1}.txt`;
        writeFileSync(path, pass.arguments.join("\n") + "\n");
        const named =
            pass.expectedSuites.length > 0
                ? `${pass.expectedSuites.length} named suites`
                : `all but ${pass.arguments.length} named suites`;
        console.log(`pass ${index + 1}: ${pass.label} (${named}) -> ${path}`);
    });

    console.log(`executed-test floor: ${EXECUTED_TEST_FLOOR}`);
}

// `realpathSync` because a caller may name this file through a symlinked path
// (macOS puts `mkdtemp` under /var, which is /private/var), and the module URL
// is always the resolved one.
if (process.argv[1] && fileURLToPath(import.meta.url) === realpathSync(process.argv[1])) {
    main();
}
