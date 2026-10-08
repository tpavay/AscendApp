import { appStoreCampaignURL, bioLinkCampaignToken } from './appStore.ts';

// Which in-app browser a visitor arrived through, read from the user agent.
// `webview` is any other iOS WKWebView: on iOS every real browser (Safari,
// Chrome, Firefox, Edge, DuckDuckGo, Brave) carries a `Safari/` token, and an
// embedded WKWebView is the one thing that does not.
export type InAppHost = 'instagram' | 'facebook' | 'tiktok' | 'youtube' | 'webview';

export interface BrowserClassification {
  inApp: boolean;
  host: InAppHost | null;
  ios: boolean;
}

const NAMED_HOSTS: ReadonlyArray<[InAppHost, RegExp]> = [
  ['instagram', /\bInstagram\b/i],
  ['facebook', /\bFB(AN|AV|_IAB|IOS)\b|\bMessengerForiOS\b|\bFBAN\/Messenger/i],
  ['tiktok', /\bmusical_ly\b|\bBytedanceWebview\b|\bTikTok\b|\bBytedance\b/i],
  ['youtube', /\bYouTube\b|com\.google\.ios\.youtube/i]
];

export function classifyBrowser(userAgent: string): BrowserClassification {
  const ua = userAgent ?? '';
  const ios = /\b(iPhone|iPad|iPod)\b/.test(ua);

  for (const [host, pattern] of NAMED_HOSTS) {
    if (pattern.test(ua)) {
      return { inApp: true, host, ios: ios || /\bMacintosh\b/.test(ua) };
    }
  }

  // An iOS WebKit user agent with no `Safari/` token is an embedded WKWebView.
  // `wv` is Android's WebView marker; Android needs no App Store hand-off, but
  // it still gets the tap-first page rather than a redirect that may be
  // swallowed.
  const isWebKit = /\bAppleWebKit\b/.test(ua);
  const hasSafariToken = /\bSafari\/\d/.test(ua);
  if (ios && isWebKit && !hasSafariToken) {
    return { inApp: true, host: 'webview', ios };
  }
  if (/\bAndroid\b/.test(ua) && /;\s*wv\)/.test(ua)) {
    return { inApp: true, host: 'webview', ios: false };
  }

  return { inApp: false, host: null, ios };
}

export interface HandoffPlan {
  inApp: boolean;
  host: InAppHost | null;
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
    host: browser.host,
    campaignToken: bioLinkCampaignToken(source),
    storeURL,
    handoffURL: useAppScheme ? appStoreCampaignURL(source, 'itms-apps') : storeURL,
    redirect: !browser.inApp
  };
}
