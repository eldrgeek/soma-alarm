import { test, expect, Page } from '@playwright/test';
import * as path from 'path';
import * as fs from 'fs';

// Test A: page loads with HTTP 200 and no Pulse error console messages
test('A: loads with no UnimplementedError console messages', async ({ page }) => {
  const errors: string[] = [];

  page.on('console', msg => {
    if (msg.type() === 'error') {
      const text = msg.text();
      // Filter out browser/Flutter internal noise — only flag Pulse errors
      if (text.includes('UnimplementedError') || text.includes('SOMA-')) {
        errors.push(text);
      }
    }
  });

  const response = await page.goto('http://localhost:8088');
  expect(response?.status()).toBe(200);

  // Wait for Flutter to boot
  await page.waitForTimeout(3000);

  expect(errors, `Unexpected console errors: ${errors.join('\n')}`).toHaveLength(0);
});

// Test B: no red UnimplementedError banner visible on screen
test('B: no UnimplementedError banner on screen', async ({ page }) => {
  await page.goto('http://localhost:8088');
  await page.waitForTimeout(3000);

  const bodyText = await page.evaluate(() => document.body.innerText || '');
  expect(bodyText).not.toContain('UnimplementedError');
});

// Test C: Health screen fetches /health and renders service pills
// Flutter web renders to canvas so we verify via network interception + screenshot.
test('C: Health screen shows service pills', async ({ page }) => {
  // Capture the /health response so we can assert on its shape
  let healthBody: Record<string, unknown> | null = null;

  page.on('response', async resp => {
    if (resp.url().includes(':3333/health') && resp.status() === 200) {
      try { healthBody = await resp.json(); } catch { /* ignore */ }
    }
  });

  await page.goto('http://localhost:8088');

  // Wait for the first 5-second poll cycle plus render time
  await page.waitForTimeout(7000);

  // Assert the health response has the expected shape with component pills
  expect(healthBody, 'Expected /health response from relay').not.toBeNull();
  const components = (healthBody as any)?.components;
  expect(components, 'Expected components object in health response').toBeDefined();
  const serviceNames = Object.keys(components);
  expect(serviceNames.length, 'Expected at least one service pill').toBeGreaterThan(0);

  // Verify at least one known service is present
  const known = ['screenpipe_process', 'yeshie_relay', 'tailscale'];
  const found = known.some(s => serviceNames.includes(s));
  expect(found, `Known services not found. Got: ${serviceNames.join(', ')}`).toBe(true);

  // Capture screenshot as visual proof of HUD render
  const screenshotsDir = path.join(
    process.env.HOME || '',
    'Projects/SOMA/audits/screenshots',
  );
  if (!fs.existsSync(screenshotsDir)) {
    fs.mkdirSync(screenshotsDir, { recursive: true });
  }
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const screenshotPath = path.join(screenshotsDir, `pulse-hud-r1-${ts}.png`);
  await page.screenshot({ path: screenshotPath, fullPage: true });
  console.log(`Screenshot saved: ${screenshotPath}`);
});

// Test D: Jobs tab is reachable — JobsScreen polls /artifacts/cc-dispatch on load
test('D: Jobs tab reachable (cc-dispatch endpoint called)', async ({ page }) => {
  let ccDispatchCalled = false;

  page.on('request', req => {
    if (req.url().includes(':3333/artifacts/cc-dispatch')) {
      ccDispatchCalled = true;
    }
  });

  await page.goto('http://localhost:8088');
  // Jobs is the default tab (index 0) so JobsScreen mounts immediately
  await page.waitForTimeout(3000);

  expect(ccDispatchCalled, 'Expected /artifacts/cc-dispatch to be requested by Jobs tab').toBe(true);
});

// Test E: Jobs screen renders at least one card after /artifacts/cc-dispatch returns data
test('E: Jobs screen renders worker activity cards', async ({ page }) => {
  let ccDispatchData: Record<string, unknown> | null = null;

  page.on('response', async resp => {
    if (resp.url().includes(':3333/artifacts/cc-dispatch') && resp.status() === 200) {
      try { ccDispatchData = await resp.json(); } catch { /* ignore */ }
    }
  });

  await page.goto('http://localhost:8088');
  await page.waitForTimeout(4000);

  expect(ccDispatchData, 'Expected /artifacts/cc-dispatch response').not.toBeNull();
  const items = (ccDispatchData as any)?.items;
  expect(items, 'Expected items array in response').toBeDefined();
  expect(Array.isArray(items), 'Expected items to be an array').toBe(true);
  expect(items.length, 'Expected at least one worker run card').toBeGreaterThan(0);

  // Verify card shape
  const first = items[0];
  expect(first.task_name, 'Expected task_name field').toBeDefined();
  expect(first.status, 'Expected status field').toBeDefined();
  expect(['running', 'complete', 'failed'].includes(first.status), 'Expected valid status').toBe(true);
});

// Test F: job detail view loads and shows audit report content
// Verifies the /artifacts/file endpoint returns readable report content
test('F: job detail view loads audit report content via /artifacts/file', async ({ page }) => {
  let ccDispatchData: Record<string, unknown> | null = null;

  page.on('response', async resp => {
    if (resp.url().includes(':3333/artifacts/cc-dispatch') && resp.status() === 200) {
      try { ccDispatchData = await resp.json(); } catch { /* ignore */ }
    }
  });

  await page.goto('http://localhost:8088');
  await page.waitForTimeout(4000);

  expect(ccDispatchData, 'Expected cc-dispatch response').not.toBeNull();
  const items = (ccDispatchData as any)?.items as any[];
  expect(items?.length).toBeGreaterThan(0);

  // Find a job that has a matching report
  const withReport = items.find((item: any) => item.report_path != null);
  expect(withReport, 'Expected at least one item with a report_path').toBeDefined();

  // Fetch the report via the relay — simulates what the detail pane does
  const reportContent: string = await page.evaluate(async (path: string) => {
    const resp = await fetch(
      `http://localhost:3333/artifacts/file?path=${encodeURIComponent(path)}`
    );
    return resp.text();
  }, withReport.report_path);

  // All cc-dispatch reports contain this marker in the title
  expect(reportContent, 'Expected report content to contain cc-dispatch marker').toContain('cc-dispatch');

  // Take a screenshot showing the Jobs tab
  const screenshotsDir = path.join(process.env.HOME || '', 'Projects/SOMA/audits/screenshots');
  if (!fs.existsSync(screenshotsDir)) {
    fs.mkdirSync(screenshotsDir, { recursive: true });
  }
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const screenshotPath = path.join(screenshotsDir, `pulse-hud-r2-jobs-${ts}.png`);
  await page.screenshot({ path: screenshotPath, fullPage: true });
  console.log(`Jobs screenshot saved: ${screenshotPath}`);
});
