# Universal links

`https://ascendstepper.com/go?src=<tag>` opens the Ascend app on an iPhone that has it, and opens the App Store on one that does not.
The three lifecycle emails (`docs/lifecycle-drip-emails.md`) and every social bio (`docs/social-bio-link.md`) carry that one link.

## What happens when it is tapped

| The phone | Where the tap is | Result |
|---|---|---|
| Has Ascend (a build with the entitlement) | Mail, Messages, Notes, Safari's page links, most other apps | iOS never loads the web page. It opens Ascend, which lands where a launch lands: the onboarding gate, the first paywall, the founder letter or Home. The app records `go_link_opened`. |
| Has no Ascend, or an older build | Anywhere | The web page loads and sends the visitor to the App Store listing, exactly as before (`docs/social-bio-link.md`). |
| Has Ascend (the App Store build) | Gmail, Chrome, Outlook's built-in viewer, Instagram, Facebook, TikTok, the YouTube app | The web page loads first and tries the app's own link. See below. |
| Has Ascend | Typing the address into Safari, or a link followed from another page on `ascendstepper.com` | iOS does not hand a navigation inside the same domain to an app, so the web page loads. The page sends the visitor to the App Store listing, and the App Store shows an Open button. |

The link opens the app to its normal launch state and nothing more.
It selects no screen, presents no sheet and writes nothing, so it cannot jump the onboarding gate, the first paywall or the founder letter, and the Google sign-in, Live Activity and Strava handlers see it only after they have declined it.

## When the page loads first: Gmail, Chrome and in-app browsers

Some mail apps open a tapped link in a browser of their own, or in Chrome, instead of handing it to iOS.
A universal link is only honoured when iOS itself is asked to open the URL, so there the web page loads first: tapping the email link in the Gmail app on an iPhone went to the website and then the App Store.

So on any iPhone the page first tries the app's own scheme, `ascendapp://go?src=<tag>` (`web/src/goHandoff.ts`).
The tag is passed only when it is one the app knows (`GO_LINK_SOURCES`, the same set as `GoLink.Source`), and is dropped otherwise.
The link is loaded in a hidden frame rather than by navigating the page, because Safari answers a page navigation to a scheme no app handles with an "address is invalid" alert, and a frame that nothing answers fails silently.

- **The app is installed:** iOS may first ask whether to open Ascend.
  The app opens to its normal launch state and records `go_link_opened`, exactly like the universal link.
  The page notices it went to the background (`visibilitychange`, `pagehide` or `blur`) and cancels its fallback, so a climber who comes back to the browser is not then sent to the App Store.
- **The app is not installed:** nothing visible happens, and after 1.5 seconds the page carries on exactly as before: a real browser goes to the App Store listing, and an in-app browser draws the `Open the App Store` button with its instructions and tries the App Store hand-off.
  The fallback runs at most once.

A browser can still decline the hand-off, and only a device can say which do.
Safari and `SFSafariViewController` ignore an app scheme loaded in a frame; Safari is the case the universal link already covers, and there the frame attempt simply costs the 1.5-second wait before the App Store.
A WKWebView-based browser (Chrome, Gmail's own viewer, Instagram) passes a frame's scheme to its host app, which decides whether to open it.
Where it is declined the visitor sees what they saw before: the App Store, or the in-app page whose `···` menu, then `Open in Safari`, puts the tap where iOS honours the universal link.
Check Gmail and Chrome on a device with the App Store build before calling this case fixed (`Testing it`, below).

The page only knows the App Store build's scheme, `ascendapp`.
Staging answers to `ascendapp-stg` and dev to `ascendapp-dev` (`AscendURLScheme`), so on a phone with only a staging build the page's attempt reaches nothing and the App Store follows; staging is reached by the universal link alone.

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
   The page's app-scheme form is matched as narrowly: this build's own scheme (`AscendURLScheme.current`), host `go`, no path, and the same `src` bound; the Live Activity's `live-climb` link is not claimed.

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
7. With the App Store build installed, send the link to a Gmail address and tap it in the Gmail app, then open it in Chrome.
   Ascend should open (after an "Open in Ascend?" prompt, if the browser asks), and returning to the browser should not then open the App Store.

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
- `node --test scripts/test/social-bio-link.test.mjs` covers the page's plan: which visitors get the app link, the `src` bound on it, and the frame attempt with its one-time, cancellable fallback.
- `AscendAppTests/GoLinkTests.swift` covers which URLs match in both forms, the `src` bound, the event and the duplicate delivery.

## Both builds installed on one phone

The staging build is in the file on purpose, so a TestFlight staging build can be exercised.
A phone with both the staging and the App Store build installed has two apps claiming the same links, and iOS picks one.
Test links on a phone with only the build under test, or expect the other to open.

## What this does not do

It does not change the emails, the paywalls or the offers.
It opens the app; it does not open a particular screen, and a climber who is signed out, unentitled or mid-onboarding lands exactly where a tap on the icon would have taken them.
It does not carry attribution into the app beyond the `go_link_opened` event, because the App Store campaign token only exists on the path through the store.
