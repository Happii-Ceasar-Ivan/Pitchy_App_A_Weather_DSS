import { defineConfig, type Plugin } from 'vite';
import { release } from './src/install/release';

/**
 * Writes the released version into index.html at build (and dev) time, so
 * src/install/release.ts is the only place to change for a new release.
 * Replaces every `%PITCHY_VERSION%` in the HTML. The value comes from this
 * repo only and must be a plain x.y.z version, so it can't inject markup.
 */
function releaseVersion(): Plugin {
  const { android, windows } = release.assets;
  if (!android || !windows) {
    throw new Error('release.ts: fill both the Android and Windows assets before building.');
  }
  if (android.version !== windows.version) {
    throw new Error(
      `release.ts: Android (${android.version}) and Windows (${windows.version}) versions differ; the page says one version for both.`,
    );
  }
  const version = android.version;
  if (!/^\d+\.\d+\.\d+$/.test(version)) {
    throw new Error(`release.ts: "${version}" is not a plain x.y.z version.`);
  }
  return {
    name: 'pitchy-release-version',
    transformIndexHtml: (html) => html.replaceAll('%PITCHY_VERSION%', version),
  };
}

export default defineConfig({
  plugins: [releaseVersion()],
});
