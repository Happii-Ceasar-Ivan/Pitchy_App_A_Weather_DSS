/**
 * Release information for the download buttons.
 *
 * Everything is `null` while Pitchy is in development: the buttons render as
 * "Download coming soon" and cannot start a download.
 *
 * To publish a release, fill in the asset for each platform with the values
 * from its GitHub Releases page. Nothing else on the site needs to change.
 * Never put a guessed URL, version or size here.
 */

export type PlatformId = 'android' | 'windows';

export interface ReleaseAsset {
  /** Direct GitHub Releases asset URL (https://github.com/<owner>/<repo>/releases/download/...). */
  url: string;
  /** Version shown on the button, e.g. "1.0.0". */
  version: string;
  /** ISO date the release was published, e.g. "2027-01-15". */
  publishedAt: string;
  /** File size in bytes, from the release asset. */
  sizeBytes: number;
  /** SHA-256 checksum of the file, if the release publishes one. */
  sha256?: string;
}

export interface ReleaseInfo {
  /** GitHub Releases page for all versions and notes. */
  releasesPageUrl: string | null;
  assets: Record<PlatformId, ReleaseAsset | null>;
}

export const release: ReleaseInfo = {
  releasesPageUrl: 'https://github.com/Happii-Ceasar-Ivan/Pitchy_App_A_Weather_DSS/releases',
  assets: {
    android: {
      url: 'https://github.com/Happii-Ceasar-Ivan/Pitchy_App_A_Weather_DSS/releases/download/v1.1.0/pitchy-1.1.0-android.apk',
      version: '1.1.0',
      publishedAt: '2026-11-26',
      sizeBytes: 24835698,
      sha256: '5f451d6f7c556913ff33a8101a7f4d65f91cf6aea49cb004d4b91ed26d165cc2',
    },
    windows: {
      url: 'https://github.com/Happii-Ceasar-Ivan/Pitchy_App_A_Weather_DSS/releases/download/v1.1.0/pitchy-1.1.0-windows-setup.exe',
      version: '1.1.0',
      publishedAt: '2026-11-26',
      sizeBytes: 11731928,
      sha256: '8feb3026ec79cd57ab9d0207d50589e0233097fcf58f2df1adf70f4262c67c8f',
    },
  },
};

/** True when the asset is a real, published https link. */
export function isPublished(asset: ReleaseAsset | null): asset is ReleaseAsset {
  return !!asset && /^https:\/\//.test(asset.url);
}

export function formatSize(bytes: number): string {
  const mb = bytes / (1024 * 1024);
  return mb >= 10 ? `${Math.round(mb)} MB` : `${mb.toFixed(1)} MB`;
}
