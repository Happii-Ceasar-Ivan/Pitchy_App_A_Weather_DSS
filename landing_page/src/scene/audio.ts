/**
 * Synthesised match sounds (no audio files). Nothing is created until the
 * visitor turns sound on, so the page is silent by default.
 */

export type Weather = 'clear' | 'wind' | 'rain';

export class MatchAudio {
  private ac: AudioContext | null = null;
  private master: GainNode | null = null;
  private noiseBuf: AudioBuffer | null = null;
  private rainGain: GainNode | null = null;
  private windGain: GainNode | null = null;
  private ambientOn = false;
  enabled = false;

  enable(on: boolean): void {
    this.enabled = on;
    if (on) {
      this.init();
      void this.ac?.resume();
      this.master?.gain.setTargetAtTime(0.8, this.ac!.currentTime, 0.05);
    } else if (this.ac && this.master) {
      this.master.gain.setTargetAtTime(0, this.ac.currentTime, 0.05);
    }
  }

  private init(): void {
    if (this.ac) return;
    try {
      const AC = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      this.ac = new AC();
      this.master = this.ac.createGain();
      this.master.gain.value = 0;
      const cmp = this.ac.createDynamicsCompressor();
      this.master.connect(cmp);
      cmp.connect(this.ac.destination);
      this.noiseBuf = this.ac.createBuffer(1, this.ac.sampleRate * 2, this.ac.sampleRate);
      const d = this.noiseBuf.getChannelData(0);
      for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    } catch {
      this.ac = null;
    }
  }

  private get ready(): boolean {
    return this.enabled && !!this.ac && !!this.master && !!this.noiseBuf;
  }

  private noise(t: number, dur: number, type: BiquadFilterType, f0: number, f1: number, vol: number, q = 1): void {
    const ac = this.ac!;
    const s = ac.createBufferSource();
    s.buffer = this.noiseBuf;
    s.loop = true;
    const fl = ac.createBiquadFilter();
    fl.type = type;
    fl.Q.value = q;
    fl.frequency.setValueAtTime(f0, t);
    fl.frequency.exponentialRampToValueAtTime(f1, t + dur);
    const g = ac.createGain();
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(vol, t + Math.min(0.02, dur / 4));
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    s.connect(fl).connect(g).connect(this.master!);
    s.start(t);
    s.stop(t + dur + 0.05);
  }

  private tone(t: number, dur: number, f0: number, f1: number, vol: number, type: OscillatorType = 'sine'): void {
    const ac = this.ac!;
    const o = ac.createOscillator();
    const g = ac.createGain();
    o.type = type;
    o.frequency.setValueAtTime(f0, t);
    o.frequency.exponentialRampToValueAtTime(f1, t + dur);
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    o.connect(g).connect(this.master!);
    o.start(t);
    o.stop(t + dur + 0.05);
  }

  kick(power: number): void {
    if (!this.ready) return;
    const t = this.ac!.currentTime;
    this.tone(t, 0.12, 160, 50, 0.9 * power);
    this.noise(t, 0.06, 'lowpass', 900, 200, 0.5 * power);
  }

  net(): void {
    if (!this.ready) return;
    const t = this.ac!.currentTime;
    this.noise(t, 0.55, 'bandpass', 3000, 700, 0.5, 0.8);
    this.tone(t, 0.2, 100, 45, 0.6);
  }

  clunk(): void {
    if (!this.ready) return;
    const t = this.ac!.currentTime;
    this.tone(t, 0.18, 90, 40, 0.7, 'square');
    this.noise(t, 0.12, 'bandpass', 1500, 300, 0.45);
    this.noise(t + 0.05, 0.7, 'lowpass', 260, 120, 0.12);
  }

  roar(vol: number, dur: number): void {
    if (!this.ready) return;
    const ac = this.ac!;
    const t = ac.currentTime;
    const s = ac.createBufferSource();
    s.buffer = this.noiseBuf;
    s.loop = true;
    const f = ac.createBiquadFilter();
    f.type = 'bandpass';
    f.Q.value = 0.5;
    f.frequency.setValueAtTime(500, t);
    f.frequency.linearRampToValueAtTime(1100, t + dur * 0.3);
    const g = ac.createGain();
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(vol, t + 0.5);
    g.gain.setValueAtTime(vol, t + dur * 0.4);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    s.connect(f).connect(g).connect(this.master!);
    s.start(t);
    s.stop(t + dur + 0.1);
  }

  ambient(): void {
    if (!this.ready || this.ambientOn) return;
    this.ambientOn = true;
    const ac = this.ac!;
    const t = ac.currentTime;
    const s = ac.createBufferSource();
    s.buffer = this.noiseBuf;
    s.loop = true;
    const f = ac.createBiquadFilter();
    f.type = 'bandpass';
    f.frequency.value = 480;
    f.Q.value = 0.4;
    const g = ac.createGain();
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(0.06, t + 4);
    s.connect(f).connect(g).connect(this.master!);
    s.start(t);
  }

  weather(w: Weather, gust: number): void {
    if (!this.ready) return;
    const ac = this.ac!;
    if (!this.rainGain) {
      const mk = (type: BiquadFilterType, fq: number, q: number) => {
        const s = ac.createBufferSource();
        s.buffer = this.noiseBuf;
        s.loop = true;
        const fl = ac.createBiquadFilter();
        fl.type = type;
        fl.frequency.value = fq;
        fl.Q.value = q;
        const g = ac.createGain();
        g.gain.value = 0;
        s.connect(fl).connect(g).connect(this.master!);
        s.start();
        return g;
      };
      this.rainGain = mk('highpass', 1800, 0.5);
      this.windGain = mk('bandpass', 420, 1.1);
    }
    const t = ac.currentTime;
    this.rainGain.gain.setTargetAtTime(w === 'rain' ? 0.06 : 0, t, 0.4);
    this.windGain!.gain.setTargetAtTime(w === 'wind' ? 0.03 + 0.09 * Math.abs(gust) : 0, t, 0.25);
  }
}
