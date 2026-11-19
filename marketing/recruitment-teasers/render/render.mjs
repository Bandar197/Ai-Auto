// Frame-accurate renderer: N headless browsers each seek()+capture a slice of the timeline
// and pipe frames straight into x264; the slices are then joined without re-encoding.
//   node render/render.mjs <video> [--scale 2] [--fps 60] [--cc] [--workers 4] [--from 0] [--to <dur>] [--crf 17] [--out file.mp4]
import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import { spawn, execFileSync } from 'child_process';
import path from 'path';
import fs from 'fs';
const { chromium } = createRequire(import.meta.url)('playwright');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const argv = process.argv.slice(2);
const video = argv[0];
const opt = (k, d) => { const i = argv.indexOf('--' + k); return i < 0 ? d : argv[i + 1]; };
const scale = parseFloat(opt('scale', '2')), fps = parseInt(opt('fps', '60')), workers = parseInt(opt('workers', '4')), crf = opt('crf', '17');
const cc = argv.includes('--cc');
const url = 'file://' + path.join(root, 'src/player.html') + `?v=${video}${cc ? '&cc=1' : ''}`;
const tmp = path.join(root, 'out/tmp', `${video}-${scale}x${cc ? '-cc' : ''}`);
fs.rmSync(tmp, { recursive: true, force: true }); fs.mkdirSync(tmp, { recursive: true });

const probe = await chromium.launch();
const pp = await probe.newPage();
await pp.goto(url); await pp.waitForFunction('window.READY === true');
const duration = await pp.evaluate(() => window.DURATION);
await probe.close();
const from = parseFloat(opt('from', '0')), to = parseFloat(opt('to', String(duration)));
const f0 = Math.round(from * fps), f1 = Math.round(to * fps), total = f1 - f0;
const out = opt('out', path.join(root, 'out', `${video}-${Math.round(1080 * scale)}x${Math.round(1920 * scale)}${cc ? '-cc' : ''}.video.mp4`));
console.log(`${video}: ${total} frames @ ${fps}fps, ${1080 * scale}x${1920 * scale}, ${workers} workers${cc ? ', captions on' : ''}`);

let done = 0; const started = Date.now();
const tick = setInterval(() => {
  const el = (Date.now() - started) / 1000, rate = done / el;
  console.log(`  ${done}/${total} frames  ${rate.toFixed(2)} fps  eta ${rate ? Math.round((total - done) / rate / 60) : '?'} min`);
}, 60000);

async function worker(w) {
  const a = f0 + Math.floor((total * w) / workers), b = f0 + Math.floor((total * (w + 1)) / workers);
  const file = path.join(tmp, `part-${String(w).padStart(2, '0')}.mp4`);
  const ff = spawn('ffmpeg', ['-v', 'error', '-y', '-f', 'image2pipe', '-c:v', 'mjpeg', '-framerate', String(fps), '-i', '-',
    '-vf', 'scale=in_range=full:in_color_matrix=bt601:out_range=tv:out_color_matrix=bt709,noise=c0s=3:c0f=t,format=yuv420p',
    '-c:v', 'libx264', '-preset', 'medium', '-crf', crf, '-g', String(fps), '-bf', '2', '-threads', '2',
    '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv', '-video_track_timescale', '15360', file], { stdio: ['pipe', 'inherit', 'inherit'] });
  const closed = new Promise((res, rej) => ff.on('close', (c) => (c === 0 ? res() : rej(new Error('ffmpeg exit ' + c)))));
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: scale });
  page.on('pageerror', (e) => console.log('pageerror:', e.message));
  await page.goto(url); await page.waitForFunction('window.READY === true');
  for (let f = a; f < b; f++) {
    await page.evaluate((t) => window.seek(t), f / fps);
    const buf = await page.screenshot({ type: 'jpeg', quality: 96, animations: 'allow', caret: 'initial' });
    if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once('drain', r));
    done++;
  }
  ff.stdin.end(); await closed; await browser.close();
  return file;
}
const parts = await Promise.all(Array.from({ length: workers }, (_, w) => worker(w)));
clearInterval(tick);
const list = path.join(tmp, 'list.txt');
fs.writeFileSync(list, parts.map((p) => `file '${p}'`).join('\n'));
execFileSync('ffmpeg', ['-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', list, '-c', 'copy', '-movflags', '+faststart', out]);
console.log(`done in ${((Date.now() - started) / 60000).toFixed(1)} min → ${out}`);
