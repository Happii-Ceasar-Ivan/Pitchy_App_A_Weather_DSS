import { icons, type IconName } from './icons';
import { mountInstall } from './install/install-ui';
import { openSheet } from './install/sheet';
import { createPitch } from './scene/pitch';
import type { Weather } from './scene/audio';

const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');

/* ---------- scroll reveals: one observer, only when motion is welcome ---------- */
if (matchMedia('(prefers-reduced-motion: no-preference)').matches && 'IntersectionObserver' in window) {
  document.documentElement.classList.add('motion');
  document.querySelectorAll<HTMLElement>('.faq-list details').forEach((d, i) => d.style.setProperty('--i', String(i)));
  const reveals = new IntersectionObserver(
    (entries, obs) => {
      for (const en of entries) {
        // also settle anything already scrolled past (anchor jumps), so nothing stays hidden
        if (!en.isIntersecting && en.boundingClientRect.top >= 0) continue;
        en.target.classList.add('is-in');
        obs.unobserve(en.target);
      }
    },
    { rootMargin: '0px 0px -15% 0px' },
  );
  document.querySelectorAll('[data-reveal], [data-sweep], [data-line]').forEach((el) => reveals.observe(el));
}

/* ---------- inline icons ---------- */
function paintIcons(root: ParentNode = document): void {
  root.querySelectorAll<HTMLElement>('[data-icon]').forEach((el) => {
    const name = el.dataset.icon as IconName;
    if (icons[name]) el.outerHTML = icons[name];
  });
}
paintIcons();

/* ---------- install section ---------- */
mountInstall(document.querySelector<HTMLElement>('[data-install-root]')!, 'page');

/* ---------- header: solid once the hero scrolls away ---------- */
const header = document.querySelector<HTMLElement>('[data-header]')!;
const hero = document.querySelector<HTMLElement>('[data-hero]')!;
const syncHeader = () => header.classList.toggle('is-solid', scrollY > 12);
addEventListener('scroll', syncHeader, { passive: true });
syncHeader();

/* ---------- hero pitch ---------- */
const canvas = document.querySelector<HTMLCanvasElement>('[data-pitch]')!;
const ball = document.querySelector<HTMLButtonElement>('[data-ball]')!;
const ui = document.querySelector<HTMLElement>('[data-pitch-ui]')!;
const score = document.querySelector<HTMLOutputElement>('[data-score]')!;
const hint = document.querySelector<HTMLElement>('[data-hint]')!;
const soundBtn = document.querySelector<HTMLButtonElement>('[data-sound]')!;
const copy = document.querySelector<HTMLElement>('[data-hero-copy]')!;
let sheetShown = false;

if (canvas.getContext('2d')) {
  hero.classList.add('has-pitch');
  const pitch = createPitch({
    canvas,
    handle: ball,
    reducedMotion: reduceMotion.matches,
    textBottom: () => {
      const h = hero.getBoundingClientRect(), c = copy.getBoundingClientRect();
      return c.bottom - h.top;
    },
    onLayout: ({ centerX, ballY, wide }) => {
      ui.style.setProperty('--pitch-cx', `${centerX}px`);
      ui.style.setProperty('--ball-y', `${ballY}px`);
      ui.classList.toggle('is-wide', wide);
    },
    onKick: () => hint.classList.add('is-hidden'),
    onGoal: (n) => {
      score.value = String(n);
      score.textContent = String(n);
      score.classList.remove('is-bumped');
      void score.offsetWidth;
      score.classList.add('is-bumped');
      hero.classList.add('is-lit');
    },
    onLightsUp: () => {
      if (sheetShown) return;
      sheetShown = true;
      window.setTimeout(() => openSheet({ reason: 'goal' }), reduceMotion.matches ? 200 : 900);
    },
  });

  ui.addEventListener('change', (e) => {
    const t = e.target as HTMLInputElement;
    if (t.name === 'pitch-weather') pitch.setWeather(t.value as Weather);
  });

  soundBtn.addEventListener('click', () => {
    const on = soundBtn.getAttribute('aria-pressed') !== 'true';
    soundBtn.setAttribute('aria-pressed', String(on));
    soundBtn.innerHTML = `<span class="visually-hidden">Sound</span>${on ? icons.soundOn : icons.soundOff}`;
    pitch.setSound(on);
  });
} else {
  ui.hidden = true;
  ball.hidden = true;
}

/* ---------- feature story: the sticky phone shows the step being read ---------- */
const stickyShots = document.querySelectorAll<HTMLImageElement>('.device-sticky img');
const steps = document.querySelectorAll<HTMLElement>('.story-step');
if (stickyShots.length) {
  // On desktop the sticky phone swaps images while scrolling: load them all up front so none shows empty.
  if (matchMedia('(min-width: 900px)').matches) stickyShots.forEach((img) => (img.loading = 'eager'));
  const io = new IntersectionObserver(
    (entries) => {
      for (const en of entries) {
        if (!en.isIntersecting) continue;
        const i = Number((en.target as HTMLElement).dataset.shot);
        stickyShots.forEach((img, k) => img.classList.toggle('is-active', k === i));
        steps.forEach((s, k) => s.classList.toggle('is-current', k === i));
      }
    },
    { rootMargin: '-45% 0px -45% 0px' },
  );
  steps.forEach((s) => io.observe(s));
}

/* ---------- footer year ---------- */
const year = document.querySelector('[data-year]');
if (year) year.textContent = String(new Date().getFullYear());
