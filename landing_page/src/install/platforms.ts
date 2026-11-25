import type { PlatformId } from './release';

export interface InstallStep {
  title: string;
  detail: string;
}

export interface Platform {
  id: PlatformId;
  name: string;
  device: string;
  fileType: string;
  summary: string;
  method: string;
  requirements: string;
  steps: InstallStep[];
  stepsNote: string;
}

/*
 * Copy rules: describe only what the OS really shows. Signing and minimum
 * OS versions are not decided yet, so prompts are written as "if you see"
 * and requirements say they will be listed with the release.
 */
export const platforms: Record<PlatformId, Platform> = {
  android: {
    id: 'android',
    name: 'Android',
    device: 'Phone or tablet',
    fileType: 'APK file',
    summary: 'For checking conditions pitch-side, on the phone in your pocket.',
    method: 'Install the APK file directly (not through Google Play).',
    requirements: 'An Android phone or tablet. The minimum Android version will be listed with the first release.',
    steps: [
      {
        title: 'Download the APK',
        detail: 'On your Android phone, tap Download on this page. The file saves to your Downloads.',
      },
      {
        title: 'Allow the install',
        detail:
          'Android may say your browser isn’t allowed to install apps. Tap Settings, turn on Allow from this source, then go back.',
      },
      {
        title: 'Open the file',
        detail: 'Open the Pitchy APK from the download notification or the Files app, then tap Install.',
      },
      {
        title: 'Open Pitchy',
        detail: 'When it finishes, tap Open. Pitchy is now in your apps.',
      },
    ],
    stepsNote: 'If Google Play Protect asks to scan the app, follow its prompt.',
  },
  windows: {
    id: 'windows',
    name: 'Windows',
    device: 'Desktop or laptop PC',
    fileType: 'EXE installer',
    summary: 'For planning a match ahead of the day, with room to read the detail.',
    method: 'Run the EXE installer on your PC.',
    requirements: 'A Windows PC. The supported Windows versions will be listed with the first release.',
    steps: [
      {
        title: 'Download the installer',
        detail: 'Click Download on this page to save the Pitchy EXE file.',
      },
      {
        title: 'Run it',
        detail: 'Open the file from your browser’s downloads list or your Downloads folder.',
      },
      {
        title: 'If Windows shows a warning',
        detail:
          'For new apps, Windows may show “Windows protected your PC”. If you got the file from this page, click More info, then Run anyway.',
      },
      {
        title: 'Finish and open Pitchy',
        detail: 'Follow the installer’s steps, then open Pitchy.',
      },
    ],
    stepsNote: 'Only run a Pitchy installer you downloaded from this page or Pitchy’s GitHub Releases.',
  },
};

export const platformOrder: PlatformId[] = ['android', 'windows'];

/** Best guess of the visitor's platform. `other` means neither is supported. */
export function detectPlatform(): { id: PlatformId; matched: boolean } {
  const ua = navigator.userAgent;
  if (/Android/i.test(ua)) return { id: 'android', matched: true };
  if (/Windows/i.test(ua)) return { id: 'windows', matched: true };
  return { id: 'android', matched: false };
}
