import { appStoreCampaignURL, bioLinkCampaignToken } from './appStore.ts';

export interface BrowserClassification {
  inApp: boolean;
  ios: boolean;
}

// On iOS every real browser (Safari, Chrome, Firefox, Edge, DuckDuckGo, Brave)
// carries a `Safari/` token, and an embedded in-app browser does not - the
// YouTube app's does not even claim AppleWebKit. `; wv)` is Android's WebView
// marker; Android needs no App Store hand-off, but it still gets the tap-first
// page rather than a redirect that may be swallowed.
export function classifyBrowser(userAgent: string): BrowserClassification {
  const ua = userAgent ?? '';
  const ios = /\b(iPhone|iPad|iPod)\b/.test(ua);

  if (ios && !/\bSafari\/\d/.test(ua)) {
    return { inApp: true, ios };
  }
  if (/\bAndroid\b/.test(ua) && /;\s*wv\)/.test(ua)) {
    return { inApp: true, ios: false };
  }

  return { inApp: false, ios };
}

// The App Store build's own URL scheme (`AscendURLScheme.production`). A staging or dev build
// answers to its own scheme, so this page only ever reaches the App Store build.
export const APP_URL_SCHEME = 'ascendapp';

// The `src` tags the app reports (`GoLink.Source`). Anything else is dropped from the app link
// rather than passed on as text a stranger put in a URL.
export const GO_LINK_SOURCES: readonly string[] = [
  'email-paywall-abandoned',
  'email-free-week-unused',
  'email-trial-reminder',
  'instagram',
  'tiktok',
  'youtube',
  'facebook'
];

export function appOpenURL(source: string | null | undefined): string {
  const key = (source ?? '').trim().toLowerCase();
  return GO_LINK_SOURCES.includes(key)
    ? `${APP_URL_SCHEME}://go?${new URLSearchParams({ src: key })}`
    : `${APP_URL_SCHEME}://go`;
}

// Mobile Safari itself, as opposed to Chrome, Firefox, Edge or the Google app, which all carry
// Safari's token too. `SFSafariViewController` sends Safari's user agent, so it counts as Safari.
export function isPlainMobileSafari(userAgent: string): boolean {
  const ua = userAgent ?? '';
  return /\bSafari\/\d/.test(ua) && !/\b(CriOS|FxiOS|EdgiOS|GSA)\//.test(ua);
}

function isEmailSource(source: string | null): boolean {
  return (source ?? '').trim().toLowerCase().startsWith('email-');
}

// `app`: a lifecycle email's link opened on an iPhone in a browser that did not let iOS hand it to
// Ascend (Gmail's viewer, Chrome). The page tries the app once and keeps both choices on screen.
// `in-app`: the tap-first App Store page. `browser`: straight to the product page.
export type HandoffMode = 'app' | 'in-app' | 'browser';

export interface HandoffPlan {
  mode: HandoffMode;
  inApp: boolean;
  // The app's own link, in `app` mode only.
  appURL: string | null;
  campaignToken: string;
  // The product page every browser can open.
  storeURL: string;
  // The App Store link this browser can follow: the App Store app's own
  // scheme in an iOS in-app browser, the product page everywhere else.
  storeLinkURL: string;
  // Where the big button and the automatic attempt go: the app in `app`
  // mode, otherwise the store link.
  handoffURL: string;
  // Only `browser` mode navigates straight to the store.
  redirect: boolean;
}

export function sourceFromSearch(search: string): string | null {
  return new URLSearchParams(search).get('src');
}

export function handoffPlan(userAgent: string, search: string): HandoffPlan {
  const source = sourceFromSearch(search);
  const browser = classifyBrowser(userAgent);
  const storeURL = appStoreCampaignURL(source, 'https');
  const storeLinkURL = browser.inApp && browser.ios ? appStoreCampaignURL(source, 'itms-apps') : storeURL;
  const appURL = browser.ios && isEmailSource(source) && !isPlainMobileSafari(userAgent) ? appOpenURL(source) : null;
  const mode: HandoffMode = appURL ? 'app' : browser.inApp ? 'in-app' : 'browser';

  return {
    mode,
    inApp: browser.inApp,
    appURL,
    campaignToken: bioLinkCampaignToken(source),
    storeURL,
    storeLinkURL,
    handoffURL: appURL ?? storeLinkURL,
    redirect: mode === 'browser'
  };
}
