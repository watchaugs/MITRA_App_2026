#!/usr/bin/env node
'use strict';
// ─────────────────────────────────────────────────────────────────────────────
// 16 KB page-size audit for an Android APK or AAB (Google Play requirement for
// apps targeting Android 15+). No dependencies — Node 18+ only.
//
//   flutter build apk --release
//   node tools/android/check_16kb.js build/app/outputs/flutter-apk/app-release.apk
//
//   flutter build appbundle --release
//   node tools/android/check_16kb.js build/app/outputs/bundle/release/app-release.aab
//
// For every native library (lib/<abi>/*.so) it reports:
//   ELF   – every PT_LOAD segment must have p_align >= 16384 (16 KB).
//   ZIP   – (APK only) an UNCOMPRESSED .so must start on a 16 KB boundary.
//   RELRO – end of the GNU_RELRO segment should fall on a 16 KB boundary;
//           otherwise the loader can make adjacent data read-only (crash).
// Only 64-bit ABIs (arm64-v8a, x86_64) are required by Play; 32-bit ABIs are
// shown for information. Exit code 1 if any required library fails.
// ─────────────────────────────────────────────────────────────────────────────
const fs = require('fs');
const zlib = require('zlib');

const PAGE = 16384;
const file = process.argv[2];
if (!file) { console.error('usage: node check_16kb.js <app.apk|app.aab>'); process.exit(2); }
const buf = fs.readFileSync(file);
const isAab = /\.aab$/i.test(file);

// ── minimal ZIP central-directory reader ──────────────────────────────────────
function entries(b) {
  let eocd = -1;
  for (let i = b.length - 22; i >= Math.max(0, b.length - 65557); i--) {
    if (b.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('not a zip file (no end-of-central-directory record)');
  let count = b.readUInt16LE(eocd + 10);
  let cd = b.readUInt32LE(eocd + 16);
  if (cd === 0xffffffff || count === 0xffff) {            // ZIP64
    const loc = eocd - 20;
    if (b.readUInt32LE(loc) !== 0x07064b50) throw new Error('ZIP64 locator missing');
    const z64 = Number(b.readBigUInt64LE(loc + 8));
    count = Number(b.readBigUInt64LE(z64 + 32));
    cd = Number(b.readBigUInt64LE(z64 + 48));
  }
  const out = [];
  for (let n = 0, p = cd; n < count; n++) {
    if (b.readUInt32LE(p) !== 0x02014b50) throw new Error('bad central directory');
    const method = b.readUInt16LE(p + 10);
    let csize = b.readUInt32LE(p + 20), usize = b.readUInt32LE(p + 24);
    const nlen = b.readUInt16LE(p + 28), xlen = b.readUInt16LE(p + 30), clen = b.readUInt16LE(p + 32);
    let lho = b.readUInt32LE(p + 42);
    const name = b.toString('utf8', p + 46, p + 46 + nlen);
    // ZIP64 extra field for large sizes/offsets
    let x = p + 46 + nlen; const xend = x + xlen;
    while (x + 4 <= xend) {
      const id = b.readUInt16LE(x), sz = b.readUInt16LE(x + 2); let q = x + 4;
      if (id === 0x0001) {
        if (usize === 0xffffffff) { usize = Number(b.readBigUInt64LE(q)); q += 8; }
        if (csize === 0xffffffff) { csize = Number(b.readBigUInt64LE(q)); q += 8; }
        if (lho === 0xffffffff) { lho = Number(b.readBigUInt64LE(q)); q += 8; }
      }
      x += 4 + sz;
    }
    out.push({ name, method, csize, usize, lho });
    p += 46 + nlen + xlen + clen;
  }
  return out;
}
function dataOffset(b, e) {
  if (b.readUInt32LE(e.lho) !== 0x04034b50) throw new Error('bad local header for ' + e.name);
  return e.lho + 30 + b.readUInt16LE(e.lho + 26) + b.readUInt16LE(e.lho + 28);
}
function bytesOf(b, e) {
  const off = dataOffset(b, e);
  const raw = b.subarray(off, off + e.csize);
  if (e.method === 0) return raw;
  if (e.method === 8) return zlib.inflateRawSync(raw);
  throw new Error(`unsupported compression ${e.method} for ${e.name}`);
}

// ── ELF program-header check ─────────────────────────────────────────────────
function elf(so) {
  if (so.readUInt32BE(0) !== 0x7f454c46) return { error: 'not an ELF file' };
  const is64 = so[4] === 2, le = so[5] === 1;
  const u16 = o => le ? so.readUInt16LE(o) : so.readUInt16BE(o);
  const u32 = o => le ? so.readUInt32LE(o) : so.readUInt32BE(o);
  const u64 = o => Number(le ? so.readBigUInt64LE(o) : so.readBigUInt64BE(o));
  const phoff = is64 ? u64(0x20) : u32(0x1c);
  const phentsize = u16(is64 ? 0x36 : 0x2a), phnum = u16(is64 ? 0x38 : 0x2c);
  const loads = []; let relro = null;
  for (let i = 0; i < phnum; i++) {
    const h = phoff + i * phentsize, type = u32(h);
    const vaddr = is64 ? u64(h + 0x10) : u32(h + 0x08);
    const memsz = is64 ? u64(h + 0x28) : u32(h + 0x14);
    const align = is64 ? u64(h + 0x30) : u32(h + 0x1c);
    if (type === 1) loads.push(align);
    if (type === 0x6474e552) relro = { vaddr, memsz };
  }
  return { is64, minAlign: loads.length ? Math.min(...loads) : 0, relro };
}

// ── run ───────────────────────────────────────────────────────────────────────
const libs = entries(buf).filter(e => /(^|\/)lib\/[^/]+\/[^/]+\.so$/.test(e.name));
if (!libs.length) { console.log('No native libraries found — nothing to check.'); process.exit(0); }
let fails = 0;
const rows = [];
for (const e of libs) {
  const abi = e.name.match(/lib\/([^/]+)\//)[1];
  const required = abi === 'arm64-v8a' || abi === 'x86_64';
  const info = elf(bytesOf(buf, e));
  const elfOk = !info.error && info.minAlign >= PAGE;
  const zipOk = isAab || e.method !== 0 || dataOffset(buf, e) % PAGE === 0;
  const relroOk = !info.relro || (info.relro.vaddr + info.relro.memsz) % PAGE === 0;
  const ok = elfOk && zipOk;
  if (required && !ok) fails++;
  rows.push({ abi, lib: e.name.split('/').pop(), required, ok,
    elf: info.error || `${info.minAlign / 1024} KB`, zip: e.method !== 0 ? 'compressed' : (zipOk ? 'aligned' : 'MISALIGNED'),
    relro: relroOk ? 'ok' : 'warn' });
}
rows.sort((a, b) => (a.ok - b.ok) || a.abi.localeCompare(b.abi) || a.lib.localeCompare(b.lib));
const pad = (s, n) => String(s).padEnd(n);
console.log(pad('RESULT', 8) + pad('ABI', 13) + pad('LIBRARY', 38) + pad('ELF LOAD', 10) + pad('ZIP', 12) + 'RELRO');
for (const r of rows) {
  const tag = r.ok ? 'PASS' : (r.required ? 'FAIL' : 'info');
  console.log(pad(tag, 8) + pad(r.abi, 13) + pad(r.lib, 38) + pad(r.elf, 10) + pad(isAab ? 'n/a (aab)' : r.zip, 12) + r.relro);
}
console.log(`\n${fails ? `❌ ${fails} required (64-bit) librar${fails === 1 ? 'y fails' : 'ies fail'} the 16 KB check.` : '✅ All 64-bit native libraries are 16 KB compatible.'}`);
if (rows.some(r => r.relro === 'warn' && r.required)) console.log('⚠️  RELRO warnings: see developer.android.com/guide/practices/page-sizes (RELRO alignment).');
process.exit(fails ? 1 : 0);
