import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession, launchSolo, waitForShinyBoot, saveState, demoteUser } from './helpers';
import path from 'path';
import fs from 'fs';

// Create a synthetic LTER sensor CSV for testing
function createSensorCsv(): string {
  const csvPath = path.join(__dirname, 'test-sensor-data.csv');
  const rows = ['Timestamp,SiteID,Temperature,SoilMoisture'];
  const sites = ['SITE_A', 'SITE_B'];
  for (let day = 1; day <= 5; day++) {
    for (const site of sites) {
      const temp = 25 + Math.random() * 10;
      const moisture = 30 + Math.random() * 20;
      rows.push(`2026-06-${String(day).padStart(2, '0')} 12:00:00,${site},${temp.toFixed(1)},${moisture.toFixed(1)}`);
    }
  }
  fs.writeFileSync(csvPath, rows.join('\n'));
  return csvPath;
}

test.describe('Climate Anomaly Detector: Core Four Matrix (REST)', () => {
  test.setTimeout(90000);
  const sharedSaveName = `Climate Checkpoint - ${Date.now()}`;

  // TEST 1: Solo Mode — Upload, Analyze & Save
  test('1. Solo Mode: Analyze Climate Data & Save State', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Climate Anomaly Detector');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, 'HTTP GET/POST');

    // Upload sensor data
    const csvPath = createSensorCsv();
    await frame.locator('input[type="file"]').setInputFiles(csvPath);

    // Click analyze
    await frame.locator('button#process_data').click();

    // Verify processed summary appears (should show SiteID column)
    await expect(frame.locator('text=SITE_A')).toBeVisible({ timeout: 30000 });

    // Verify "Analysis triggered by" text
    await expect(frame.locator('text=alice')).toBeVisible({ timeout: 10000 });

    // Save state
    await saveState(page, sharedSaveName);

    // Verify in saved-apps
    await page.goto('/saved-apps');
    await expect(page.locator(`text=${sharedSaveName}`)).toBeVisible();

    fs.unlinkSync(csvPath);
  });

  // TEST 2: Real-Time Collaborative Sync
  test('2. Collab Mode: Real-Time Synchronization', async ({ browser }) => {
    const aliceCtx = await browser.newContext();
    const bobCtx = await browser.newContext();
    const alicePage = await aliceCtx.newPage();
    const bobPage = await bobCtx.newPage();

    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Climate Anomaly Detector', 'Climate Sync Test');

    await login(bobPage, 'bob');
    await joinCollabSession(bobPage, sessionId);

    const aliceFrame = alicePage.frameLocator('iframe');
    const bobFrame = bobPage.frameLocator('iframe');
    await waitForShinyBoot(aliceFrame, 'HTTP GET/POST');
    await waitForShinyBoot(bobFrame, 'HTTP GET/POST');

    // Alice uploads and analyzes
    const csvPath = createSensorCsv();
    await aliceFrame.locator('input[type="file"]').setInputFiles(csvPath);
    await aliceFrame.locator('button#process_data').click();

    // Alice sees results
    await expect(aliceFrame.locator('text=SITE_A')).toBeVisible({ timeout: 30000 });

    // Bob's UI polls and sees the same results
    await expect(bobFrame.locator('text=SITE_A')).toBeVisible({ timeout: 15000 });

    fs.unlinkSync(csvPath);
    await aliceCtx.close();
    await bobCtx.close();
  });

  // TEST 3: Permission Enforcement
  test('3. Security: Role-Based UI Locking', async ({ browser }) => {
    const aliceCtx = await browser.newContext();
    const charlieCtx = await browser.newContext();
    const alicePage = await aliceCtx.newPage();
    const charliePage = await charlieCtx.newPage();

    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Climate Anomaly Detector', 'Climate Security Test');

    await login(charliePage, 'charlie');
    await joinCollabSession(charliePage, sessionId);

    const charlieFrame = charliePage.frameLocator('iframe');
    await waitForShinyBoot(charlieFrame, 'HTTP GET/POST');

    // Charlie starts as Editor
    await expect(charlieFrame.locator('button#process_data')).toBeEnabled();

    // Alice demotes Charlie
    await demoteUser(alicePage, 'charlie');

    // Charlie's controls lock
    await expect(charlieFrame.locator('button#process_data')).toBeDisabled({ timeout: 10000 });

    await aliceCtx.close();
    await charlieCtx.close();
  });

  // TEST 4: Time Machine — Restore Checkpoint
  test('4. Time Machine: Restoring Historical States', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Climate Anomaly Detector');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, 'HTTP GET/POST');

    // Default: shows "Awaiting Data..."
    await expect(frame.locator('text=Awaiting Data')).toBeVisible();

    // Load checkpoint from Test 1
    await page.click('button:has-text("Load Checkpoint")');
    await page.locator(`text=${sharedSaveName}`).click();
    page.once('dialog', dialog => dialog.accept());
    await page.click('button:has-text("Load")');

    // Verify restored data appears
    await expect(frame.locator('text=SITE_A')).toBeVisible({ timeout: 15000 });
  });
});
