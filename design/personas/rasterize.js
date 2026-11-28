// Renders design/personas/svg/*.svg to PNGs in apps/mobile/assets/personas.
// Usage (from repo root): node design/personas/rasterize.js
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const src = path.join(__dirname, 'svg');
const out = path.join(__dirname, '../../apps/mobile/assets/personas');
const SIZES = { head: [288, 288], full: [576, 720] };
(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage();
  for (const f of fs.readdirSync(src).filter((f) => f.endsWith('.svg'))) {
    const [w, h] = SIZES[f.endsWith('_head.svg') ? 'head' : 'full'];
    await page.setViewportSize({ width: w, height: h });
    const svg = fs.readFileSync(path.join(src, f), 'utf8').replace('<svg ', `<svg width="${w}" height="${h}" `);
    await page.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
    await page.screenshot({ path: path.join(out, f.replace('.svg', '.png')), omitBackground: true, clip: { x: 0, y: 0, width: w, height: h } });
  }
  await browser.close();
})();
