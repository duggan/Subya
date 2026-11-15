// node render.js frames.json outdir : draws each frame (an SVG snippet in a 320x180 scene) to a 1280x720 PNG.
// Needs playwright-core: npm install --prefix Resources/demo playwright-core
const path = require('path');
const fs = require('fs');
const { chromium } = require(path.join(__dirname, 'node_modules', 'playwright-core'));

(async () => {
  const [framesPath, out] = process.argv.slice(2);
  const frames = JSON.parse(fs.readFileSync(framesPath, 'utf8'));
  fs.rmSync(out, { recursive: true, force: true });
  fs.mkdirSync(out, { recursive: true });
  let browser;
  try { browser = await chromium.launch(); } catch { browser = await chromium.launch({ channel: 'chrome' }); }
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1 });
  await page.setContent('<style>html,body{margin:0;background:#7CCBFF}svg{display:block}</style>' +
    '<svg id="s" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 180" width="1280" height="720"></svg>');
  for (let i = 0; i < frames.length; i++) {
    await page.evaluate(svg => { document.getElementById('s').innerHTML = svg; }, frames[i]);
    await page.screenshot({ path: path.join(out, String(i).padStart(4, '0') + '.png') });
  }
  await browser.close();
  console.log(`${frames.length} frames`);
})();
