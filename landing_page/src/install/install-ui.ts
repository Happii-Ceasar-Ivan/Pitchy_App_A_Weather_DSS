import { icons } from '../icons';
import { detectPlatform, platformOrder, platforms } from './platforms';
import { formatSize, isPublished, release, type PlatformId } from './release';

/* ---------- shared selection (page section and sheet stay in sync) ---------- */

const detected = detectPlatform();
let selected: PlatformId = detected.id;
const listeners = new Set<(id: PlatformId) => void>();

export function getSelected(): PlatformId {
  return selected;
}

export function setSelected(id: PlatformId): void {
  if (id === selected) return;
  selected = id;
  listeners.forEach((fn) => fn(id));
}

/* ---------- markup ---------- */

let uid = 0;
const esc = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

function pickerHtml(name: string): string {
  const opts = platformOrder
    .map((id) => {
      const p = platforms[id];
      const yours = detected.matched && detected.id === id;
      return `
      <label class="pick" data-platform="${id}">
        <input class="pick-input" type="radio" name="${name}" value="${id}" ${id === selected ? 'checked' : ''}>
        <span class="pick-icon">${icons[id]}</span>
        <span class="pick-text">
          <span class="pick-name">${p.name}</span>
          <span class="pick-meta">${p.device} · ${p.fileType}</span>
        </span>
        ${yours ? '<span class="pick-yours">Your device</span>' : ''}
        <span class="pick-check">${icons.check}</span>
      </label>`;
    })
    .join('');
  return `
    <fieldset class="picker">
      <legend class="picker-legend">Choose your device</legend>
      <div class="picker-options">${opts}</div>
    </fieldset>`;
}

function downloadHtml(id: PlatformId, noteId: string): string {
  const p = platforms[id];
  const asset = release.assets[id];

  if (isPublished(asset)) {
    const date = new Date(asset.publishedAt).toLocaleDateString('en-PH', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
    });
    return `
      <a class="btn btn-primary btn-download" href="${esc(asset.url)}" download rel="noopener">
        ${icons.download}<span>Download for ${p.name}</span>
      </a>
      <p class="dl-note" id="${noteId}">Version ${esc(asset.version)} · ${formatSize(asset.sizeBytes)} · Released ${date}</p>
      ${
        asset.sha256
          ? `<p class="dl-hash"><span>SHA-256</span><code>${esc(asset.sha256)}</code></p>`
          : ''
      }`;
  }

  return `
    <button type="button" class="btn btn-primary btn-download" aria-disabled="true" aria-describedby="${noteId}">
      ${icons.clock}<span>Download coming soon</span>
    </button>
    <p class="dl-note" id="${noteId}" aria-live="polite">Pitchy is still in development. The ${p.name} ${p.fileType} will be published on GitHub Releases when it’s ready.</p>`;
}

function panelHtml(id: PlatformId, variant: 'page' | 'sheet'): string {
  const p = platforms[id];
  const asset = release.assets[id];
  const live = isPublished(asset);
  const noteId = `dl-note-${++uid}`;

  const status = live
    ? `<span class="chip chip-live">${icons.check}Available</span>`
    : `<span class="chip chip-soon">${icons.clock}Coming soon</span>`;

  const facts = `
    <dl class="facts">
      <div class="fact"><dt>File</dt><dd>${p.fileType}</dd></div>
      <div class="fact"><dt>How it installs</dt><dd>${p.method}</dd></div>
      <div class="fact"><dt>You’ll need</dt><dd>${p.requirements}</dd></div>
      <div class="fact"><dt>Version</dt><dd>${live ? esc(asset!.version) : 'Not released yet'}</dd></div>
    </dl>`;

  const download = `
    <div class="dl" data-variant="${variant}">
      <div class="dl-head">
        <h3 class="dl-title">Pitchy for ${p.name}</h3>
        ${status}
      </div>
      <p class="dl-summary">${p.summary}</p>
      ${
        variant === 'sheet'
          ? `<div class="dl-action">${downloadHtml(id, noteId)}</div>${facts}`
          : `${facts}<div class="dl-action">${downloadHtml(id, noteId)}</div>`
      }
    </div>`;

  if (variant === 'sheet') {
    return `${download}
      <a class="sheet-steps-link" href="#install-steps" data-close-sheet>
        How to install on ${p.name}${icons.arrowRight}
      </a>`;
  }

  const steps = p.steps
    .map(
      (s, i) => `
      <li class="step">
        <span class="step-num" aria-hidden="true">${i + 1}</span>
        <div class="step-body">
          <p class="step-title">${s.title}</p>
          <p class="step-detail">${s.detail}</p>
        </div>
      </li>`,
    )
    .join('');

  return `${download}
    <div class="steps" id="install-steps" tabindex="-1">
      <h3 class="steps-title">How to install on ${p.name}</h3>
      <ol class="steps-list">${steps}</ol>
      <p class="steps-note">${icons.info}<span>${p.stepsNote}</span></p>
    </div>`;
}

/* ---------- mount ---------- */

export function mountInstall(root: HTMLElement, variant: 'page' | 'sheet'): void {
  const name = `platform-${variant}`;
  root.innerHTML = `
    ${
      detected.matched
        ? ''
        : `<p class="device-note">${icons.info}<span>Pitchy is made for Android phones and Windows PCs only. Pick the one you’ll install it on.</span></p>`
    }
    ${pickerHtml(name)}
    <div class="install-panel">${panelHtml(selected, variant)}</div>`;

  const panel = root.querySelector<HTMLElement>('.install-panel')!;

  const render = (id: PlatformId) => {
    root.querySelectorAll<HTMLInputElement>('.pick-input').forEach((r) => (r.checked = r.value === id));
    panel.innerHTML = panelHtml(id, variant);
  };
  listeners.add(render);

  root.addEventListener('change', (e) => {
    const t = e.target as HTMLInputElement;
    if (t.matches('.pick-input')) setSelected(t.value as PlatformId);
  });

  // A download that isn't published can never start: swallow the click and point at the note.
  root.addEventListener('click', (e) => {
    const btn = (e.target as Element).closest<HTMLElement>('.btn-download[aria-disabled="true"]');
    if (!btn) return;
    e.preventDefault();
    const note = document.getElementById(btn.getAttribute('aria-describedby') || '');
    if (note) {
      note.classList.remove('is-flagged');
      void note.offsetWidth;
      note.classList.add('is-flagged');
      // Re-set the text so the live region announces it again.
      const text = note.textContent ?? '';
      note.textContent = '';
      window.setTimeout(() => (note.textContent = text), 60);
    }
  });
}
