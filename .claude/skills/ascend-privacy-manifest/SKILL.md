---
name: ascend-privacy-manifest
description: Use when Ascend collects a new data type - any new Firestore field, HealthKit metric read, or profile/onboarding input captured from the user - calls a required-reason API (UserDefaults, file timestamps, boot time, disk space, active keyboards), adds or upgrades a third-party SDK or Swift package, or starts ATT-sense tracking, and when preparing App Store submission. These triggers fire while editing Swift sources or project.pbxproj, not just while editing the manifest itself. Covers PrivacyInfo.xcprivacy maintenance, the four artifacts that must agree (manifest, privacy policy, App Store questionnaire, Info.plist usage strings), and when to flip NSPrivacyTracking.
---

# Privacy Manifest Maintenance

`AscendApp/PrivacyInfo.xcprivacy` is a machine-readable Apple privacy manifest that ships inside the app bundle. It is REQUIRED for App Store submission and must stay in sync with reality.

Load the `app-store-review` skill for submission prep and rejection-risk audits, and `ios-security` for device-side secret handling.

## Update the manifest in the SAME PR whenever you:

1. **Collect a new data type** - any new field written to Firestore, Firebase Storage, Crashlytics, Analytics, a new HealthKit metric read, or a new profile/onboarding field captured from the user. Add or extend an entry under `NSPrivacyCollectedDataTypes` with the right Apple data type, `Linked` flag, and purpose(s).
2. **Call a new "required reason" API category** - `UserDefaults`, file timestamp APIs (`.contentModificationDateKey`, `stat`, `getattrlist`, etc.), system boot time (`mach_absolute_time`, `systemUptime`), disk space (`volumeAvailableCapacity`, `statfs`), or active keyboards (`UITextInputMode.activeInputModes`). Add an entry under `NSPrivacyAccessedAPITypes` with an Apple-approved reason code from https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api.
3. **Add or upgrade a third-party SDK** - open the SDK's bundled `PrivacyInfo.xcprivacy` and add any new data type / API reason it forces on the host app.
4. **Start performing tracking** in the ATT sense (cross-app or cross-site identifiers, ad networks, IDFA collection) - flip `NSPrivacyTracking` to `true`, populate `NSPrivacyTrackingDomains`, implement the ATT prompt via `ATTrackingManager`, and add `NSUserTrackingUsageDescription` to `Info.plist`.

## What the tests enforce

`AscendAppTests/PrivacyManifestTests.swift` is the executable check on the manifest, and it is stricter than a spot review.
It pins every `NSPrivacyCollectedDataTypes` entry to its expected `Linked` flag and purpose set, rejects any purpose outside Apple's six valid values, and pins every `NSPrivacyAccessedAPITypes` category to its reason codes.
It also scans every Swift file under `AscendApp/` for literal `setUserProperty("…")` names, plus the `set("…")` wrapper inside `OnboardingAnalyticsUserProperties`, and fails until each one is classified against the manifest data type that declares it - which must be linked, non-tracking, and carry the Analytics purpose.

Analytics **event parameters** are not scanned, because a parameter's data type can depend on call-site context rather than on its name (`selected_value` on `leaderboard_filter_changed` is Health, Other Data Types, or Coarse Location depending on `filter_type`).
Classify a new event parameter by hand; the tests only guarantee that every category such a parameter can land in is declared for Analytics.

## The four artifacts must agree

The privacy manifest, the user-facing Privacy Policy at `ascendstepper.com/privacy`, the App Store Connect "App Privacy" questionnaire (nutrition labels), and the `NS*UsageDescription` strings in `Info.plist` must all describe the SAME set of data practices. If you change one, change all four.

## Current posture

The current manifest declares NO tracking and NO ads. Firebase Analytics is enabled in Release/TestFlight only, with `IS_ADS_ENABLED=false`. Do not enable ad SDKs or IDFA collection without flipping `NSPrivacyTracking` and adding ATT.

When in doubt about whether something needs to be declared, declare it. Under-declaring is a rejection risk; over-declaring is not.
