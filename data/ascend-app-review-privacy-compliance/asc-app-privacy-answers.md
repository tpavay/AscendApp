# Ascend App Privacy Answers

Last audited: July 28, 2026.

This is the exact App Store Connect checklist for the code and pinned dependencies on this branch.
Copy the "PR description" section into the pull request description.
The captain must enter and confirm the App Privacy answers in App Store Connect.

## PR description

### Privacy compliance

This change aligns Ascend's privacy manifest, public privacy policy source, and App Store Connect declaration with actual app behavior.

The audit traced identity and telemetry call sites for Firebase Analytics, Firebase Crashlytics, Mixpanel, Sentry, RevenueCat, and Superwall.
Ascend identifies the signed-in Firebase user to all six services, so User ID and the data those services associate with it are declared as linked to the user.
Purchase History and Device ID are also linked.
No data is used for App Tracking Transparency tracking.

The app manifest now uses only Apple's valid collection-purpose values.
The invalid `NSPrivacyCollectedDataTypePurposeCustomerSupport` value was removed, and feedback was declared under Apple's `NSPrivacyCollectedDataTypeCustomerSupport` data type with App Functionality as its purpose.
The manifest also distinguishes feedback from workout notes, adds the actual analytics and personalization purposes, and fixes Purchase History linkage.

Required-reason API coverage is complete for UserDefaults `CA92.1`, file timestamps `C617.1`, disk space `E174.1`, and system boot time `35F9.1`.
No Active Keyboards required-reason API use was found.

All five pinned SDK families have the privacy-manifest coverage required for their integration form.
Sentry and Firebase Analytics ship signed binary XCFramework artifacts whose signatures validate.
Mixpanel, RevenueCat, Superwall, and Firebase Crashlytics are source package products, so Apple does not require a separate binary signature for those products.
No SDK upgrade blocker was found.
Firebase Analytics intentionally does not ship its own `PrivacyInfo.xcprivacy`; Google documents that it is not on Apple's required-SDK manifest list, while the Firebase source modules that require manifests, including Crashlytics, include them.

### Validation

- `plutil -lint AscendApp/PrivacyInfo.xcprivacy`
- `PrivacyManifestTests`
- Release device compilation with code signing disabled through app and dependency compilation, followed by direct packaged-artifact verification
- Packaged app privacy-manifest inventory
- `codesign --verify --deep --strict` for the Sentry and Google binary XCFramework artifacts
- `cd web && npm run build`

### Captain action

Enter the field-by-field App Privacy answers below in App Store Connect.
Confirm the deployed privacy policy contains the updated identity-linkage and HealthKit synchronization disclosures before submission.
No monetization behavior or dashboard configuration was changed.

## App Store Connect field-by-field checklist

### Data collection and tracking

- [ ] Select **Yes, we collect data from this app**.
- [ ] Do not select any data type as used for tracking.
- [ ] Confirm **Data Used to Track You** is empty.
- [ ] Ascend does not need an ATT prompt for the audited configuration.

### Contact Info

- [ ] **Name**
  - [ ] Collected: Yes
  - [ ] Linked to the user's identity: Yes
  - [ ] Used for tracking: No
  - [ ] Purpose: App Functionality
- [ ] **Email Address**
  - [ ] Collected: Yes
  - [ ] Linked to the user's identity: Yes
  - [ ] Used for tracking: No
  - [ ] Purpose: App Functionality
- [ ] **Physical Address**: Not collected
- [ ] **Phone Number**: Not collected
- [ ] **Other User Contact Info**: Not collected

### Health and Fitness

- [ ] **Health**
  - [ ] Collected: Yes
  - [ ] Linked to the user's identity: Yes
  - [ ] Used for tracking: No
  - [ ] Purpose: App Functionality
- [ ] **Fitness**
  - [ ] Collected: Yes
  - [ ] Linked to the user's identity: Yes
  - [ ] Used for tracking: No
  - [ ] Purposes: Analytics, Product Personalization, App Functionality

### Financial Info

- [ ] **Payment Info**: Not collected
- [ ] **Credit Info**: Not collected
- [ ] **Other Financial Info**: Not collected

Apple processes payment credentials and does not expose payment-card details to Ascend.
Subscription and transaction history are declared separately under Purchases.

### Location

- [ ] **Coarse Location**
  - [ ] Collected: Yes
  - [ ] Linked to the user's identity: Yes
  - [ ] Used for tracking: No
  - [ ] Purposes: Analytics, App Functionality
- [ ] **Precise Location**: Not collected

### Sensitive Info

- [ ] **Sensitive Info**: Not collected

### Contacts

- [ ] **Contacts**: Not collected

### User Content

- [ ] **Photos or Videos**
  - [ ] Collected: Yes
  - [ ] Linked to the user's identity: Yes
  - [ ] Used for tracking: No
  - [ ] Purpose: App Functionality
- [ ] **Customer Support**
  - [ ] Collected: Yes
  - [ ] Linked to the user's identity: Yes
  - [ ] Used for tracking: No
  - [ ] Purpose: App Functionality
- [ ] **Other User Content**
  - [ ] Collected: Yes
  - [ ] Linked to the user's identity: Yes
  - [ ] Used for tracking: No
  - [ ] Purpose: App Functionality
- [ ] **Emails or Text Messages**: Not collected
- [ ] **Audio Data**: Not collected
- [ ] **Gameplay Content**: Not collected

`Other User Content` covers workout notes.
`Customer Support` covers feedback and support requests.

### Browsing History

- [ ] **Browsing History**: Not collected

### Search History

- [ ] **Search History**: Not collected

### Identifiers

- [ ] **User ID**
  - [ ] Collected: Yes
  - [ ] Linked to the user's identity: Yes
  - [ ] Used for tracking: No
  - [ ] Purposes: Analytics, App Functionality
- [ ] **Device ID**
  - [ ] Collected: Yes
  - [ ] Linked to the user's identity: Yes
  - [ ] Used for tracking: No
  - [ ] Purposes: Analytics, App Functionality

`User ID` includes the Firebase Auth UID passed to Firebase Analytics, Crashlytics, Mixpanel, Sentry, RevenueCat, and Superwall.
`Device ID` includes APNs and FCM registration tokens plus app-specific analytics identifiers such as Firebase App Instance ID, Firebase Installation ID, Mixpanel device distinct ID, and Superwall vendor ID.
It does not represent IDFA use.

### Purchases

- [ ] **Purchase History**
  - [ ] Collected: Yes
  - [ ] Linked to the user's identity: Yes
  - [ ] Used for tracking: No
  - [ ] Purposes: Analytics, App Functionality

RevenueCat and Superwall receive subscription, product, paywall, and purchase-result data after the app identifies the signed-in user.

### Usage Data

- [ ] **Product Interaction**
  - [ ] Collected: Yes
  - [ ] Linked to the user's identity: Yes
  - [ ] Used for tracking: No
  - [ ] Purposes: Analytics, App Functionality
- [ ] **Advertising Data**: Not collected
- [ ] **Other Usage Data**: Not collected

### Diagnostics

- [ ] **Crash Data**
  - [ ] Collected: Yes
  - [ ] Linked to the user's identity: Yes
  - [ ] Used for tracking: No
  - [ ] Purpose: App Functionality
- [ ] **Performance Data**
  - [ ] Collected: Yes
  - [ ] Linked to the user's identity: Yes
  - [ ] Used for tracking: No
  - [ ] Purpose: App Functionality
- [ ] **Other Diagnostic Data**
  - [ ] Collected: Yes
  - [ ] Linked to the user's identity: Yes
  - [ ] Used for tracking: No
  - [ ] Purpose: App Functionality

Crashlytics and Sentry receive crash state, nonfatal errors, logs, device and OS context, and the signed-in user ID.
Ascend feedback diagnostics also contain the device model, OS version, app version, and build number.

### Surroundings

- [ ] **Environment Scanning**: Not collected

### Body

- [ ] **Hands**: Not collected
- [ ] **Head**: Not collected

### Other Data

- [ ] **Other Data Types**
  - [ ] Collected: Yes
  - [ ] Linked to the user's identity: Yes
  - [ ] Used for tracking: No
  - [ ] Purposes: Analytics, Product Personalization, App Functionality

`Other Data Types` covers onboarding survey answers and profile demographics that do not map to a more specific Apple category.
Ascend logs the actual onboarding cohort values for analytics and uses experience and exercise answers to personalize the first-climb recommendation.

## SDK manifest and signature audit

| SDK | Pinned version | Actual Ascend behavior | SDK privacy manifest | Signature at pinned artifact | Status |
|---|---:|---|---|---|---|
| Sentry Cocoa | 9.18.0 | Sets the Firebase user ID on `Sentry.User`; captures errors, diagnostics, device and OS context | Present at `Sources/Resources/PrivacyInfo.xcprivacy`; declares crash, performance, diagnostics, UserDefaults, boot time, and file timestamps | Signed `Sentry.xcframework`; signature validates to GetSentry LLC team `97JCY7859U` | Pass |
| Mixpanel Swift | 6.4.0 | Calls `identify(distinctId:usePeople:)` with the Firebase user ID; records product interactions, onboarding cohorts, and workout event properties | Present at `Sources/Mixpanel/PrivacyInfo.xcprivacy`; configuration-neutral collected-data array is intentionally empty and UserDefaults reason `1C8F.1` is declared | Source package product; separate binary signature not applicable | Pass, with app-level declarations required |
| RevenueCat | 5.74.0 | Calls `logIn` with the Firebase user ID; receives products, subscriptions, purchase history, and entitlement state | Present at `Sources/PrivacyInfo.xcprivacy`; declares Purchase History and UserDefaults `CA92.1` | Source package product; separate binary signature not applicable | Pass, with app-level linked declaration required |
| Superwall | 4.15.3 | Calls `identify` with the Firebase user ID; receives app user ID, vendor ID, app and device context, paywall events, products, and purchase results | Present at `Sources/SuperwallKit/Resources/PrivacyInfo.xcprivacy`; declares Purchase History and file timestamps `C617.1` | Source package product; separate binary signature not applicable | Pass, with app-level linked declaration required |
| Firebase Analytics and Crashlytics | 11.15.0 | Analytics sets the Firebase user ID and records product, onboarding, workout, subscription, and app-lifecycle events; Crashlytics sets the same user ID and records crashes and nonfatal diagnostics | Crashlytics and Firebase source modules include manifests. Google documents that Firebase Analytics itself intentionally has no manifest because it is not on Apple's required-SDK manifest list | Signed `FirebaseAnalytics`, `GoogleAppMeasurement`, and transitive on-device conversion XCFrameworks validate to Google LLC team `EQHXZ8M8AV`; Crashlytics is a source package product | Pass |

No missing manifest or signature requires an SDK upgrade at these pinned versions.
Firebase Analytics resolves Google's signed on-device-conversion package transitively, but Ascend does not call its email, phone, or user-data conversion APIs.
The successful simulator launch also reports that `GoogleAppMeasurementIdentitySupport` is not linked and IDFA is unavailable.

## Required-reason API audit

| API category | Reason | Evidence | Result |
|---|---|---|---|
| UserDefaults | `CA92.1` | Ascend settings, repositories, and caches access first-party defaults in the app container | Declared in the app manifest |
| UserDefaults | `1C8F.1` | Mixpanel accesses its SDK-owned defaults | Declared in Mixpanel's bundled manifest |
| File Timestamp | `C617.1` | `DiskAssetCache` reads `contentModificationDateKey` for cache eviction; Sentry and Superwall also declare file timestamp access | Declared |
| Disk Space | `E174.1` | Mapbox Common and Core Maps manage SDK-owned map and tile caches | Declared |
| System Boot Time | `35F9.1` | Mapbox Common and Core Maps, Sentry, and gRPC use elapsed-time APIs | Declared |
| Active Keyboards | None | No app or packaged SDK declaration or direct call was found | Not used |

The source scan and packaged Release manifest inventory did not identify another required-reason category.

## Validation environment note

The unsigned Release device build completed Swift compilation and produced an app bundle whose app and SDK manifests were verified directly.
The final build phase then stopped because this disposable worktree does not have the gitignored `GoogleService-Info-Production.plist`.
That environment-only condition does not affect the privacy source changes, and the same code and manifest passed the Staging simulator build and privacy tests.
The normal release or CI environment must supply the production Firebase plist before archive validation, as documented by `AscendApp/App/Firebase/README.md`.

## Code audit evidence

- `AuthenticationViewModel` sends the authenticated Firebase UID to `TelemetryManager.setUserId` and `MonetizationManager.identify`.
- `FirebaseTelemetrySink` calls `Analytics.setUserID`.
- `MixpanelTelemetrySink` calls `identify(distinctId:usePeople:)`.
- `FirebaseDiagnosticSink` calls `Crashlytics.setUserID`.
- `SentryDiagnosticSink` assigns `Sentry.User.userId`.
- `MonetizationManager` calls both `Purchases.logIn` and `Superwall.identify`.
- Workout and Live Climb telemetry includes workout duration, step buckets, completion, and rank context.
- Onboarding telemetry records experience, exercise level, goals, motivation, planned frequency, gender, age group, weight group, country, notification choice, and first-climb state.
- First-climb recommendations use onboarding experience and exercise answers.
- Feedback submissions contain user-authored text and attached diagnostic context.
- Workout notes and user media sync to user-scoped cloud storage.

## Fixes included in code

- Corrected the app privacy manifest's linked flags, collected data types, and purposes.
- Added a regression test for the exact collected-data and required-reason API contract.
- Updated the public privacy-policy source with HealthKit synchronization and service identity-linkage disclosures.
- Left monetization behavior unchanged.
- Left Xcode project build settings unchanged.

## Captain and dashboard actions

1. Enter every listed field above in App Store Connect.
2. Confirm the App Store Connect App Privacy summary shows all declared data as linked and none as tracking.
3. Deploy the updated `web/src/pages/privacy.astro` build before submission and confirm the live `/privacy` page includes the new disclosures.
4. Perform a final Firebase production-console check that Google Ads linking, Google Signals, and advertising personalization remain disabled.
5. Keep Superwall Apple Search Ads attribution disabled unless a future change adds ATT and updates every privacy surface.

The Superwall production application audit found Apple Search Ads configuration disabled.
The checked-in development and staging Firebase configurations have ads collection disabled.
No dashboard action requires a product decision for the current non-tracking posture.

## Authoritative references

- Apple third-party SDK requirements: <https://developer.apple.com/support/third-party-SDK-requirements/>
- Apple privacy manifest files: <https://developer.apple.com/documentation/bundleresources/privacy-manifest-files>
- Apple data-use declarations: <https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests>
- Apple collected-data purposes: <https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatypepurposes>
- Firebase Apple-platform data collection: <https://firebase.google.com/docs/ios/app-store-data-collection>
- Google Analytics data collection: <https://support.google.com/analytics/answer/11593727>
- Mixpanel App Store privacy details: <https://mixpanel.com/legal/app-store-privacy-details/>
- Superwall privacy nutrition labels: <https://superwall.com/docs/ios/guides/app-privacy-nutrition-labels>
- Superwall identity management: <https://superwall.com/docs/identity-management>
