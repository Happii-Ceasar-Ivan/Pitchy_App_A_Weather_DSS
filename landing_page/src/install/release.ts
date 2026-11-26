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
      url: 'https://github.com/Happii-Ceasar-Ivan/Pitchy_App_A_Weather_DSS/releases/download/v1.0.1/pitchy-1.0.1-android.apk',
      version: '1.0.1',
      publishedAt: '2026-11-26',
      sizeBytes: 24738302,
      sha256: '15cd1b2ebaf3ff990db1eb0c53cae1b841f467b5862a9c98ddcea46d1eee7d4d',
    },
    windows: {
      url: 'https://github.com/Happii-Ceasar-Ivan/Pitchy_App_A_Weather_DSS/releases/download/v1.0.1/pitchy-1.0.1-windows-setup.exe',
      version: '1.0.1',
      publishedAt: '2026-11-26',
      sizeBytes: 11701346,
      sha256: '52faa887faf459d1085d4d9938adfd7c777efc3b640a61afad314e03ce46a33f',
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
