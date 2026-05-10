#!/usr/bin/env node
// playwright_mobile_screenshots.js
// Captures Pulse web UI in mobile viewports (iPhone 14 + Pixel 5).
// Usage: node playwright_mobile_screenshots.js <out-dir> <base-url>
//
// Flutter web renders to canvas (CanvasKit) so DOM text selectors don't work.
// Navigation uses coordinate-based clicks on the NavigationRail.

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const outDir = process.argv[2] || path.join(__dirname, '../build/mobile-screenshots');
const baseUrl = process.argv[3] || 'http://localhost:8088';

const VIEWPORTS = [
  { name: 'iphone14', width: 390, height: 844,
    ua: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1' },
  { name: 'pixel5',   width: 393, height: 851,
    ua: 'Mozilla/5.0 (Linux; Android 12; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36' },
];

// Flutter NavigationRail coordinate estimator.
// With labelType:all, 4 items, groupAlignment:-1 (top-aligned, default).
// Rail minWidth default: 72px. Items have top padding ~8px.
// Each item (icon 24px + label ~16px + vertical padding 16px) ≈ 56px tall.
function railCoords(vp, tabIndex) {
  const railX = 36; // center of ~72px wide rail
  // Items start near top (y≈8 padding), each ≈56px tall
  const itemY = 8 + 28 + tabIndex * 56; // 28 = half of first item height
  return { x: railX, y: itemY };
}

// R5 nav: 0=Conversation(default), 1=Jobs, 2=Activity, 3=Putoff, 4=Health
const TABS = [
  { index: 0, name: 'conversation' },
  { index: 1, name: 'jobs'        },
  { index: 2, name: 'activity'    },
  { index: 3, name: 'putoff'      },
  { index: 4, name: 'health'      },
];

async function captureViewport(browser, vp) {
  const dir = path.join(outDir, vp.name);
  fs.mkdirSync(dir, { recursive: true });

  const ctx = await browser.newContext({
    viewport: { width: vp.width, height: vp.height },
    userAgent: vp.ua,
    deviceScaleFactor: 2,
  });
  const page = await ctx.newPage();

  console.log(`[${vp.name}] navigating to ${baseUrl}`);
  await page.goto(baseUrl, { waitUntil: 'networkidle', timeout: 15000 });
  // Wait for Flutter to fully render (CanvasKit needs warm-up)
  await page.waitForTimeout(3500);

  // Capture all tabs in order (Conversation is default on load)
  for (const tab of TABS) {
    if (tab.index > 0) {
      const { x, y } = railCoords(vp, tab.index);
      console.log(`  [${vp.name}] clicking tab '${tab.name}' at (${x}, ${y})`);
      await page.mouse.click(x, y);
      await page.waitForTimeout(2500);
    }
    const num = String(tab.index + 1).padStart(2, '0');
    const file = path.join(dir, `${num}-${tab.name}.png`);
    await page.screenshot({ path: file, fullPage: false });
    console.log(`  [${vp.name}] saved ${num}-${tab.name}.png`);
  }

  await ctx.close();
}

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch({ headless: true });
  for (const vp of VIEWPORTS) {
    await captureViewport(browser, vp);
  }
  await browser.close();
  console.log('[done] web mobile viewport screenshots complete');
})().catch(err => {
  console.error('[fatal]', err.message);
  process.exit(1);
});
