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
      url: 'https://github.com/Happii-Ceasar-Ivan/Pitchy_App_A_Weather_DSS/releases/download/v1.0.0/pitchy-1.0.0-android.apk',
      version: '1.0.0',
      publishedAt: '2026-11-26',
      sizeBytes: 24698974,
      sha256: '7d5c62e4d091dbf5b20d13f39efa63636e2ea45b9af6a912e9387e4cb2fbb718',
    },
    windows: {
      url: 'https://github.com/Happii-Ceasar-Ivan/Pitchy_App_A_Weather_DSS/releases/download/v1.0.0/pitchy-1.0.0-windows-setup.exe',
      version: '1.0.0',
      publishedAt: '2026-11-26',
      sizeBytes: 11702049,
      sha256: 'f3c003956f7447a225c85f8b40be87589b7e3aeb67e7405914d6357e5355a03e',
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
