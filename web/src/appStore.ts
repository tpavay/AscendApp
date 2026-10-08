// Bare storefront-agnostic App Store URL. Apple's browser address bar shows a
// `/us/` variant that pins every visitor to the American storefront; Ascend
// ships to 147 countries, so the bare form is required - it redirects each
// visitor to their own country's store.
export const APP_STORE_URL = 'https://apps.apple.com/app/id6757202987';

// The App Store campaign link behind ascendstepper.com/go, the one URL every
// social bio points at. Apple attributes an install to the campaign token in
// `ct` and the provider token in `pt`; `mt=8` names the App Store media type.
// The path is Apple's campaign-link form of the same storefront-agnostic id.
export const APP_STORE_CAMPAIGN_PATH = 'apps.apple.com/app/apple-store/id6757202987';
export const APP_STORE_PROVIDER_TOKEN = '128011549';

// `src` query values the bio link accepts, and the campaign token each one
// reports. Anything else - including no `src` at all - is attributed to the
// direct campaign rather than to an invented token.
export const BIO_LINK_CAMPAIGNS: Readonly<Record<string, string>> = {
  instagram: 'Instagram-bio',
  tiktok: 'TikTok-bio',
  youtube: 'YouTube-shorts',
  facebook: 'Facebook-bio'
};
export const BIO_LINK_DEFAULT_CAMPAIGN = 'Link-direct';

export type AppStoreScheme = 'https' | 'itms-apps';

export function bioLinkCampaignToken(source: string | null | undefined): string {
  const key = (source ?? '').trim().toLowerCase();
  // Own keys only: `?src=__proto__` must not read Object.prototype into `ct`.
  return Object.hasOwn(BIO_LINK_CAMPAIGNS, key) ? BIO_LINK_CAMPAIGNS[key] : BIO_LINK_DEFAULT_CAMPAIGN;
}

// `https` is the product page every browser understands. `itms-apps` is the
// App Store app's own scheme: a WKWebView that refuses to hand an
// apps.apple.com navigation to the system (Instagram's does, silently) will
// still pass a custom scheme on to iOS, so the in-app hand-off uses it.
export function appStoreCampaignURL(source: string | null | undefined, scheme: AppStoreScheme = 'https'): string {
  const query = new URLSearchParams({
    pt: APP_STORE_PROVIDER_TOKEN,
    ct: bioLinkCampaignToken(source),
    mt: '8'
  });
  return `${scheme}://${APP_STORE_CAMPAIGN_PATH}?${query}`;
}
