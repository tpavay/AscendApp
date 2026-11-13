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

// How long the page waits for the app to take over before it falls back to the App Store.
export const APP_FALLBACK_DELAY_MS = 1500;

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

export interface HandoffPlan {
  inApp: boolean;
  // On iOS, the app's own link, tried before anything else: a mail app's own browser or Chrome
  // loads this page instead of letting iOS hand the universal link to Ascend.
  appURL: string | null;
  campaignToken: string;
  // The product page every browser can open.
  storeURL: string;
  // Where the big button and the automatic attempt go. In an iOS in-app
  // browser that is the App Store app's own scheme; everywhere else the
  // product page.
  handoffURL: string;
  // Outside an in-app browser the page navigates straight to the store.
  redirect: boolean;
}

export function sourceFromSearch(search: string): string | null {
  return new URLSearchParams(search).get('src');
}

export function handoffPlan(userAgent: string, search: string): HandoffPlan {
  const source = sourceFromSearch(search);
  const browser = classifyBrowser(userAgent);
  const storeURL = appStoreCampaignURL(source, 'https');
  const useAppScheme = browser.inApp && browser.ios;

  return {
    inApp: browser.inApp,
    appURL: browser.ios ? appOpenURL(source) : null,
    campaignToken: bioLinkCampaignToken(source),
    storeURL,
    handoffURL: useAppScheme ? appStoreCampaignURL(source, 'itms-apps') : storeURL,
    redirect: !browser.inApp
  };
}

export interface AppOpenEnvironment {
  // Loads the app link without navigating the page, so a phone without Ascend shows no error.
  openInFrame(url: string): void;
  isHidden(): boolean;
  listen(type: 'visibilitychange' | 'pagehide' | 'blur', handler: () => void): void;
  setTimeout(handler: () => void, delayMs: number): number;
  clearTimeout(id: number): void;
}

// Tries the app, then runs `fallback` once if the page is still on screen after the delay. The
// page going hidden, being paged away or losing focus means the app took over, so a climber who
// comes back from Ascend is never also sent to the App Store.
export function attemptAppOpen(
  env: AppOpenEnvironment,
  appURL: string,
  fallback: () => void,
  delayMs: number = APP_FALLBACK_DELAY_MS
): void {
  let settled = false;
  const timer = env.setTimeout(() => {
    if (settled) return;
    settled = true;
    if (!env.isHidden()) fallback();
  }, delayMs);
  const cancel = () => {
    if (settled) return;
    settled = true;
    env.clearTimeout(timer);
  };

  env.listen('visibilitychange', () => {
    if (env.isHidden()) cancel();
  });
  env.listen('pagehide', cancel);
  env.listen('blur', cancel);
  env.openInFrame(appURL);
}
