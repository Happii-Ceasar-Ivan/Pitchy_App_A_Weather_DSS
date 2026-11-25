/** Authored SVG icons, one stroke weight (1.75) on a 24px grid. */

const stroke = (body: string) =>
  `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${body}</svg>`;

export const icons = {
  // The Android robot is reproduced from work created and shared by Google (CC BY 3.0).
  android: `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path fill="currentColor" d="M17.6 9.48 19.44 6.3a.38.38 0 0 0-.66-.38l-1.87 3.23a11.5 11.5 0 0 0-9.82 0L5.22 5.92a.38.38 0 0 0-.66.38L6.4 9.48A10.8 10.8 0 0 0 1 18h22a10.8 10.8 0 0 0-5.4-8.52ZM7 15.25A1.25 1.25 0 1 1 8.25 14 1.25 1.25 0 0 1 7 15.25Zm10 0A1.25 1.25 0 1 1 18.25 14 1.25 1.25 0 0 1 17 15.25Z"/></svg>`,
  windows: `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path fill="currentColor" d="M3 5.1 10.4 4v7.2H3Zm8.4-1.24L21 2.5v8.7h-9.6ZM3 12.8h7.4V20L3 18.9Zm8.4 0H21v8.7l-9.6-1.36Z"/></svg>`,
  download: stroke('<path d="M12 4v11"/><path d="m7 11 5 5 5-5"/><path d="M5 20h14"/>'),
  clock: stroke('<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>'),
  check: stroke('<path d="m5 12.5 4.5 4.5L19 7.5"/>'),
  close: stroke('<path d="M6 6l12 12M18 6 6 18"/>'),
  arrowRight: stroke('<path d="M5 12h14"/><path d="m13 6 6 6-6 6"/>'),
  arrowDown: stroke('<path d="M12 5v14"/><path d="m6 13 6 6 6-6"/>'),
  info: stroke('<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5"/><path d="M12 8h.01"/>'),
  shield: stroke('<path d="M12 3 5 6v5.5c0 4.3 3 7.9 7 9.5 4-1.6 7-5.2 7-9.5V6Z"/><path d="m9 12 2 2 4-4"/>'),
  source: stroke('<circle cx="6" cy="6" r="2"/><circle cx="6" cy="18" r="2"/><circle cx="18" cy="12" r="2"/><path d="M8 6h3a3 3 0 0 1 3 3v0a3 3 0 0 0 3 3h-1M8 18h3a3 3 0 0 0 3-3"/>'),
  cloudOff: stroke('<path d="m3 3 18 18"/><path d="M8.5 8.6A5 5 0 0 0 7 18h10.5M20.6 16.4A3.5 3.5 0 0 0 17 11h-.6A5.5 5.5 0 0 0 10.7 6.1"/>'),
  globeTime: stroke('<circle cx="12" cy="12" r="8.5"/><path d="M12 7v5h4"/>'),
  chat: stroke('<path d="M5 5h14v10H9l-4 4Z"/><path d="M9 10h6"/>'),
  phone: stroke('<rect x="7" y="2.75" width="10" height="18.5" rx="2.5"/><path d="M11 18.25h2"/>'),
  monitor: stroke('<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/>'),
  github: `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path fill="currentColor" d="M12 2a10 10 0 0 0-3.16 19.49c.5.09.68-.22.68-.48v-1.7c-2.78.6-3.37-1.34-3.37-1.34-.45-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.9 1.52 2.34 1.08 2.91.83.09-.65.35-1.08.63-1.33-2.22-.25-4.55-1.11-4.55-4.94 0-1.09.39-1.98 1.03-2.68-.1-.25-.45-1.27.1-2.64 0 0 .84-.27 2.75 1.02a9.6 9.6 0 0 1 5 0c1.91-1.29 2.75-1.02 2.75-1.02.55 1.37.2 2.39.1 2.64.64.7 1.03 1.59 1.03 2.68 0 3.84-2.34 4.68-4.57 4.93.36.31.68.92.68 1.85v2.74c0 .27.18.58.69.48A10 10 0 0 0 12 2Z"/></svg>`,
  sun: stroke('<circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4"/>'),
  wind: stroke('<path d="M3 8h10a3 3 0 1 0-3-3"/><path d="M3 12h15a3 3 0 1 1-3 3"/><path d="M3 16h7"/>'),
  rain: stroke('<path d="M7 15a4 4 0 0 1-.5-7.97A5.5 5.5 0 0 1 17 7a3.5 3.5 0 0 1 0 8Z"/><path d="m8 18.5-1 2M12 18.5l-1 2M16 18.5l-1 2"/>'),
  soundOn: stroke('<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4Z"/><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11"/>'),
  soundOff: stroke('<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4Z"/><path d="m16 9.5 5 5M21 9.5l-5 5"/>'),
  ball: stroke('<circle cx="12" cy="12" r="8.5"/><path d="m12 8 3.3 2.4-1.3 3.9h-4l-1.3-3.9Z"/><path d="M12 8V3.5M15.3 10.4l4.2-1.4M14 14.3l2.6 3.6M10 14.3l-2.6 3.6M8.7 10.4 4.5 9"/>'),
} as const;

export type IconName = keyof typeof icons;
