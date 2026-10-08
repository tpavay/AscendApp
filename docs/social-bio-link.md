# Social bio link

Every social bio points at one link on ascendstepper.com, never at the App Store URL itself.
Instagram's in-app browser drops an `apps.apple.com` navigation silently, so a raw store link in a bio is a blank page for the audience most likely to tap it.
`https://ascendstepper.com/go` is the one link; `?src=` names the platform so App Store Analytics can tell the bios apart.

## The one URL per platform

Copy these exactly.
It is one page, `/go`, with one URL per platform, and those URLs differ only in `src`.
The page and what it does are identical everywhere; only `src` and the call-to-action wording around the link change from platform to platform.

| Platform | Where it goes | URL |
|---|---|---|
| Instagram | Bio "Website" link | `https://ascendstepper.com/go?src=instagram` |
| TikTok | Profile "Website" field (links in captions are not clickable) | `https://ascendstepper.com/go?src=tiktok` |
| YouTube | Channel page link (links in Shorts are not clickable, so every Short points at the channel) | `https://ascendstepper.com/go?src=youtube` |
| Facebook | Page "Website" field and post captions | `https://ascendstepper.com/go?src=facebook` |
| Anywhere else | Email signatures, QR codes, DMs | `https://ascendstepper.com/go` |

## Where each visitor ends up

The page sends every visitor to Apple's campaign link for Ascend, with the campaign token picked from `src`:

| `src` | Campaign token (`ct`) | App Store URL the visitor reaches |
|---|---|---|
| `instagram` | `Instagram-bio` | `https://apps.apple.com/app/apple-store/id6757202987?pt=128011549&ct=Instagram-bio&mt=8` |
| `tiktok` | `TikTok-bio` | `https://apps.apple.com/app/apple-store/id6757202987?pt=128011549&ct=TikTok-bio&mt=8` |
| `youtube` | `YouTube-shorts` | `https://apps.apple.com/app/apple-store/id6757202987?pt=128011549&ct=YouTube-shorts&mt=8` |
| `facebook` | `Facebook-bio` | `https://apps.apple.com/app/apple-store/id6757202987?pt=128011549&ct=Facebook-bio&mt=8` |
| missing or anything else | `Link-direct` | `https://apps.apple.com/app/apple-store/id6757202987?pt=128011549&ct=Link-direct&mt=8` |

`pt=128011549` is Ascend's App Store Connect provider token and `mt=8` is the App Store media type.
Adding a platform means adding one row to `BIO_LINK_CAMPAIGNS` in `web/src/appStore.ts`, a row here, and a campaign of the same name in App Store Connect; nothing invents tokens on the fly.
Installs attributed to these tokens show up in App Store Connect under Analytics, Sources, Campaigns.

## How the page behaves

The logic is `web/src/goHandoff.ts`; the page is `web/src/pages/go.astro`; `scripts/test/social-bio-link.test.mjs` holds the contract.

- **In an in-app browser** (Instagram, Facebook, Messenger, TikTok, the YouTube app, or any other: an iOS user agent with no `Safari/` token, or an Android one carrying the `; wv)` WebView marker): the page stays on screen with one large button, `Open the App Store`, that links to the App Store app's own scheme (`itms-apps://`, which a webview passes to iOS even when it refuses an `https://apps.apple.com` hand-off).
  The same hand-off is attempted automatically a moment after the page paints.
  Under the button, a short instruction says what to tap if nothing opened (the `···` menu, then `Open in Safari` or `Open in browser`), plus a plain link to the https product page.
- **In a real browser** (Safari, Chrome, Firefox, Edge on iPhone; any desktop browser; Android): the page redirects straight to the https campaign link with `location.replace`, so the back button never lands on the bounce page.
  The button is still rendered underneath for the moment the redirect is in flight.
- **Without JavaScript**: the server-rendered button and App Store badge already link to the `Link-direct` campaign URL, so there is always something to tap. Attribution needs the script, so a no-script visitor counts as direct.

The page is standalone on purpose: no nav, no site footer beyond one home link, no stylesheet or script request, no tracking.
The site carries no analytics script, and the bounce page is not where one appears; the campaign token is the attribution.

## Verifying a change

`npm --prefix web run build` then open `web/dist/go.html` behind a static server with clean URLs and each platform's iPhone user agent.
The pull request that added the page (`fm/ascend-bio-link-go-page`) ran that headless with Playwright for Instagram, Facebook, TikTok, YouTube, Safari, Chrome, desktop, no `src` and no JavaScript, capturing the navigation each case requested; `scripts/test/social-bio-link.test.mjs` pins the user agents and URLs that run proved.
