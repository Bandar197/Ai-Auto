// Dump the timeline metadata (sound cues, VO placement, music sections) for the audio mixer.
import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import path from 'path';
import fs from 'fs';
const { chromium } = createRequire(import.meta.url)('playwright');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const video = process.argv[2] || 'seeker';
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
page.on('pageerror', (e) => console.log('pageerror:', e.message));
await page.goto('file://' + path.join(root, 'src/player.html') + `?v=${video}`);
await page.waitForFunction('window.READY === true', null, { timeout: 15000 });
const data = await page.evaluate(() => ({ duration: window.DURATION, sfx: window.SFX, vo: window.VO || [], music: window.MUSIC || null }));
fs.mkdirSync(path.join(root, 'out'), { recursive: true });
fs.writeFileSync(path.join(root, `out/${video}.cues.json`), JSON.stringify(data, null, 1));
console.log(video, 'cues:', data.sfx.length, 'vo:', data.vo.length, 'duration:', data.duration);
await browser.close();
