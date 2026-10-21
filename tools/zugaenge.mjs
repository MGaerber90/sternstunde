// Erzeugt Zugänge für Sternstunde:
//   - PIN pro Schüler, Klassencode, Lehrer-PIN (bleiben beim erneuten Ausführen gleich)
//   - supabase/seed.local.sql   (Startdaten für die Datenbank)
//   - supabase/items.sql        (Shop-Preise, damit der Server Käufe prüfen kann)
//   - namen.local.js            (Namen und PINs für den lokalen Testmodus)
//   - zugangskarten.local.html  (PIN-Karten zum Ausdrucken)
//
// Aufruf:  node tools/zugaenge.mjs            vorhandene PINs behalten
//          node tools/zugaenge.mjs --neu      alle PINs, Code und Lehrer-PIN neu
//          node tools/zugaenge.mjs --url=https://...   Adresse der App auf den Karten
//
// Alle *.local.*-Dateien enthalten personenbezogene Daten und stehen in .gitignore.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { randomInt, randomBytes } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const P = f => join(ROOT, f);
const args = process.argv.slice(2);
const NEU = args.includes('--neu');
const urlArg = (args.find(a => a.startsWith('--url=')) || '').slice(6);

// ---------- Namen ----------
const namenSrc = readFileSync(P('namen.local.js'), 'utf8');
const listMatch = namenSrc.match(/STERNSTUNDE_NAMES\s*=\s*\[([\s\S]*?)\]/);
if (!listMatch) throw new Error('namen.local.js: STERNSTUNDE_NAMES nicht gefunden');
const names = [...listMatch[1].matchAll(/'([^']+)'|"([^"]+)"/g)].map(m => (m[1] || m[2]).trim()).filter(Boolean)
  .sort((a, b) => a.localeCompare(b, 'de'));
if (new Set(names).size !== names.length) throw new Error('Doppelte Namen in namen.local.js, bitte eindeutig machen (z. B. "Lukas M.")');

// ---------- Vorhandene Zugänge ----------
const stateFile = P('zugang.local.json');
const prev = !NEU && existsSync(stateFile) ? JSON.parse(readFileSync(stateFile, 'utf8')) : null;

const CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const classCode = prev?.classCode || Array.from({ length: 6 }, () => CODE_CHARS[randomInt(CODE_CHARS.length)]).join('');
const teacherPin = prev?.teacherPin || String(randomInt(10000000, 100000000));
const url = urlArg || prev?.url || 'https://mgaerber90.github.io/sternstunde/';

const badPin = p => /^(\d)\1{3}$/.test(p) || '0123456789'.includes(p) || '9876543210'.includes(p) || /^(19|20)\d\d$/.test(p) || /^(\d\d)\1$/.test(p);
const used = new Set();
const prevByName = new Map((prev?.students || []).map(s => [s.name, s]));
const students = names.map(name => {
  const old = prevByName.get(name);
  if (old && !used.has(old.pin)) { used.add(old.pin); return old; }
  let pin;
  do { pin = String(randomInt(0, 10000)).padStart(4, '0'); } while (badPin(pin) || used.has(pin));
  used.add(pin);
  return { id: 'st_' + randomBytes(5).toString('hex'), name, pin };
});

writeFileSync(stateFile, JSON.stringify({ classCode, teacherPin, url, students }, null, 2));

// ---------- namen.local.js ----------
writeFileSync(P('namen.local.js'), `/* Echte Vornamen und PINs der Klasse. NUR LOKAL, wird nicht hochgeladen (.gitignore).
   Erzeugt mit: node tools/zugaenge.mjs */
window.STERNSTUNDE_NAMES = [
${names.map(n => `  ${JSON.stringify(n)}`).join(',\n')}
];
window.STERNSTUNDE_PINS = {
${students.map(s => `  ${JSON.stringify(s.name)}: '${s.pin}'`).join(',\n')}
};
`);

// ---------- seed.local.sql ----------
const q = s => `'${String(s).replace(/'/g, "''")}'`;
writeFileSync(P('supabase/seed.local.sql'), `-- =====================================================================
-- Sternstunde: Startdaten. NICHT VERÖFFENTLICHEN, enthält Namen und PINs.
-- Nach schema.sql und items.sql im Supabase SQL Editor ausführen.
-- Erneutes Ausführen aktualisiert Namen und PINs, Sterne und Avatare bleiben.
-- =====================================================================
insert into app_meta (id, class_code, teacher_pin_hash, settings)
values (1, ${q(classCode)}, crypt(${q(teacherPin)}, gen_salt('bf')), '{"className":"9m","schoolYear":"2026/27","teacherLabel":""}'::jsonb)
on conflict (id) do update set class_code = excluded.class_code, teacher_pin_hash = excluded.teacher_pin_hash;

insert into students (id, name, pin, sort) values
${students.map((s, i) => `  (${q(s.id)}, ${q(s.name)}, ${q(s.pin)}, ${i})`).join(',\n')}
on conflict (id) do update set name = excluded.name, pin = excluded.pin, sort = excluded.sort;
`);

// ---------- items.sql (aus dem Katalog in index.html) ----------
const html = readFileSync(P('index.html'), 'utf8');
const cat = html.slice(html.indexOf('const CATALOG = ['), html.indexOf('];', html.indexOf('const CATALOG = [')));
const items = [...cat.matchAll(/id: '([^']+)', slot: '[^']+', name: '[^']+', price: (\d+)(?:, ach: '([^']+)')?/g)].map(m => ({ id: m[1], price: +m[2], ach: m[3] || null }));
if (items.length < 50) throw new Error('Katalog nicht gefunden oder unvollständig');
writeFileSync(P('supabase/items.sql'), `-- Shop-Preise (automatisch erzeugt aus index.html, nicht von Hand ändern)
-- Nach jeder Katalog-Änderung: node tools/zugaenge.mjs  und diese Datei erneut in Supabase ausführen.
delete from item_prices;
insert into item_prices (id, price, ach) values
${items.map(i => `  (${q(i.id)}, ${i.price}, ${i.ach ? q(i.ach) : 'null'})`).join(',\n')};
`);

// ---------- QR-Code (qr.svg, zeigt auf die App-Adresse) ----------
const qrSvg = existsSync(P('qr.svg')) ? readFileSync(P('qr.svg'), 'utf8') : '';

// ---------- Zugangskarten ----------
const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
writeFileSync(P('zugangskarten.local.html'), `<!DOCTYPE html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sternstunde · Zugangskarten 9m</title>
<style>
  *{box-sizing:border-box}
  body{margin:0;font-family:"Segoe UI",system-ui,sans-serif;background:#eef0fa;color:#1f1d2b}
  .wrap{max-width:210mm;margin:0 auto;padding:16px}
  .bar{display:flex;gap:12px;align-items:center;margin:8px 0 16px}
  .bar h1{font-size:20px;margin:0;flex:1}
  button{font:inherit;font-weight:700;padding:10px 16px;border:0;border-radius:10px;background:#4338ca;color:#fff;cursor:pointer}
  .teacher{background:#fff;border:2px solid #4338ca;border-radius:12px;padding:14px 16px;margin-bottom:16px;line-height:1.5}
  .teacher b{font-family:Consolas,monospace;font-size:18px;letter-spacing:.12em}
  .teacher table{border-collapse:collapse;width:100%;margin-top:8px;font-size:14px}
  .teacher td{border-bottom:1px solid #ddd;padding:4px 6px}
  .teacher td.pin{font-family:Consolas,monospace;font-weight:700;letter-spacing:.15em}
  .cards{display:grid;grid-template-columns:repeat(3,1fr);background:#fff}
  .card{border:1px dashed #9aa0b8;padding:4.5mm 5mm;height:69mm;display:flex;flex-direction:column;gap:1.6mm;break-inside:avoid;overflow:hidden}
  .card .top{display:flex;align-items:center;gap:2mm;font-weight:800;color:#4338ca;font-size:10pt;letter-spacing:.06em}
  .card .head{display:flex;justify-content:space-between;align-items:flex-start;gap:3mm}
  .card .name{font-size:17pt;font-weight:800;margin-top:1mm}
  .card .qr{width:19mm;height:19mm;flex:none}
  .card .qr svg{width:100%;height:100%;display:block}
  .card .row{display:flex;justify-content:space-between;align-items:baseline;border-top:1px solid #e3e5f0;padding-top:1.5mm}
  .card .row span{font-size:8pt;color:#666;text-transform:uppercase;letter-spacing:.05em}
  .card .row b{font-family:Consolas,monospace;font-size:15pt;letter-spacing:.18em}
  .card .steps{font-size:7.5pt;color:#555;line-height:1.35;margin-top:auto}
  .card .url{font-size:7.5pt;font-weight:700;word-break:break-all;color:#1f1d2b}
  @media print{
    @page{size:A4;margin:8mm}
    body{background:#fff}
    .noprint{display:none!important}
    .wrap{padding:0;max-width:none}
  }
</style></head><body><div class="wrap">
<div class="bar noprint"><h1>Zugangskarten Klasse 9m</h1><button onclick="window.print()">Als PDF herunterladen</button></div>
<div class="teacher noprint">
  <div>Nur für dich, wird nicht mitgedruckt.</div>
  <div>Lehrer-PIN: <b>${teacherPin}</b> &nbsp;·&nbsp; Klassencode: <b>${classCode}</b></div>
  <div>Adresse: ${esc(url)}</div>
  <table>${students.map(s => `<tr><td>${esc(s.name)}</td><td class="pin">${s.pin}</td></tr>`).join('')}</table>
</div>
<div class="cards">
${students.map(s => `  <div class="card">
    <div class="top"><svg width="14" height="14" viewBox="0 0 24 24"><path fill="#f2a900" d="M12 2.5l2.9 6.1 6.6.8-4.9 4.6 1.3 6.6L12 17.3 6.1 20.6l1.3-6.6L2.5 9.4l6.6-.8z"/></svg>STERNSTUNDE · 9M</div>
    <div class="head"><div class="name">${esc(s.name)}</div>${qrSvg ? `<div class="qr">${qrSvg}</div>` : ''}</div>
    <div class="row"><span>Klassencode</span><b>${classCode}</b></div>
    <div class="row"><span>Deine PIN</span><b>${s.pin}</b></div>
    <div class="steps">QR-Code scannen, „Ich bin in der Klasse“, Klassencode eingeben, Namen wählen, PIN eingeben. PIN nicht weitergeben!</div>
    <div class="url">${esc(url)}</div>
  </div>`).join('\n')}
</div></div></body></html>
`);

writeFileSync(P('qr-plakat.local.html'), `<!DOCTYPE html>
<html lang="de"><head><meta charset="utf-8"><title>Sternstunde · QR-Code</title>
<style>
  *{box-sizing:border-box} body{margin:0;font-family:"Segoe UI",system-ui,sans-serif;color:#1f1d2b;background:#fff}
  .page{width:210mm;min-height:297mm;margin:0 auto;padding:22mm 18mm;display:flex;flex-direction:column;align-items:center;text-align:center}
  h1{font-size:44pt;margin:0;color:#4338ca;letter-spacing:.02em} .sub{font-size:16pt;color:#555;margin:3mm 0 12mm}
  .qr{width:140mm;height:140mm;border:3mm solid #1f1d2b;border-radius:6mm;padding:4mm} .qr svg{width:100%;height:100%;display:block}
  .url{font-size:15pt;font-weight:700;margin-top:10mm;word-break:break-all}
  .code{margin-top:8mm;font-size:16pt} .code b{font-family:Consolas,monospace;font-size:26pt;letter-spacing:.2em;margin-left:4mm}
  .hint{margin-top:6mm;font-size:12pt;color:#666}
  .bar{position:fixed;top:12px;right:12px} button{font:inherit;font-weight:700;padding:10px 16px;border:0;border-radius:10px;background:#4338ca;color:#fff;cursor:pointer}
  @media print{@page{size:A4;margin:0} .bar{display:none}}
</style></head><body>
<div class="bar"><button onclick="window.print()">Als PDF herunterladen</button></div>
<div class="page">
  <h1>STERNSTUNDE</h1><div class="sub">Klasse 9m · Scannen und los</div>
  <div class="qr">${qrSvg}</div>
  <div class="url">${esc(url)}</div>
  <div class="code">Klassencode:<b>${classCode}</b></div>
  <div class="hint">Namen wählen, PIN von deiner Karte eingeben.</div>
</div></body></html>
`);

console.log(`Klassencode: ${classCode}`);
console.log(`Lehrer-PIN:  ${teacherPin}`);
console.log(`${students.length} Schüler, ${items.length} Shop-Items`);
console.log('Geschrieben: namen.local.js, zugang.local.json, supabase/seed.local.sql, supabase/items.sql, zugangskarten.local.html, qr-plakat.local.html');
