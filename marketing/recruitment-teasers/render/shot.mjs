// Quick still capture for visual QA:  node render/shot.mjs <video> <t1,t2,...> [outDir] [scale]
import { createRequire } from 'module';
const { chromium } = createRequire(import.meta.url)('playwright');
import { fileURLToPath } from 'url';
import path from 'path';
import fs from 'fs';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const [video = 'seeker', times = '0', outDir = path.join(root, 'out/shots'), scale = '0.5', cc = '0'] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: parseFloat(scale) });
page.on('console', (m) => { if (m.type() === 'error') console.log('console:', m.text()); });
page.on('pageerror', (e) => console.log('pageerror:', e.message));
await page.goto('file://' + path.join(root, 'src/player.html') + `?v=${video}&cc=${cc}`);
await page.waitForFunction('window.READY === true', null, { timeout: 8000 }).catch(() => { console.log('NOT READY (script error?)'); process.exit(1); });
for (const t of times.split(',').map(Number)) {
  await page.evaluate((t) => window.seek(t), t);
  const f = path.join(outDir, `${video}-${t.toFixed(2).padStart(6, '0')}.jpg`);
  await page.screenshot({ path: f, type: 'jpeg', quality: 88 });
  console.log(f);
}
await browser.close();
