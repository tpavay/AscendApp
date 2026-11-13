# Universal links

`https://ascendstepper.com/go?src=<tag>` opens the Ascend app on an iPhone that has it, and opens the App Store on one that does not.
The three lifecycle emails (`docs/lifecycle-drip-emails.md`) and every social bio (`docs/social-bio-link.md`) carry that one link.

## What happens when it is tapped

| The phone | Where the tap is | Result |
|---|---|---|
| Has Ascend (a build with the entitlement) | Mail, Messages, Notes, Safari's page links, most other apps | iOS never loads the web page. It opens Ascend, which lands where a launch lands: the onboarding gate, the first paywall, the founder letter or Home. The app records `go_link_opened`. |
| Has no Ascend, or an older build | Anywhere | The web page loads and sends the visitor to the App Store listing, exactly as before (`docs/social-bio-link.md`). |
| Has Ascend | An in-app browser (Gmail's and Outlook's built-in viewers, Instagram, Facebook, TikTok, the YouTube app) | See the caveat below. The web page loads first. |
| Has Ascend | Typing the address into Safari, or a link followed from another page on `ascendstepper.com` | iOS does not hand a navigation inside the same domain to an app, so the web page loads. The page sends the visitor to the App Store listing, and the App Store shows an Open button. |

The link opens the app to its normal launch state and nothing more.
It selects no screen, presents no sheet and writes nothing, so it cannot jump the onboarding gate, the first paywall or the founder letter, and the Google sign-in, Live Activity and Strava handlers see it only after they have declined it.

## The caveat: in-app browsers

Some mail apps open a tapped link in a browser of their own instead of handing it to iOS.
A universal link is only honoured when iOS itself is asked to open the URL, so there the web page loads first.
Nothing Ascend ships can change that.

What the page does in that case is what it already did for Instagram: on iOS it draws one large button and, a moment after the page paints, tries the hand-off by itself.
The button reads `Open the App Store`, and under it a short instruction says what to tap if nothing opened: the `···` menu, then `Open in Safari`.
A tap on the same link from Safari then opens the app.
A climber who has Ascend installed still lands on the App Store listing, which shows Open.

## The four pieces

Each is right or wrong on its own, and a link then opens Safari without any build or deploy failing, so `scripts/test/universal-links-contract.test.mjs` holds the first three to each other.

1. **The entitlement.**
   `AscendApp/AscendApp.entitlements` carries `com.apple.developer.associated-domains` with the single entry `applinks:ascendstepper.com`.
   All three configurations (Debug, Staging, Release) sign with that file.
2. **The site's file.**
   `web/public/.well-known/apple-app-site-association` has no extension and is served as `application/json`.
   It lists two app IDs, `QWGVB7TN4T.com.TylerPavay.AscendApp` and `QWGVB7TN4T.com.TylerPavay.AscendApp.staging`, and two paths, `/go` and `/go/*`.
   A path matches whatever query string follows it, so `?src=` always matches.
   The dev build's bundle ID is not listed, so a debug build never claims a link.
3. **The hosting config.**
   `firebase.json` sets `appAssociation` to `NONE`, gives the file an explicit `Content-Type: application/json` header, and has no redirect or rewrite on the path.
   Hosting infers no type for an extensionless file, and Apple's fetch needs JSON with no redirect.
   `appAssociation` has to be `NONE`: left on its default, Firebase serves a file it generates itself in place of the deployed one, and that file (what `ascendstepper.com` served on 2026-11-13) claims `/*`, which would open the app from the privacy policy and the support page.
4. **The app.**
   `GoLink` recognises the URL and `GoLinkHandler` records the event; `AscendApp.handleDeepLink` calls it last, after Google, Live Activity and Strava, from both `onOpenURL` and `onContinueUserActivity` (SwiftUI may deliver one tap through either, and the handler drops the second within five seconds).
   Matching is as narrow as the file: `https`, host `ascendstepper.com` exactly (not `www`), path `/go` or beneath `/go/`.

### Switches

There is no Remote Config kill switch, on purpose.
The switches in `docs/remote-config-kill-switches.md` guard paths that write or reshape persisted data, and this path writes nothing and routes nowhere: it reports one analytics event.
The off switch for the feature is on the server: remove the paths from the apple-app-site-association file, or the file itself, and redeploy Hosting.
iOS re-reads the file on app install and update and then periodically through Apple's CDN, so the change takes days to reach every phone and cannot be called instant.
An installed build that has been told to stop claiming the link simply goes back to opening the web page.

## The event

`go_link_opened`, defined in `AscendApp/App/Analytics/GoLinkAnalyticsEvent.swift`, beside the other app-lifecycle events.

| Parameter | Values |
|---|---|
| `src` | `email-paywall-abandoned`, `email-free-week-unused`, `email-trial-reminder`, `instagram`, `tiktok`, `youtube`, `facebook`, `none` (no `src`), `other` (any other `src`) |

`src` is bounded on purpose (`ascend-analytics`): an unregistered tag is `other`, never the text a stranger put in a URL.
A new email gets a case in `GoLink.Source` and a row here.
The event does not say whether the link launched the app or brought a running one forward: a process iOS started in the background, for a Health delivery or a push, would look like one the link started.
Climber route and sign-in state are not repeated on the event; they are on `app_session_started`.

## What the captain has to do before this ships

The Associated Domains capability is enabled on both App IDs that archive in CI, `com.TylerPavay.AscendApp` (App Store Connect id `KFLA2LJ45H`) and `com.TylerPavay.AscendApp.staging` (`9NG4886NU3`).
What remains is regenerating the two signing profiles, because they were made from those App IDs before the capability was on.
The dev App ID (`com.TylerPavay.AscendApp.dev`, `B6N2PL2224`) builds with automatic signing, so Xcode turns the capability on the first time a signed-in team member builds it.

1. **Regenerate the two profiles** in the signing repository.
   CI runs `fastlane match` read-only, and the profiles it fetches were made before the capability existed, so a staging or production archive fails with a message that the profile does not support Associated Domains until they are replaced.
   From a checkout with the signing repository's access:

   ```bash
   bundle exec fastlane match appstore --force \
     --app_identifier "com.TylerPavay.AscendApp,com.TylerPavay.AscendApp.staging"
   ```

   Run it without `MATCH_READONLY`, and leave out the widget and watch identifiers: they carry no entitlement that changed.
   The profiles keep their names (`match AppStore com.TylerPavay.AscendApp[.staging]`), so no workflow or Fastfile edit follows.
2. **Do it before this branch reaches `develop`.**
   A push to `develop` starts the staging archive, and it fails until step 1 is done.
3. **Deploy Hosting before the build reaches phones.**
   The file is only live on `ascendstepper.com` after a production deploy, because that site is served by the production Firebase project.
   A phone reads the file when the app is installed or updated, so a build that reaches a phone before the file is live does not claim the link until iOS next refreshes it.
   The production deploy checks the file itself (`scripts/ci/assert-aasa-served.mjs`, run after Hosting on staging and again on production) and fails if the file is not served as JSON, is redirected, or is Firebase's generated one.

## Testing it

### On a simulator

The app has to be installed first (the Staging scheme works), and the file has to be live on the domain, because the system fetches it from `ascendstepper.com` and a simulator does not read the local copy.

```bash
xcrun simctl boot <udid>
xcrun simctl install <udid> path/to/AscendApp.app
xcrun simctl openurl <udid> "https://ascendstepper.com/go?src=email-trial-reminder"
```

If the app opens, the association works.
If Safari opens instead, the system has not accepted the file for this build: read the next section.
Cold-launch the app from a tap by terminating it first: `xcrun simctl terminate <udid> <bundle id>`, then the `openurl` above.
A simulator already holds an answer for a domain it has asked about, so after changing the file run `xcrun simctl uninstall` and reinstall the app before trying again.

### On a device

1. Install a build that carries the entitlement (TestFlight is fine), with the file live.
2. Open the Notes app and type `https://ascendstepper.com/go?src=email-trial-reminder`.
3. Tap the link, rather than pasting it in Safari's address bar (a typed address is a navigation inside Safari and is never handed to an app).
   Ascend should open with no web page flashing first.
4. Terminate Ascend from the app switcher and tap again, to see the link launch the app.
5. Long-press the link: the menu should offer **Open in Ascend**.
   That entry is how you tell a working association from a slow one.
6. With the app deleted, tap the link: the page loads and the App Store listing opens.

The event shows in the debug telemetry console on a debug or staging build, and in the staging Mixpanel project as `go_link_opened`.

### Checking the file without a phone

```bash
curl -si https://ascendstepper.com/.well-known/apple-app-site-association
```

Expect `200`, `content-type: application/json`, no `location` header, and a body with `"components"`.
A body with `"paths":["NOT /__/auth/action/", ..., "/*"]` is Firebase's generated file, which means `appAssociation` is not `NONE` in the deployed config.
Apple keeps its own copy at `https://app-site-association.cdn-apple.com/a/v1/ascendstepper.com`, which is what a phone actually reads, and which can lag a fix by hours.

### The test suites

- `node --test scripts/test/universal-links-contract.test.mjs` keeps the entitlement, the file, the bundle IDs in the project and the hosting config consistent.
- `node --test scripts/test/assert-aasa-served.test.mjs` pins the post-deploy check.
- `AscendAppTests/GoLinkTests.swift` covers which URLs match, the `src` bound, the event and the duplicate delivery.

## Both builds installed on one phone

The staging build is in the file on purpose, so a TestFlight staging build can be exercised.
A phone with both the staging and the App Store build installed has two apps claiming the same links, and iOS picks one.
Test links on a phone with only the build under test, or expect the other to open.

## What this does not do

It does not change the emails, the paywalls or the offers.
It opens the app; it does not open a particular screen, and a climber who is signed out, unentitled or mid-onboarding lands exactly where a tap on the icon would have taken them.
It does not carry attribution into the app beyond the `go_link_opened` event, because the App Store campaign token only exists on the path through the store.
