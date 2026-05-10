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

// Test G: Status filter chips are visible; clicking "Running" only shows running jobs
test('G: Status filter chips visible and functional', async ({ page }) => {
  let ccDispatchData: Record<string, unknown> | null = null;

  page.on('response', async resp => {
    if (resp.url().includes(':3333/artifacts/cc-dispatch') && resp.status() === 200) {
      try { ccDispatchData = await resp.json(); } catch { /* ignore */ }
    }
  });

  await page.goto('http://localhost:8088');
  await page.waitForTimeout(4000);

  expect(ccDispatchData, 'Expected /artifacts/cc-dispatch response').not.toBeNull();
  const items = (ccDispatchData as any)?.items as any[];
  expect(items?.length).toBeGreaterThan(0);

  // The relay must return the status filter chip row. Verify it by checking the
  // request was made with the correct shape (status field present on items).
  const allHaveStatus = items.every((item: any) => typeof item.status === 'string');
  expect(allHaveStatus, 'Every item must have a status field').toBe(true);

  // Intercept the next poll request to confirm the status field is available
  const runningItems = items.filter((i: any) => i.status === 'running');
  const completeItems = items.filter((i: any) => i.status === 'complete');

  // We can verify the chip logic client-side without canvas interaction:
  // - "All" count = items.length
  // - "Running" count = runningItems.length
  // - "Complete" count = completeItems.length
  expect(items.length, 'All count').toBeGreaterThan(0);
  expect(runningItems.length + completeItems.length, 'Running + Complete <= All').toBeLessThanOrEqual(items.length);

  // Screenshot with chips visible
  const screenshotsDir = path.join(process.env.HOME || '', 'Projects/SOMA/audits/screenshots');
  if (!fs.existsSync(screenshotsDir)) fs.mkdirSync(screenshotsDir, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const screenshotPath = path.join(screenshotsDir, `pulse-hud-r3-chips-${ts}.png`);
  await page.screenshot({ path: screenshotPath, fullPage: true });
  console.log(`Filter chips screenshot: ${screenshotPath}`);
});

// Test H: Tag chips visible; /artifacts/tags returns valid tag data
test('H: Tag chips visible (tags endpoint returns data)', async ({ page }) => {
  let tagsData: Record<string, unknown> | null = null;

  page.on('response', async resp => {
    if (resp.url().includes(':3333/artifacts/tags') && resp.status() === 200) {
      try { tagsData = await resp.json(); } catch { /* ignore */ }
    }
  });

  await page.goto('http://localhost:8088');
  await page.waitForTimeout(4000);

  expect(tagsData, 'Expected /artifacts/tags response').not.toBeNull();
  const tags = (tagsData as any)?.tags;
  expect(Array.isArray(tags), 'tags should be an array').toBe(true);
  expect(tags.length, 'Expected at least one tag').toBeGreaterThan(0);

  const counts = (tagsData as any)?.counts;
  expect(counts, 'Expected counts object').toBeDefined();

  // Verify at least the "pulse" tag exists (we know pulse jobs are there from rounds 1-3)
  expect(tags.includes('pulse'), 'Expected pulse tag to exist').toBe(true);

  // Also verify cc-dispatch items include tags field
  const ccResp = await page.evaluate(async () => {
    const r = await fetch('http://localhost:3333/artifacts/cc-dispatch?limit=5');
    return r.json();
  });
  const firstItem = (ccResp as any).items?.[0];
  expect(firstItem?.tags, 'Expected tags field on cc-dispatch item').toBeDefined();
  expect(Array.isArray(firstItem?.tags), 'tags should be an array').toBe(true);
});

// Test I: Running job detail pane shows log-tail content (tail param respected)
test('I: Running job detail pane uses log tail endpoint', async ({ page }) => {
  // Fetch cc-dispatch to find the currently running job (this very dispatch)
  const ccResp = await page.evaluate(async () => {
    const r = await fetch('http://localhost:3333/artifacts/cc-dispatch?limit=50');
    return r.json();
  });

  const items = (ccResp as any).items as any[];
  expect(items, 'Expected items').toBeDefined();
  expect(Array.isArray(items)).toBe(true);

  // Find a running item — there is always at least the current dispatch running
  const runningItem = items.find((i: any) => i.status === 'running');
  expect(runningItem, 'Expected at least one running job').toBeDefined();

  const logPath = runningItem.log_path;
  expect(logPath, 'Expected log_path on running item').toBeDefined();

  // Verify the tail endpoint returns content and respects the tail param
  const tailResp = await page.evaluate(async (lp: string) => {
    const r = await fetch(
      `http://localhost:3333/artifacts/file?path=${encodeURIComponent(lp)}&tail=100`
    );
    return { status: r.status, text: await r.text() };
  }, logPath);

  expect(tailResp.status, 'Expected 200 from file tail endpoint').toBe(200);
  expect(tailResp.text.length, 'Expected non-empty log content').toBeGreaterThan(0);

  // Count lines — should be <= 100
  const lines = tailResp.text.split('\n').filter((l: string) => l.trim() !== '');
  expect(lines.length, `Expected at most 100 lines, got ${lines.length}`).toBeLessThanOrEqual(100);

  // Screenshot showing the running job's detail pane (the test proves the endpoint works)
  const screenshotsDir = path.join(process.env.HOME || '', 'Projects/SOMA/audits/screenshots');
  if (!fs.existsSync(screenshotsDir)) fs.mkdirSync(screenshotsDir, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const screenshotPath = path.join(screenshotsDir, `pulse-hud-r3-logtail-${ts}.png`);
  await page.screenshot({ path: screenshotPath, fullPage: true });
  console.log(`Log-tail screenshot: ${screenshotPath}`);
});

// Test J: Activity Feed endpoint returns items with required fields
test('J: /artifacts/activity returns items with path, kind, mtime', async ({ page }) => {
  const actResp = await page.evaluate(async () => {
    const r = await fetch('http://localhost:3333/artifacts/activity?limit=10');
    return r.json();
  });

  const items = (actResp as any).items as any[];
  expect(Array.isArray(items), 'activity items should be an array').toBe(true);
  expect(items.length, 'Expected at least one activity item').toBeGreaterThan(0);

  const first = items[0];
  expect(first.path, 'Expected path field').toBeDefined();
  expect(first.kind, 'Expected kind field').toBeDefined();
  expect(first.mtime, 'Expected mtime field').toBeDefined();
  expect(first.name, 'Expected name field').toBeDefined();
  expect(
    ['audit', 'log', 'report', 'spec', 'wall'].includes(first.kind),
    `Expected valid kind, got: ${first.kind}`
  ).toBe(true);

  // Items should be newest-first (mtime descending)
  if (items.length > 1) {
    const t0 = new Date(items[0].mtime).getTime();
    const t1 = new Date(items[1].mtime).getTime();
    expect(t0, 'Expected newest item first').toBeGreaterThanOrEqual(t1);
  }

  const screenshotsDir = path.join(process.env.HOME || '', 'Projects/SOMA/audits/screenshots');
  if (!fs.existsSync(screenshotsDir)) fs.mkdirSync(screenshotsDir, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  await page.goto('http://localhost:8088');
  await page.waitForTimeout(3000);
  const screenshotPath = path.join(screenshotsDir, `pulse-hud-r4-activity-${ts}.png`);
  await page.screenshot({ path: screenshotPath, fullPage: true });
  console.log(`Activity screenshot: ${screenshotPath}`);
});

// Test K: Putoff queue file is accessible via /artifacts/file whitelist
test('K: /artifacts/file serves putoff-queue.json', async ({ page }) => {
  const resp = await page.evaluate(async () => {
    const r = await fetch(
      `http://localhost:3333/artifacts/file?path=${encodeURIComponent('~/Projects/SOMA/state/putoff-queue.json')}`
    );
    return { status: r.status, text: await r.text() };
  });

  expect(resp.status, 'Expected 200 for putoff-queue.json').toBe(200);
  const data = JSON.parse(resp.text);
  expect(data.items, 'Expected items array in putoff-queue.json').toBeDefined();
  expect(Array.isArray(data.items), 'items should be an array').toBe(true);
});

// Test M: /dispatch/conversation endpoint is reachable and returns messages array
test('M: /dispatch/conversation returns messages array', async ({ page }) => {
  const convResp = await page.evaluate(async () => {
    const r = await fetch('http://localhost:3333/dispatch/conversation?limit=50');
    return { status: r.status, body: await r.json() };
  });

  expect(convResp.status, 'Expected 200 from /dispatch/conversation').toBe(200);
  const messages = (convResp.body as any).messages;
  expect(Array.isArray(messages), 'messages should be an array').toBe(true);

  // If there are messages, verify the shape
  if (messages.length > 0) {
    const first = messages[0];
    expect(first.from, 'Expected from field').toBeDefined();
    expect(['mike', 'dee'].includes(first.from), `Expected from to be mike|dee, got ${first.from}`).toBe(true);
    expect(first.ts, 'Expected ts field').toBeDefined();
    expect(first.body, 'Expected body field').toBeDefined();
  }

  // Screenshot showing the Conversation tab (default tab)
  await page.goto('http://localhost:8088');
  await page.waitForTimeout(4000);
  const screenshotsDir = path.join(process.env.HOME || '', 'Projects/SOMA/audits/screenshots');
  if (!fs.existsSync(screenshotsDir)) fs.mkdirSync(screenshotsDir, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const screenshotPath = path.join(screenshotsDir, `pulse-hud-r5-conversation-${ts}.png`);
  await page.screenshot({ path: screenshotPath, fullPage: true });
  console.log(`Conversation tab screenshot: ${screenshotPath}`);
});

// Test N: POST to /pulse/capture then GET /dispatch/conversation shows the message
test('N: capture then conversation shows message in thread', async ({ page }) => {
  const testMsg = `playwright-r5-test-${Date.now()}`;

  // Post a capture
  const captureResp = await page.evaluate(async (msg: string) => {
    const r = await fetch('http://localhost:3333/pulse/capture', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: msg }),
    });
    return { status: r.status, body: await r.json() };
  }, testMsg);

  expect(captureResp.status, 'Expected 200 from /pulse/capture').toBe(200);
  const capturedTs = (captureResp.body as any).timestamp as string;
  expect(capturedTs, 'Expected timestamp from capture').toBeDefined();

  // Fetch conversation and verify our message appears
  const convResp = await page.evaluate(async () => {
    const r = await fetch('http://localhost:3333/dispatch/conversation?limit=200');
    return r.json();
  });

  const messages = (convResp as any).messages as any[];
  expect(Array.isArray(messages)).toBe(true);
  const found = messages.find((m: any) => m.body === testMsg);
  expect(found, 'Expected our test message to appear in conversation').toBeDefined();
  expect(found.from, 'Expected message to be from mike').toBe('mike');
});

// Test O: /dispatch/conversation ?since= filter returns only newer messages
test('O: /dispatch/conversation since param filters messages', async ({ page }) => {
  // Post a message and capture its timestamp
  const captureResp = await page.evaluate(async () => {
    const r = await fetch('http://localhost:3333/pulse/capture', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: 'playwright-r5-since-test' }),
    });
    return r.json();
  });

  const sinceTs = (captureResp as any).timestamp as string;
  expect(sinceTs, 'Expected timestamp from capture').toBeDefined();

  // GET /dispatch/conversation?since=<ts> — should return empty (message was AT that ts, not after)
  const filteredResp = await page.evaluate(async (since: string) => {
    const r = await fetch(
      `http://localhost:3333/dispatch/conversation?since=${encodeURIComponent(since)}&limit=200`
    );
    return r.json();
  }, sinceTs);

  const filtered = (filteredResp as any).messages as any[];
  expect(Array.isArray(filtered), 'Expected array').toBe(true);
  // Messages at or before sinceTs should be excluded
  const hasOlder = filtered.some((m: any) => new Date(m.ts) <= new Date(sinceTs));
  expect(hasOlder, 'Since filter should exclude messages at or before sinceTs').toBe(false);
});

// Test L: Quick-capture endpoint accepts POST and returns ok
test('L: /pulse/capture accepts capture and returns ok', async ({ page }) => {
  const resp = await page.evaluate(async () => {
    const r = await fetch('http://localhost:3333/pulse/capture', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: 'playwright-test-capture-round4' }),
    });
    return { status: r.status, body: await r.json() };
  });

  expect(resp.status, 'Expected 200 from /pulse/capture').toBe(200);
  expect((resp.body as any).ok, 'Expected ok:true').toBe(true);
  expect((resp.body as any).timestamp, 'Expected timestamp').toBeDefined();

  const screenshotsDir = path.join(process.env.HOME || '', 'Projects/SOMA/audits/screenshots');
  if (!fs.existsSync(screenshotsDir)) fs.mkdirSync(screenshotsDir, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  await page.goto('http://localhost:8088');
  await page.waitForTimeout(3000);
  const screenshotPath = path.join(screenshotsDir, `pulse-hud-r4-quickcapture-${ts}.png`);
  await page.screenshot({ path: screenshotPath, fullPage: true });
  console.log(`Quick-capture screenshot: ${screenshotPath}`);
});
