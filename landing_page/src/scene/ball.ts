/**
 * A procedural football: 12 pentagon patches on an icosahedron, rotated in
 * true 3D as the ball rolls, so the spin always matches the direction of travel.
 */

type V3 = [number, number, number];
interface Patch {
  c: V3;
  u: V3;
}

const cross = (a: V3, b: V3): V3 => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const norm = (v: V3): V3 => {
  const n = Math.hypot(v[0], v[1], v[2]) || 1;
  return [v[0] / n, v[1] / n, v[2] / n];
};

export class Ball {
  private patches: Patch[] = [];

  constructor() {
    const p = 1.618;
    const verts: V3[] = [
      [0, 1, p], [0, -1, p], [0, 1, -p], [0, -1, -p],
      [1, p, 0], [-1, p, 0], [1, -p, 0], [-1, -p, 0],
      [p, 0, 1], [-p, 0, 1], [p, 0, -1], [-p, 0, -1],
    ];
    for (const v of verts) {
      const c = norm(v);
      let u = cross(c, [0, 0, 1]);
      if (Math.hypot(...u) < 0.1) u = cross(c, [0, 1, 0]);
      this.patches.push({ c, u: norm(u) });
    }
    this.spin(0.6, 0.35);
  }

  /** Roll the ball by a screen-space displacement (dx, dy) for radius r. */
  roll(dx: number, dy: number, r: number): void {
    if (!dx && !dy) return;
    this.spin(dx / r, dy / r);
  }

  private spin(a: number, b: number): void {
    const cA = Math.cos(a), sA = Math.sin(a), cB = Math.cos(b), sB = Math.sin(b);
    const rot = (v: V3): V3 => {
      const x = v[0] * cA + v[2] * sA;
      let z = -v[0] * sA + v[2] * cA;
      const y = v[1] * cB + z * sB;
      z = -v[1] * sB + z * cB;
      return [x, y, z];
    };
    for (const p of this.patches) {
      p.c = norm(rot(p.c));
      const u = rot(p.u);
      const d = u[0] * p.c[0] + u[1] * p.c[1] + u[2] * p.c[2];
      p.u = norm([u[0] - d * p.c[0], u[1] - d * p.c[1], u[2] - d * p.c[2]]);
    }
  }

  /** Draw at (x, y) with radius r. `shade` 0..1 darkens it before the lights are on. */
  draw(g: CanvasRenderingContext2D, x: number, y: number, r: number, shade: number): void {
    g.save();
    // contact shadow
    g.fillStyle = 'rgba(0,0,0,.34)';
    g.beginPath();
    g.ellipse(x + r * 0.12, y + r * 0.92, r * 0.95, r * 0.22, 0, 0, Math.PI * 2);
    g.fill();

    g.beginPath();
    g.arc(x, y, r, 0, Math.PI * 2);
    g.clip();

    let gr = g.createRadialGradient(x - r * 0.35, y - r * 0.42, r * 0.08, x, y, r);
    gr.addColorStop(0, '#ffffff');
    gr.addColorStop(0.55, '#e6e9ec');
    gr.addColorStop(1, '#8e959c');
    g.fillStyle = gr;
    g.fillRect(x - r, y - r, 2 * r, 2 * r);

    // seams: a faint line from each visible patch to its nearest neighbours
    g.strokeStyle = 'rgba(40,46,54,.28)';
    g.lineWidth = Math.max(0.6, r * 0.025);
    g.beginPath();
    for (let i = 0; i < this.patches.length; i++) {
      const a = this.patches[i].c;
      if (a[2] < -0.2) continue;
      for (let j = i + 1; j < this.patches.length; j++) {
        const b = this.patches[j].c;
        const dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
        if (dot < 0.4 || b[2] < -0.2) continue;
        g.moveTo(x + a[0] * r, y + a[1] * r);
        g.lineTo(x + b[0] * r, y + b[1] * r);
      }
    }
    g.stroke();

    // pentagons
    g.fillStyle = '#15191e';
    for (const p of this.patches) {
      if (p.c[2] < -0.35) continue;
      const w = cross(p.c, p.u);
      g.beginPath();
      for (let i = 0; i < 5; i++) {
        const th = i * 1.2566, a = 0.38;
        const q = [0, 1, 2].map(
          (k) => p.c[k] * Math.cos(a) + (p.u[k] * Math.cos(th) + w[k] * Math.sin(th)) * Math.sin(a),
        );
        if (i) g.lineTo(x + q[0] * r, y + q[1] * r);
        else g.moveTo(x + q[0] * r, y + q[1] * r);
      }
      g.closePath();
      g.fill();
    }

    // rim darkening + highlight
    gr = g.createRadialGradient(x - r * 0.4, y - r * 0.45, r * 0.2, x, y, r * 1.05);
    gr.addColorStop(0, 'rgba(0,0,0,0)');
    gr.addColorStop(1, 'rgba(0,0,0,.42)');
    g.fillStyle = gr;
    g.fillRect(x - r, y - r, 2 * r, 2 * r);
    gr = g.createRadialGradient(x - r * 0.38, y - r * 0.45, 0, x - r * 0.38, y - r * 0.45, r * 0.5);
    gr.addColorStop(0, 'rgba(255,255,255,.55)');
    gr.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = gr;
    g.fillRect(x - r, y - r, 2 * r, 2 * r);

    if (shade > 0) {
      g.fillStyle = `rgba(4,10,18,${shade})`;
      g.fillRect(x - r, y - r, 2 * r, 2 * r);
    }
    g.restore();
  }
}
