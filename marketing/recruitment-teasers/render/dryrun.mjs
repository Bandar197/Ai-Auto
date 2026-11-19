// Seek through every frame without capturing, to catch runtime errors before a long render.
import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import path from 'path';
const { chromium } = createRequire(import.meta.url)('playwright');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const fps = 60;
let bad = 0;
for (const video of process.argv.slice(2)) for (const cc of ['', '&cc=1']) {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 0.25 });
  page.on('pageerror', (e) => { bad++; console.log(video, 'pageerror:', e.message); });
  page.on('console', (m) => { if (m.type() === 'error') { bad++; console.log(video, 'console:', m.text()); } });
  await page.goto('file://' + path.join(root, 'src/player.html') + `?v=${video}${cc}`);
  await page.waitForFunction('window.READY === true');
  const res = await page.evaluate((fps) => {
    const errs = []; const n = Math.round(window.DURATION * fps);
    for (let f = 0; f < n; f++) { try { window.seek(f / fps); } catch (e) { errs.push(`t=${(f / fps).toFixed(3)}: ${e.message}`); if (errs.length > 8) break; } }
    return { n, errs };
  }, fps);
  console.log(video, cc ? 'cc' : 'main', res.n, 'frames,', res.errs.length, 'errors', res.errs.join(' | '));
  bad += res.errs.length;
  await browser.close();
}
process.exit(bad ? 1 : 0);
