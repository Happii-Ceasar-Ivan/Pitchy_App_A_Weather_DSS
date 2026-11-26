// Downloads the official Switzer variable font from Fontshare at build time.
//
// Why: Switzer is under the ITF Free Font License (FFL v2.0). Self-hosting on our own site is allowed,
// but putting the font files in a public repository is not, and the files may not be modified
// (no subsetting or conversion). So the file is git-ignored, fetched unchanged from Fontshare
// during `npm run build` / `npm run dev`, and served from our own domain. Visitors never connect
// to Fontshare.
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { inflateRawSync } from 'node:zlib';

const KIT_URL = 'https://api.fontshare.com/v2/fonts/download/switzer';
const ENTRY = 'Switzer_Complete/Fonts/WEB/fonts/Switzer-Variable.woff2';
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = join(root, 'public', 'fonts', 'switzer-variable.woff2');

if (existsSync(out) && !process.argv.includes('--force')) {
  console.log('[fonts] Switzer already present, skipping download.');
  process.exit(0);
}

console.log(`[fonts] Downloading Switzer from ${KIT_URL}`);
const res = await fetch(KIT_URL);
if (!res.ok) throw new Error(`[fonts] Fontshare download failed: HTTP ${res.status}`);
const zip = Buffer.from(await res.arrayBuffer());

// Read the zip's central directory to find the one entry we need.
const eocd = zip.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
if (eocd < 0) throw new Error('[fonts] Not a zip archive.');
const count = zip.readUInt16LE(eocd + 10);
let p = zip.readUInt32LE(eocd + 16);
let font = null;
for (let i = 0; i < count; i++) {
  const method = zip.readUInt16LE(p + 10);
  const compSize = zip.readUInt32LE(p + 20);
  const nameLen = zip.readUInt16LE(p + 28);
  const extraLen = zip.readUInt16LE(p + 30);
  const commentLen = zip.readUInt16LE(p + 32);
  const localOffset = zip.readUInt32LE(p + 42);
  const name = zip.toString('utf8', p + 46, p + 46 + nameLen);
  if (name === ENTRY) {
    const lNameLen = zip.readUInt16LE(localOffset + 26);
    const lExtraLen = zip.readUInt16LE(localOffset + 28);
    const start = localOffset + 30 + lNameLen + lExtraLen;
    const data = zip.subarray(start, start + compSize);
    font = method === 0 ? Buffer.from(data) : method === 8 ? inflateRawSync(data) : null;
    if (!font) throw new Error(`[fonts] Unsupported zip method ${method}.`);
    break;
  }
  p += 46 + nameLen + extraLen + commentLen;
}
if (!font) throw new Error(`[fonts] ${ENTRY} not found in the Fontshare kit.`);
if (font.toString('latin1', 0, 4) !== 'wOF2') throw new Error('[fonts] Extracted file is not WOFF2.');

mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, font);
console.log(`[fonts] Wrote ${out} (${font.length} bytes).`);
