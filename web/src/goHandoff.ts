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

export interface HandoffPlan {
  inApp: boolean;
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
    campaignToken: bioLinkCampaignToken(source),
    storeURL,
    handoffURL: useAppScheme ? appStoreCampaignURL(source, 'itms-apps') : storeURL,
    redirect: !browser.inApp
  };
}
