import { Ball } from './ball';
import { MatchAudio, type Weather } from './audio';

/**
 * The hero's night pitch. Shoot the ball into the goal and the floodlights
 * come on. Drag or flick the ball, tap the pitch to shoot there, or focus the
 * ball and press Enter (single-pointer and keyboard alternatives to dragging).
 *
 * The weather here is an illustration only, never live data.
 */

export interface PitchOptions {
  canvas: HTMLCanvasElement;
  handle: HTMLButtonElement;
  /** Lowest y (px, in hero space) that the hero text reaches on narrow layouts. */
  textBottom: () => number;
  reducedMotion: boolean;
  onKick?: () => void;
  onGoal?: (goals: number) => void;
  /** Fires once, when the floodlights have finished coming on after the first goal. */
  onLightsUp?: () => void;
  /** Reports where the pitch sits, so HTML overlays can line up with it. */
  onLayout?: (g: { centerX: number; regionX: number; regionW: number; ballY: number; wide: boolean }) => void;
}

export interface PitchHandle {
  setWeather(w: Weather): void;
  setSound(on: boolean): void;
  shoot(): void;
}

type State = 'idle' | 'dragging' | 'returning' | 'scored';

interface Geo {
  W: number; H: number; dpr: number; wide: boolean;
  cx: number; pt: number; pb: number; tw: number; bw: number;
  gw: number; gh: number; goalY: number; startY: number; R0: number;
  cy: number; tc: number; rx: number; regionX: number; regionW: number;
}

const BANK_STARTS = [0, 0.45, 0.9, 1.4];
const FLICKER_T = [0, 0.07, 0.13, 0.25, 0.33, 0.5, 0.62, 1, 2.2];
const FLICKER_V = [0, 0.9, 0.05, 0.75, 0, 0.65, 0.15, 0.85, 1];

export function createPitch(o: PitchOptions): PitchHandle {
  const { canvas: cv, handle, reducedMotion: reduce } = o;
  const ctx = cv.getContext('2d')!;
  const lit = document.createElement('canvas');
  const lx = lit.getContext('2d')!;
  const ball = new Ball();
  const audio = new MatchAudio();

  let G!: Geo;
  const b = { x: 0, y: 0, vx: 0, vy: 0 };
  let state: State = 'idle';
  let weather: Weather = 'clear';
  let goals = 0, tFirstGoal = 0, tGoal = 0, stillT = 0, prevY = 0, impactX = 0;
  let lastT = 0, tNow = 0, lastBX = 0, lastBY = 0, lightsAnnounced = false;
  let ret: { x: number; y: number; t0: number; d: number } | null = null;
  let samples: { x: number; y: number; t: number }[] = [];
  let grab: [number, number] = [0, 0];
  let downAt: { x: number; y: number; t: number } | null = null;
  const sparks: { x: number; y: number; t: number }[] = [];
  const particles: { x: number; y: number; v: number }[] = [];
  let grain: CanvasPattern | null = null;

  /* ---------- geometry ---------- */

  const hw = (t: number) => G.tw + (G.bw - G.tw) * t;
  const PY = (t: number) => G.pt + (G.pb - G.pt) * t;
  const PX = (x: number, t: number) => G.cx + x * hw(t);
  const scaleAt = (y: number) => 0.42 + 0.58 * Math.min(1.1, Math.max(0, (y - G.goalY) / (G.startY - G.goalY)));
  const radius = () => G.R0 * scaleAt(b.y);

  function layout(): void {
    const rect = cv.getBoundingClientRect();
    const W = Math.max(1, rect.width), H = Math.max(1, rect.height);
    const dpr = Math.min(W < 700 ? 1.5 : 2, devicePixelRatio || 1);
    cv.width = Math.round(W * dpr);
    cv.height = Math.round(H * dpr);
    const wide = W >= 960;
    const regionX = wide ? W * 0.36 : 0;
    const regionW = W - regionX;
    const cx = regionX + regionW / 2;
    const gw = Math.max(130, Math.min(regionW * 0.44, H * 0.38, 440));
    // On narrow layouts the goal (which stands above the goal line) must clear the hero text.
    const pt = wide ? H * 0.33 : Math.min(H * 0.66, Math.max(H * 0.47, o.textBottom() + 28 + gw * 0.34));
    // Keep the ball clear of the hint and controls docked at the bottom.
    const reserve = 156 + Math.max(22, Math.min(Math.min(regionW, H) * 0.072, 54));
    const startY = Math.max(pt + 150, Math.min(H * 0.84, H - reserve));
    const U = Math.min(regionW, (H - pt) * (wide ? 1.9 : 2.4));
    const cy = pt + (H * 1.05 - pt) * 0.4;
    const tc = (cy - pt) / (H * 1.05 - pt);
    G = {
      W, H, dpr, wide, cx, pt, pb: H * 1.05, tw: 0.4 * U, bw: 0.95 * U,
      gw, gh: gw * 0.34, goalY: pt + 0.012 * H, startY,
      R0: Math.max(22, Math.min(Math.min(regionW, H) * 0.072, 54)),
      cy, tc, rx: 0, regionX, regionW,
    };
    G.rx = hw(tc) * 0.34;
    if (state === 'scored') {
      b.x = G.cx;
      b.y = G.goalY - G.gh * 0.2;
    } else if (state !== 'dragging') {
      state = 'idle';
      b.x = G.cx;
      b.y = G.startY;
      b.vx = b.vy = 0;
    }
    lastBX = b.x;
    lastBY = b.y;
    prevY = b.y;
    buildStadium();
    placeHandle();
    o.onLayout?.({ centerX: cx, regionX, regionW, ballY: startY, wide });
  }

  /* ---------- static, fully lit stadium (drawn once per layout) ---------- */

  function buildStadium(): void {
    const { W, H, dpr, pt, cx, cy, rx, tc } = G;
    lit.width = W * dpr;
    lit.height = H * dpr;
    const g = lx;
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    let s = 7;
    const rnd = () => {
      s |= 0; s = (s + 0x6d2b79f5) | 0;
      let t = Math.imul(s ^ (s >>> 15), 1 | s);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };

    g.fillStyle = '#0d1624';
    g.fillRect(0, 0, W, H);

    // stands: crowd as small tiles in muted kit colours
    const boardH = Math.max(14, H * 0.034);
    const standBottom = pt - boardH;
    const step = Math.max(4, H * 0.0085);
    const crowd = ['#33404f', '#4e3636', '#2c4058', '#5f6266', '#6f6450', '#35473f', '#7d4a4a', '#8c8f94', '#9a8440', '#2f5f57'];
    for (let y = 2, r = 0; y < standBottom; y += step, r++) {
      const dim = 0.5 + 0.5 * (y / standBottom);
      for (let x = (r % 2) * step * 0.6; x < W; x += step * 1.2) {
        g.globalAlpha = (0.5 + rnd() * 0.5) * dim;
        g.fillStyle = crowd[(rnd() * crowd.length) | 0];
        g.fillRect(x, y, step * 0.8, step * 0.8);
      }
      if (r % 9 === 8) {
        g.globalAlpha = 0.55;
        g.fillStyle = '#070d16';
        g.fillRect(0, y + step * 0.85, W, step * 0.35);
      }
    }
    g.globalAlpha = 1;
    let gr = g.createLinearGradient(0, 0, 0, standBottom);
    gr.addColorStop(0, 'rgba(5,9,16,.9)');
    gr.addColorStop(1, 'rgba(5,9,16,0)');
    g.fillStyle = gr;
    g.fillRect(0, 0, W, standBottom);
    for (let x = W / 16; x < W; x += W / 8) {
      g.fillStyle = 'rgba(6,10,16,.5)';
      g.fillRect(x, 0, Math.max(3, W * 0.006), standBottom);
    }

    // advertising boards carrying the wordmark
    const pw = Math.max(110, W / 9);
    g.font = `800 ${Math.round(boardH * 0.62)}px "Big Shoulders Display", sans-serif`;
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    for (let x = 0, i = 0; x < W; x += pw, i++) {
      g.fillStyle = i % 2 ? '#0f2540' : '#0e3b2e';
      g.fillRect(x, standBottom, pw, boardH);
      g.fillStyle = i % 2 ? 'rgba(242,245,249,.82)' : 'rgba(82,199,180,.9)';
      g.fillText('PITCHY', x + pw / 2, standBottom + boardH * 0.54);
    }
    g.fillStyle = 'rgba(0,0,0,.35)';
    g.fillRect(0, pt - boardH * 0.12, W, boardH * 0.12);

    // grass: mown stripes in perspective
    g.fillStyle = '#163a22';
    g.fillRect(0, pt, W, H - pt);
    const N = 16;
    for (let i = 0; i < N; i++) {
      const t0 = Math.pow(i / N, 1.7), t1 = Math.pow((i + 1) / N, 1.7);
      g.fillStyle = i % 2 ? '#2a6230' : '#327038';
      g.beginPath();
      g.moveTo(PX(-1, t0), PY(t0));
      g.lineTo(PX(1, t0), PY(t0));
      g.lineTo(PX(1, t1), PY(t1));
      g.lineTo(PX(-1, t1), PY(t1));
      g.closePath();
      g.fill();
    }
    gr = g.createLinearGradient(0, pt, 0, H);
    gr.addColorStop(0, 'rgba(0,0,0,.3)');
    gr.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = gr;
    g.fillRect(0, pt, W, H - pt);
    const blades = Math.min(12000, (W * H) / 80);
    for (let i = 0; i < blades; i++) {
      const t = Math.pow(rnd(), 0.8), y = pt + (H - pt) * t, x = rnd() * W;
      g.globalAlpha = 0.05 + rnd() * 0.07;
      g.fillStyle = rnd() < 0.5 ? '#0c2410' : '#7fae6a';
      g.fillRect(x, y, Math.max(0.7, t * 1.2), 1 + t * 5);
    }
    g.globalAlpha = 1;

    // floodlight pools on the grass
    g.globalCompositeOperation = 'lighter';
    [[cx, H * 0.5, 0.55, 0.15], [cx, pt + (H - pt) * 0.12, 0.35, 0.08]].forEach(([x, y, k, a]) => {
      const R = Math.max(W, H) * k;
      const h = g.createRadialGradient(x, y, 0, x, y, R);
      h.addColorStop(0, `rgba(190,230,170,${a})`);
      h.addColorStop(1, 'rgba(190,230,170,0)');
      g.fillStyle = h;
      g.fillRect(0, pt, W, H - pt);
    });
    g.globalCompositeOperation = 'source-over';
    gr = g.createLinearGradient(0, pt, 0, pt + H * 0.09);
    gr.addColorStop(0, 'rgba(0,0,0,.5)');
    gr.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = gr;
    g.fillRect(0, pt, W, H * 0.09);

    // pitch markings
    g.strokeStyle = 'rgba(232,238,226,.74)';
    g.lineWidth = Math.max(1.5, W / 340);
    g.lineJoin = 'round';
    const poly = (pts: [number, number][]) => {
      g.beginPath();
      pts.forEach(([x, t], i) => (i ? g.lineTo(PX(x, t), PY(t)) : g.moveTo(PX(x, t), PY(t))));
      const lw = g.lineWidth;
      g.globalAlpha = 0.18;
      g.lineWidth = lw * 3;
      g.stroke();
      g.globalAlpha = 1;
      g.lineWidth = lw;
      g.stroke();
    };
    const tb = tc * 0.55, t6 = tc * 0.22, ts = tc * 0.38;
    poly([[-1, 1], [-1, 0], [1, 0], [1, 1]]);
    poly([[-0.62, 0], [-0.62, tb], [0.62, tb], [0.62, 0]]);
    poly([[-0.3, 0], [-0.3, t6], [0.3, t6], [0.3, 0]]);
    poly([[-1, tc], [1, tc]]);
    g.beginPath();
    g.ellipse(cx, cy, rx, rx * 0.38, 0, 0, Math.PI * 2);
    g.stroke();
    g.fillStyle = 'rgba(255,255,255,.85)';
    g.beginPath();
    g.ellipse(PX(0, ts), PY(ts), W / 190, (W / 190) * 0.4, 0, 0, Math.PI * 2);
    g.fill();
  }

  /* ---------- floodlights ---------- */

  function flicker(u: number): number {
    if (u <= 0) return 0;
    if (u >= 2.2) return 1;
    if (reduce) {
      const k = u / 2.2;
      return k * k * (3 - 2 * k);
    }
    let i = 1;
    while (FLICKER_T[i] < u) i++;
    const k = (u - FLICKER_T[i - 1]) / (FLICKER_T[i] - FLICKER_T[i - 1]);
    return FLICKER_V[i - 1] + (FLICKER_V[i] - FLICKER_V[i - 1]) * k;
  }

  function bankXY(i: number): [number, number, number, number] {
    const xs = [0.08, 0.92, 0.32, 0.68], ys = [0.05, 0.05, 0.022, 0.022];
    const w = Math.max(28, G.regionW * 0.05), h = w * 0.55;
    // Sit below the fixed header so the lights never sit behind its links.
    const top = 68 + h / 2 + 14;
    return [G.regionX + xs[i] * G.regionW, Math.min(G.pt * 0.6, Math.max(ys[i] * G.H + top, top)), w, h];
  }

  function drawBank(i: number, v: number): void {
    const [x, y, w, h] = bankXY(i);
    ctx.fillStyle = `rgba(12,16,22,${0.6 + 0.4 * Math.min(1, v * 4)})`;
    ctx.fillRect(x - w / 2 - 3, y - h / 2 - 3, w + 6, h + 6);
    ctx.fillStyle = `rgba(255,248,230,${0.06 + 0.94 * v})`;
    for (let r = 0; r < 2; r++)
      for (let c = 0; c < 3; c++) {
        ctx.beginPath();
        ctx.arc(x - w / 3 + (c * w) / 3, y - h / 4 + (r * h) / 2, h / 5, 0, Math.PI * 2);
        ctx.fill();
      }
    if (v <= 0.01) return;
    ctx.globalCompositeOperation = 'lighter';
    const gr = ctx.createRadialGradient(x, y, 0, x, y, w * 1.7);
    gr.addColorStop(0, `rgba(255,244,214,${0.6 * v})`);
    gr.addColorStop(1, 'rgba(255,244,214,0)');
    ctx.fillStyle = gr;
    ctx.fillRect(x - w * 2, y - w * 2, w * 4, w * 4);
    ctx.globalCompositeOperation = 'source-over';
  }

  /* ---------- goal ---------- */

  function ripple(x: number): number {
    if (!goals || reduce) return 0;
    const k = (tNow - tGoal) / 1000;
    return -G.gh * 0.16 * Math.exp(-((x - impactX) ** 2) / (G.gw * G.gw * 0.08)) * Math.exp(-k * 2.2) * Math.cos(k * 16);
  }

  function net(xa: number, ya: number, xb: number, yb: number, cols: number, rows: number): void {
    ctx.beginPath();
    for (let i = 0; i <= cols; i++) {
      const x = xa + ((xb - xa) * i) / cols;
      for (let j = 0; j <= 6; j++) {
        const y = ya + ((yb - ya) * j) / 6 + ripple(x);
        j ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
      }
    }
    for (let j = 0; j <= rows; j++)
      for (let i = 0; i <= cols; i++) {
        const x = xa + ((xb - xa) * i) / cols, y = ya + ((yb - ya) * j) / rows + ripple(x);
        i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
      }
    ctx.stroke();
  }

  function goalBack(L: number): void {
    const { cx, gw, gh, goalY } = G;
    const x0 = cx - gw / 2, x1 = cx + gw / 2, yt = goalY - gh, ins = gw * 0.07;
    const bx0 = x0 + ins, bx1 = x1 - ins, byb = goalY - gh * 0.2, byt = goalY - gh * 0.92;
    ctx.lineWidth = 1;
    ctx.strokeStyle = `rgba(255,255,255,${0.08 + 0.36 * L})`;
    ctx.beginPath();
    [[x0, yt, bx0, byt], [x1, yt, bx1, byt], [x0, goalY, bx0, byb], [x1, goalY, bx1, byb]].forEach(([a, b2, c, d]) => {
      ctx.moveTo(a, b2);
      ctx.lineTo(c, d);
    });
    for (let i = 0; i <= 12; i++) {
      ctx.moveTo(x0 + (gw * i) / 12, yt);
      ctx.lineTo(bx0 + ((bx1 - bx0) * i) / 12, byt);
    }
    ctx.stroke();
    net(bx0, byt, bx1, byb, 12, 5);
  }

  function goalFront(L: number): void {
    const { cx, gw, gh, goalY } = G;
    const x0 = cx - gw / 2, x1 = cx + gw / 2, yt = goalY - gh;
    ctx.lineWidth = 1;
    ctx.strokeStyle = `rgba(255,255,255,${0.06 + 0.26 * L})`;
    net(x0, yt, x1, goalY, 14, 6);
    ctx.strokeStyle = `rgba(255,255,255,${0.42 + 0.58 * L})`;
    ctx.lineWidth = Math.max(2, gw * 0.016);
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.beginPath();
    ctx.moveTo(x0, goalY);
    ctx.lineTo(x0, yt);
    ctx.lineTo(x1, yt);
    ctx.lineTo(x1, goalY);
    ctx.stroke();
  }

  /* ---------- physics ---------- */

  const gust = (t: number) => Math.max(-1, Math.min(1, Math.sin(t * 0.0004) * 0.75 + Math.sin(t * 0.0013 + 1) * 0.35));
  const vmax = () => (G.startY - G.goalY) * 0.022;

  function startReturn(now: number, delay = 350, d = 800): void {
    state = 'returning';
    ret = { x: b.x, y: b.y, t0: now + delay, d };
    b.vx = b.vy = 0;
  }

  function score(now: number): void {
    state = 'scored';
    if (!goals) tFirstGoal = now;
    tGoal = now;
    goals++;
    impactX = b.x;
    b.vx *= 0.4;
    b.vy = Math.max(-9, Math.min(-4, b.vy * 0.7));
    audio.net();
    if (goals === 1) {
      audio.roar(0.6, 5.5);
      BANK_STARTS.forEach((s) => setTimeout(() => audio.clunk(), 700 + s * 1000));
      setTimeout(() => audio.ambient(), 3600);
    } else audio.roar(0.3, 2.4);
    o.onGoal?.(goals);
  }

  function update(f: number, dt: number, now: number): void {
    const r = radius();
    if (state === 'returning' && ret) {
      const k = Math.max(0, Math.min(1, (now - ret.t0) / ret.d));
      const e = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
      b.x = ret.x + (G.cx - ret.x) * e;
      b.y = ret.y + (G.startY - ret.y) * e;
      if (k >= 1) {
        state = 'idle';
        stillT = 0;
        prevY = b.y;
      }
      return;
    }
    if (state === 'idle') {
      const spd = Math.hypot(b.vx, b.vy);
      if (spd > 0.25) {
        if (weather === 'wind') b.vx += gust(now) * Math.min(G.W, G.H) * 0.0001 * f;
        else if (weather === 'rain') b.vx += (Math.random() - 0.5) * 0.05 * f;
      }
      b.x += b.vx * f;
      b.y += b.vy * f;
      const fr = Math.pow(weather === 'rain' ? 0.99 : 0.985, f);
      b.vx *= fr;
      b.vy *= fr;
      const minX = G.wide ? G.regionX + r : r;
      if (b.x < minX) { b.x = minX; b.vx *= -0.6; }
      if (b.x > G.W - r) { b.x = G.W - r; b.vx *= -0.6; }
      if (b.y > G.H - r) { b.y = G.H - r; b.vy *= -0.5; }
      if (prevY >= G.goalY && b.y < G.goalY && Math.abs(b.x - G.cx) < G.gw / 2 - r * 0.25) score(now);
      else if (b.y < G.goalY - 4) startReturn(now);
      else {
        const sp = Math.hypot(b.vx, b.vy);
        if (sp < 0.25) {
          b.vx = b.vy = 0;
          stillT += dt;
          if (stillT > 650 && Math.hypot(b.x - G.cx, b.y - G.startY) > 6) startReturn(now);
        } else stillT = 0;
      }
      prevY = b.y;
    } else if (state === 'scored') {
      b.x += b.vx * f;
      b.y += b.vy * f;
      const fr = Math.pow(0.9, f);
      b.vx *= fr;
      b.vy = b.vy * fr + 0.12 * f;
      const top = G.goalY - G.gh * 0.6, bot = G.goalY - G.gh * 0.1;
      if (b.y < top) { b.y = top; b.vy *= -0.3; }
      if (b.y > bot) { b.y = bot; b.vy *= -0.2; }
      const m = G.gw / 2 - r;
      b.x = Math.max(G.cx - m, Math.min(G.cx + m, b.x));
      if (now - tGoal > 900) startReturn(now, 0, 650);
    }
  }

  /* ---------- shooting ---------- */

  function kickToward(tx: number, ty: number): void {
    if (state !== 'idle' || Math.hypot(b.vx, b.vy) > 0.5) return;
    if (ty > b.y - 20) ty = G.goalY - G.gh * 0.3;
    const dx = tx - b.x, dy = ty - b.y, d = Math.hypot(dx, dy) || 1;
    const sp = vmax();
    b.vx = (dx / d) * sp;
    b.vy = (dy / d) * sp;
    stillT = 0;
    prevY = b.y;
    audio.kick(0.8);
    o.onKick?.();
  }

  function shootAtGoal(): void {
    kickToward(G.cx + (Math.random() - 0.5) * G.gw * 0.5, G.goalY - G.gh * 0.4);
  }

  /* ---------- input ---------- */

  const local = (e: PointerEvent): [number, number] => {
    const r = cv.getBoundingClientRect();
    return [e.clientX - r.left, e.clientY - r.top];
  };

  handle.addEventListener('pointerdown', (e) => {
    if (state === 'returning' || state === 'scored') return;
    const [p, q] = local(e);
    state = 'dragging';
    grab = [b.x - p, b.y - q];
    samples = [{ x: p, y: q, t: e.timeStamp }];
    downAt = { x: p, y: q, t: e.timeStamp };
    b.vx = b.vy = 0;
    handle.setPointerCapture(e.pointerId);
    handle.classList.add('is-dragging');
    e.preventDefault();
  });

  handle.addEventListener('pointermove', (e) => {
    if (state !== 'dragging') return;
    const [p, q] = local(e);
    const r = radius();
    const minX = G.wide ? G.regionX + r : r;
    b.x = Math.max(minX, Math.min(G.W - r, p + grab[0]));
    b.y = Math.max(G.goalY + (G.startY - G.goalY) * 0.3, Math.min(G.H - r, q + grab[1]));
    samples.push({ x: p, y: q, t: e.timeStamp });
    if (samples.length > 8) samples.shift();
  });

  function release(e: PointerEvent): void {
    if (state !== 'dragging') return;
    handle.classList.remove('is-dragging');
    const [p, q] = local(e);
    const now = e.timeStamp;
    state = 'idle';
    stillT = 0;
    prevY = b.y;
    // A tap on the ball (no real drag) shoots at the goal.
    if (downAt && Math.hypot(p - downAt.x, q - downAt.y) < 8 && now - downAt.t < 320) {
      downAt = null;
      shootAtGoal();
      return;
    }
    downAt = null;
    const recent = samples.filter((s) => now - s.t < 110);
    let vx = 0, vy = 0;
    if (recent.length > 1) {
      const a = recent[0], z = recent[recent.length - 1], d = Math.max(16, z.t - a.t);
      vx = ((z.x - a.x) / d) * 16.667;
      vy = ((z.y - a.y) / d) * 16.667;
    }
    const vm = vmax(), sp = Math.hypot(vx, vy);
    if (sp > vm) { vx *= vm / sp; vy *= vm / sp; }
    // gentle aim assist toward the goal mouth on upward flicks
    if (vy < -2) vx = vx * 0.8 + ((G.cx - b.x) / Math.max(40, b.y - G.goalY)) * Math.abs(vy) * 0.2;
    b.vx = vx;
    b.vy = vy;
    if (Math.hypot(vx, vy) > 2) {
      audio.kick(Math.min(1, Math.hypot(vx, vy) / vm));
      o.onKick?.();
    }
  }
  handle.addEventListener('pointerup', release);
  handle.addEventListener('pointercancel', release);

  // Tap anywhere on the pitch to shoot toward that spot (no dragging needed).
  let tapStart: { x: number; y: number; t: number } | null = null;
  cv.addEventListener('pointerdown', (e) => {
    tapStart = { x: e.clientX, y: e.clientY, t: e.timeStamp };
  });
  cv.addEventListener('pointerup', (e) => {
    if (!tapStart) return;
    const moved = Math.hypot(e.clientX - tapStart.x, e.clientY - tapStart.y);
    const quick = e.timeStamp - tapStart.t < 500;
    tapStart = null;
    if (moved > 10 || !quick) return;
    const [p, q] = local(e);
    if (q < G.pt - G.gh * 1.5) return; // taps on the stands do nothing
    if (G.wide && p < G.regionX) return;
    kickToward(p, q);
  });

  handle.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      shootAtGoal();
    } else if ((e.key === 'ArrowLeft' || e.key === 'ArrowRight') && state === 'idle' && !Math.hypot(b.vx, b.vy)) {
      e.preventDefault();
      const r = radius();
      const minX = (G.wide ? G.regionX : 0) + r;
      b.x = Math.max(minX, Math.min(G.W - r, b.x + (e.key === 'ArrowLeft' ? -16 : 16)));
      stillT = -100000; // stay where the visitor aimed
    }
  });

  /* ---------- render ---------- */

  function placeHandle(): void {
    const r = radius();
    const size = Math.max(56, r * 2.4);
    handle.style.width = handle.style.height = `${size}px`;
    handle.style.transform = `translate(${b.x - size / 2}px, ${b.y - size / 2}px)`;
  }

  function lightLevels(now: number): number[] {
    const tl = goals ? (now - tFirstGoal - 700) / 1000 : -1;
    return BANK_STARTS.map((s) => (tl >= 0 ? flicker(tl - s) : 0));
  }

  function frame(now: number): void {
    tNow = now;
    const dt = Math.min(40, now - lastT || 16);
    lastT = now;
    const slowMo = !reduce && goals === 1 && now - tGoal < 600 ? 0.3 : 1;
    const f = (dt / 16.667) * slowMo;
    update(f, dt, now);
    const r = radius();
    ball.roll(b.x - lastBX, b.y - lastBY, r);
    lastBX = b.x;
    lastBY = b.y;

    const banks = lightLevels(now);
    const L = (banks[0] + banks[1] + banks[2] + banks[3]) / 4;
    if (L >= 0.999 && !lightsAnnounced) {
      lightsAnnounced = true;
      o.onLightsUp?.();
    }

    const { W, H, dpr, cx, goalY, gh, gw } = G;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = '#07111f';
    ctx.fillRect(0, 0, W, H);

    ctx.save();
    const k = goals ? now - tGoal : 9999;
    if (k < 700 && !reduce) {
      const a = 1 - k / 700, z = 1 + 0.025 * Math.sin(Math.PI * Math.min(1, k / 700)), sh = Math.sin(k * 0.09) * 4 * a;
      ctx.translate(cx, goalY);
      ctx.scale(z, z);
      ctx.translate(-cx + sh, -goalY + sh * 0.4);
    }

    // the stadium, dim until the lights come on
    ctx.globalAlpha = 0.4 + 0.6 * L;
    ctx.drawImage(lit, 0, 0, W, H);
    ctx.globalAlpha = 1;
    if (L < 1) {
      ctx.fillStyle = `rgba(7,17,31,${0.22 * (1 - L)})`;
      ctx.fillRect(0, 0, W, H);
    }

    if (L > 0) {
      ctx.globalCompositeOperation = 'lighter';
      for (let i = 0; i < 4; i++) {
        if (banks[i] <= 0) continue;
        const [x, y] = bankXY(i), R = Math.max(W, H) * 0.7;
        const g2 = ctx.createRadialGradient(x, y, 0, x, y, R);
        g2.addColorStop(0, `rgba(255,244,214,${0.2 * banks[i]})`);
        g2.addColorStop(1, 'rgba(255,244,214,0)');
        ctx.fillStyle = g2;
        ctx.fillRect(0, 0, W, H);
        const tx = cx + (x - cx) * 0.25, ty = H * 0.9;
        const bg = ctx.createLinearGradient(x, y, tx, ty);
        bg.addColorStop(0, `rgba(255,244,214,${0.07 * banks[i]})`);
        bg.addColorStop(1, 'rgba(255,244,214,0)');
        ctx.fillStyle = bg;
        ctx.beginPath();
        ctx.moveTo(x - 6, y);
        ctx.lineTo(x + 6, y);
        ctx.lineTo(tx + W * 0.08, ty);
        ctx.lineTo(tx - W * 0.08, ty);
        ctx.fill();
      }
      ctx.globalCompositeOperation = 'source-over';
    }

    const inside = state === 'scored' || b.y < goalY;
    goalBack(L);
    if (inside) {
      ball.draw(ctx, b.x, b.y, r, (1 - L) * 0.4);
      goalFront(L);
    } else {
      goalFront(L);
      ball.draw(ctx, b.x, b.y, r, (1 - L) * 0.4);
    }
    for (let i = 0; i < 4; i++) drawBank(i, banks[i]);

    // camera flashes in the crowd once the lights are up
    if (!reduce && L > 0.4 && Math.random() < (now - tGoal < 3000 ? 0.5 : 0.08) * f)
      sparks.push({ x: G.regionX + Math.random() * G.regionW, y: Math.random() * (G.pt - H * 0.05), t: now });
    ctx.globalCompositeOperation = 'lighter';
    for (let i = sparks.length - 1; i >= 0; i--) {
      const s = sparks[i], q = (now - s.t) / 160;
      if (q > 1) { sparks.splice(i, 1); continue; }
      const R = Math.max(4, W * 0.01) * (1.2 - q * 0.4);
      const g3 = ctx.createRadialGradient(s.x, s.y, 0, s.x, s.y, R);
      g3.addColorStop(0, `rgba(255,255,255,${1 - q})`);
      g3.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = g3;
      ctx.fillRect(s.x - R, s.y - R, 2 * R, 2 * R);
    }
    // goal pulse ring
    if (goals && !reduce) {
      const q = (now - tGoal) / 1100;
      if (q < 1) {
        const R = gw * 0.3 + q * G.regionW * 0.8;
        ctx.strokeStyle = `rgba(255,255,255,${0.45 * (1 - q) * (goals === 1 ? 1 : 0.55)})`;
        ctx.lineWidth = 2 + 5 * (1 - q);
        ctx.beginPath();
        ctx.ellipse(cx, goalY - gh * 0.4, R, R * 0.35, 0, 0, Math.PI * 2);
        ctx.stroke();
      }
    }
    ctx.globalCompositeOperation = 'source-over';
    if (goals && !reduce) {
      const fa = Math.max(0, 1 - (now - tFirstGoal) / 500);
      if (fa > 0) {
        ctx.fillStyle = `rgba(255,255,255,${fa * 0.35})`;
        ctx.fillRect(-20, -20, W + 40, H + 40);
      }
    }
    ctx.restore();

    // vignette + film grain once lit
    const vg = ctx.createRadialGradient(cx, H / 2, Math.max(W, H) * 0.3, cx, H / 2, Math.max(W, H) * 0.85);
    vg.addColorStop(0, 'rgba(0,0,0,0)');
    vg.addColorStop(1, `rgba(0,0,0,${0.35 + 0.25 * L})`);
    ctx.fillStyle = vg;
    ctx.fillRect(0, 0, W, H);
    if (grain && L > 0 && !reduce) {
      ctx.save();
      ctx.globalAlpha = 0.06 * L;
      ctx.globalCompositeOperation = 'overlay';
      ctx.translate((Math.random() * 160) | 0, (Math.random() * 160) | 0);
      ctx.fillStyle = grain;
      ctx.fillRect(-160, -160, W + 320, H + 320);
      ctx.restore();
    }

    // illustrative weather
    const gu = gust(now);
    audio.weather(weather, gu);
    if (weather === 'rain') {
      ctx.fillStyle = `rgba(18,28,44,${0.12 + 0.18 * L})`;
      ctx.fillRect(0, 0, W, H);
    } else if (weather === 'clear' && L > 0) {
      ctx.fillStyle = `rgba(255,226,160,${0.05 * L})`;
      ctx.fillRect(0, 0, W, H);
    }
    if (weather !== 'clear') {
      const rain = weather === 'rain';
      const n = rain ? Math.min(reduce ? 60 : 220, (W * H) / 5200) | 0 : Math.min(reduce ? 14 : 46, (W * H) / 21000) | 0;
      while (particles.length < n) particles.push({ x: Math.random() * W, y: Math.random() * H, v: 0.6 + Math.random() * 0.6 });
      particles.length = n;
      const speed = reduce ? 0.2 : 1;
      ctx.lineWidth = 1;
      ctx.strokeStyle = `rgba(200,215,235,${0.16 + 0.16 * L})`;
      ctx.beginPath();
      for (const p of particles) {
        if (rain) {
          const sp = H * 0.03 * p.v * f * speed;
          p.y += sp;
          p.x -= sp * 0.12;
          if (p.y > H + 30) { p.y = -30; p.x = Math.random() * W * 1.2; }
          const len = Math.max(sp, H * 0.006);
          ctx.moveTo(p.x, p.y);
          ctx.lineTo(p.x + len * 0.25, p.y - len * 2.2);
        } else {
          p.x += gu * W * 0.012 * p.v * f * speed;
          if (p.x > W + 80) p.x = -80;
          if (p.x < -80) p.x = W + 80;
          ctx.moveTo(p.x, p.y);
          ctx.lineTo(p.x - gu * W * 0.07 * p.v, p.y + gu * 3);
        }
      }
      ctx.stroke();
    }

    placeHandle();
  }

  /* ---------- loop: runs only while the hero is on screen ---------- */

  let raf = 0, visible = true;
  const loop = (t: number) => {
    frame(t);
    raf = requestAnimationFrame(loop);
  };
  const start = () => {
    if (!raf && visible && !document.hidden) {
      lastT = performance.now();
      raf = requestAnimationFrame(loop);
    }
  };
  const stop = () => {
    cancelAnimationFrame(raf);
    raf = 0;
  };
  new IntersectionObserver(([en]) => {
    visible = en.isIntersecting;
    visible ? start() : stop();
  }).observe(cv);
  document.addEventListener('visibilitychange', () => (document.hidden ? stop() : start()));

  let rt = 0;
  new ResizeObserver(() => {
    clearTimeout(rt);
    rt = window.setTimeout(layout, 60);
  }).observe(cv);

  {
    const gc = document.createElement('canvas');
    gc.width = gc.height = 160;
    const q = gc.getContext('2d')!, im = q.createImageData(160, 160);
    for (let i = 0; i < im.data.length; i += 4) {
      const v = Math.random() * 255;
      im.data[i] = im.data[i + 1] = im.data[i + 2] = v;
      im.data[i + 3] = 255;
    }
    q.putImageData(im, 0, 0);
    grain = ctx.createPattern(gc, 'repeat');
  }

  layout();
  // Redraw the advertising boards once the display face has loaded.
  void document.fonts?.load('800 20px "Big Shoulders Display"').then(() => buildStadium());
  frame(performance.now());
  start();

  return {
    setWeather(w) {
      weather = w;
      particles.length = 0;
    },
    setSound(on) {
      audio.enable(on);
    },
    shoot: shootAtGoal,
  };
}
