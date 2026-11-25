import { icons } from '../icons';
import { mountInstall } from './install-ui';

/**
 * The install sheet: the same install component as the page section, in a
 * native <dialog> (focus trap and Esc for free). Bottom sheet on phones,
 * centred panel on wider screens.
 */

let dialog: HTMLDialogElement | null = null;
let returnFocus: HTMLElement | null = null;
let heading: HTMLElement | null = null;

function build(): HTMLDialogElement {
  const d = document.createElement('dialog');
  d.className = 'sheet';
  d.setAttribute('aria-labelledby', 'sheet-title');
  d.innerHTML = `
    <div class="sheet-inner">
      <header class="sheet-head">
        <img class="sheet-logo" src="/brand/pitchy-logo.png" alt="" width="40" height="40">
        <div class="sheet-heading">
          <h2 class="sheet-title" id="sheet-title" tabindex="-1">Get Pitchy</h2>
          <p class="sheet-sub" data-sheet-sub>Your football safety &amp; weather guide, for Android and Windows.</p>
        </div>
        <button type="button" class="sheet-close" aria-label="Close">${icons.close}</button>
      </header>
      <div class="sheet-body" data-sheet-install></div>
    </div>`;
  document.body.appendChild(d);

  mountInstall(d.querySelector<HTMLElement>('[data-sheet-install]')!, 'sheet');
  heading = d.querySelector('#sheet-title');

  d.querySelector('.sheet-close')!.addEventListener('click', () => closeSheet());
  // Click on the backdrop (outside the inner panel) closes.
  d.addEventListener('click', (e) => {
    if (e.target === d) closeSheet();
  });
  d.addEventListener('close', () => {
    document.documentElement.classList.remove('sheet-open');
    returnFocus?.focus({ preventScroll: true });
    returnFocus = null;
  });
  // "How to install" link: close, then move to the steps on the page.
  d.addEventListener('click', (e) => {
    const link = (e.target as Element).closest('[data-close-sheet]');
    if (!link) return;
    e.preventDefault();
    returnFocus = null;
    d.close();
    const steps = document.getElementById('install-steps');
    if (steps) {
      steps.scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'start' });
      steps.focus({ preventScroll: true });
    }
  });
  return d;
}

export function openSheet(opts: { reason?: 'goal' | 'button' } = {}): void {
  dialog ??= build();
  if (dialog.open) return;
  const sub = dialog.querySelector<HTMLElement>('[data-sheet-sub]')!;
  const title = dialog.querySelector<HTMLElement>('#sheet-title')!;
  if (opts.reason === 'goal') {
    title.textContent = 'Goal! Now get Pitchy.';
    sub.textContent = 'Pick your device. Downloads open when the first release is ready.';
  } else {
    title.textContent = 'Get Pitchy';
    sub.textContent = 'Your football safety & weather guide, for Android and Windows.';
  }
  returnFocus = document.activeElement as HTMLElement | null;
  document.documentElement.classList.add('sheet-open');
  dialog.showModal();
  heading?.focus();
}

export function closeSheet(): void {
  dialog?.close();
}
