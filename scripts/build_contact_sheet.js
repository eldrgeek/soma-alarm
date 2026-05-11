#!/usr/bin/env node
// build_contact_sheet.js
// Generates a self-contained HTML contact sheet from screenshots.
// Usage: node build_contact_sheet.js <screenshots-dir> <timestamp>

const fs = require('fs');
const path = require('path');

const screensDir = process.argv[2] || path.join(__dirname, '../build/mobile-screenshots');
const timestamp = process.argv[3] || new Date().toISOString();
const outFile = path.join(screensDir, 'contact-sheet.html');

// Collect all PNG files under screensDir, up to 2 levels deep.
// Handles both flat (mobile/android/01-home.png) and nested
// (mobile/web-mobile-viewport/iphone14/01-jobs.png) structures.
function collectScreenshots(dir) {
  const result = [];
  if (!fs.existsSync(dir)) return result;

  function scanDir(scanPath, platformLabel) {
    const entries = fs.readdirSync(scanPath, { withFileTypes: true });
    const pngs = entries.filter(e => !e.isDirectory() && e.name.endsWith('.png'));
    const dirs = entries.filter(e => e.isDirectory());

    if (pngs.length > 0) {
      for (const f of pngs.map(e => e.name).sort()) {
        const fullPath = path.join(scanPath, f);
        const bytes = fs.readFileSync(fullPath);
        const b64 = bytes.toString('base64');
        result.push({
          platform: platformLabel,
          screen: f.replace('.png', ''),
          dataUri: `data:image/png;base64,${b64}`,
          label: `${platformLabel} / ${f.replace('.png', '').replace(/-/g, ' ')}`,
        });
      }
    } else {
      // Go one level deeper
      for (const d of dirs) {
        const subLabel = platformLabel ? `${platformLabel} / ${d.name}` : d.name;
        scanDir(path.join(scanPath, d.name), subLabel);
      }
    }
  }

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory() && entry.name !== 'contact-sheet.html') {
      scanDir(path.join(dir, entry.name), entry.name);
    }
  }
  return result;
}

const screenshots = collectScreenshots(screensDir);

if (screenshots.length === 0) {
  console.warn('[build_contact_sheet] No screenshots found in', screensDir);
  process.exit(0);
}

// Group by platform
const byPlatform = {};
for (const s of screenshots) {
  (byPlatform[s.platform] ||= []).push(s);
}

const refreshCmd = `./scripts/mobile_screenshots.sh web  # or android/ios/all`;

function platformSections() {
  return Object.entries(byPlatform).map(([platform, shots]) => `
    <section>
      <h2>${platform}</h2>
      <div class="grid">
        ${shots.map(s => `
          <div class="card">
            <a href="${s.dataUri}" target="_blank">
              <img src="${s.dataUri}" alt="${s.label}" loading="lazy" />
            </a>
            <div class="label">${s.screen.replace(/-/g, ' ')}</div>
          </div>
        `).join('')}
      </div>
    </section>
  `).join('');
}

const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Pulse Mobile Screens — ${timestamp}</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    background: #111;
    color: #eee;
    padding: 24px;
  }
  header {
    margin-bottom: 32px;
    border-bottom: 1px solid #333;
    padding-bottom: 16px;
  }
  header h1 { font-size: 1.6rem; font-weight: 600; }
  header .meta {
    margin-top: 8px;
    font-size: 0.85rem;
    color: #888;
    display: flex;
    flex-wrap: wrap;
    gap: 16px;
  }
  header .meta span { white-space: nowrap; }
  header .refresh {
    margin-top: 10px;
    font-family: 'SF Mono', 'Fira Mono', monospace;
    font-size: 0.8rem;
    background: #1a1a1a;
    border: 1px solid #333;
    padding: 6px 12px;
    border-radius: 6px;
    color: #9de;
    display: inline-block;
  }
  section { margin-bottom: 48px; }
  section h2 {
    font-size: 1.1rem;
    font-weight: 500;
    color: #aaa;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    margin-bottom: 16px;
    border-bottom: 1px solid #222;
    padding-bottom: 8px;
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
    gap: 16px;
  }
  .card {
    background: #1a1a1a;
    border: 1px solid #2a2a2a;
    border-radius: 10px;
    overflow: hidden;
    transition: border-color 0.15s;
  }
  .card:hover { border-color: #555; }
  .card a { display: block; }
  .card img {
    display: block;
    width: 100%;
    height: auto;
    max-height: 480px;
    object-fit: contain;
    background: #000;
  }
  .label {
    padding: 8px 10px;
    font-size: 0.78rem;
    color: #999;
    text-align: center;
    text-transform: capitalize;
  }
</style>
</head>
<body>
<header>
  <h1>Pulse Mobile Screens</h1>
  <div class="meta">
    <span>Captured: ${timestamp}</span>
    <span>Screens: ${screenshots.length}</span>
    <span>Platforms: ${Object.keys(byPlatform).join(', ')}</span>
  </div>
  <div class="refresh">${refreshCmd}</div>
</header>
${platformSections()}
</body>
</html>
`;

fs.writeFileSync(outFile, html, 'utf8');
console.log(`[build_contact_sheet] wrote ${outFile} (${screenshots.length} screens)`);
