import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession, launchSolo, waitForShinyBoot, saveState, demoteUser } from './helpers';
import path from 'path';
import fs from 'fs';
import os from 'os';

function createSensorCsv(): string {
  const csvPath = path.join(os.tmpdir(), 'test-sensor-data.csv');
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

test.describe('Climate Anomaly Detector: Core Four Matrix', () => {
  test.describe.configure({ mode: 'serial' });
  test.setTimeout(90000);
  let sharedSaveName: string;

  test.beforeAll(() => {
    sharedSaveName = `Climate Checkpoint - ${Date.now()}`;
  });

  test('1. Solo Mode: Analyze Climate Data & Save State', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Climate Anomaly Detector');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame);

    const csvPath = createSensorCsv();
    await frame.locator('input[type="file"]').setInputFiles(csvPath);

    // SHINY FIX: Wait 1.5 seconds for the AJAX upload to reach 100% before clicking!
    await page.waitForTimeout(1500);

    await frame.locator('button#process_data').click();

    await expect(frame.locator('text=SITE_A').first()).toBeVisible({ timeout: 60000 });
    await expect(frame.locator('text=Analysis triggered by')).toBeVisible({ timeout: 15000 });

    await saveState(page, sharedSaveName);
    fs.unlinkSync(csvPath);
  });

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
    await waitForShinyBoot(aliceFrame);
    await waitForShinyBoot(bobFrame);

    const csvPath = createSensorCsv();
    await aliceFrame.locator('input[type="file"]').setInputFiles(csvPath);
    
    // SHINY FIX: Wait for upload in Collab mode too
    await alicePage.waitForTimeout(1500); 
    
    await aliceFrame.locator('button#process_data').click();

    await expect(aliceFrame.locator('text=SITE_A').first()).toBeVisible({ timeout: 60000 });
    await expect(bobFrame.locator('text=SITE_A').first()).toBeVisible({ timeout: 30000 });

    fs.unlinkSync(csvPath);
    await aliceCtx.close();
    await bobCtx.close();
  });

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
    await waitForShinyBoot(charlieFrame);

    await expect(charlieFrame.locator('button#process_data')).toBeEnabled();
    await demoteUser(alicePage, 'charlie');
    await expect(charlieFrame.locator('button#process_data')).toBeDisabled({ timeout: 10000 });

    await aliceCtx.close();
    await charlieCtx.close();
  });

  // TEST 5: RQ5 — Cross-User Checkpoint Restore
  test('5. RQ5: Cross-User Checkpoint Restore', async ({ browser }) => {
    const aliceCtx = await browser.newContext();
    const bobCtx = await browser.newContext();
    const alicePage = await aliceCtx.newPage();
    const bobPage = await bobCtx.newPage();

    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Climate Anomaly Detector', 'RQ5 Climate Test');

    const aliceFrame = alicePage.frameLocator('iframe');
    await waitForShinyBoot(aliceFrame);

    // Alice uploads first sensor CSV (SITE_A, SITE_B) and processes
    const csv1Path = createSensorCsv();
    await aliceFrame.locator('input[type="file"]').setInputFiles(csv1Path);
    await alicePage.waitForTimeout(1500);
    await aliceFrame.locator('button#process_data').click();
    await expect(aliceFrame.locator('text=SITE_A').first()).toBeVisible({ timeout: 60000 });

    const saveName = `RQ5-Climate-${Date.now()}`;
    await saveState(alicePage, saveName);

    // Alice uploads a DIFFERENT CSV with different site names
    const csv2Path = path.join(os.tmpdir(), 'rq5-climate2.csv');
    const rows2 = ['Timestamp,SiteID,Temperature,SoilMoisture'];
    for (let day = 1; day <= 5; day++) {
      rows2.push(`2026-06-${String(day).padStart(2, '0')} 12:00:00,SITE_X,${(30 + Math.random() * 5).toFixed(1)},${(40 + Math.random() * 10).toFixed(1)}`);
      rows2.push(`2026-06-${String(day).padStart(2, '0')} 12:00:00,SITE_Y,${(20 + Math.random() * 5).toFixed(1)},${(50 + Math.random() * 10).toFixed(1)}`);
    }
    fs.writeFileSync(csv2Path, rows2.join('\n'));
    await aliceFrame.locator('input[type="file"]').setInputFiles(csv2Path);
    await alicePage.waitForTimeout(1500);
    await aliceFrame.locator('button#process_data').click();
    await expect(aliceFrame.locator('text=SITE_X').first()).toBeVisible({ timeout: 60000 });

    // Alice leaves
    await alicePage.click('button:has-text("Exit")');
    await alicePage.waitForURL('**/library');
    await aliceCtx.close();

    // Bob joins and restores
    await login(bobPage, 'bob');
    await joinCollabSession(bobPage, sessionId);
    const bobFrame = bobPage.frameLocator('iframe');
    await waitForShinyBoot(bobFrame);

    await bobPage.click('button:has-text("Load Checkpoint")');
    const modal = bobPage.locator('app-modal');
    await expect(modal.getByRole('heading', { name: 'Load Checkpoint' })).toBeVisible({ timeout: 5000 });

    const checkpointRow = modal.locator('div.flex.justify-between').filter({ hasText: saveName });
    await expect(checkpointRow).toBeVisible({ timeout: 10000 });
    await expect(checkpointRow.locator('text=by alice')).toBeVisible();

    bobPage.once('dialog', dialog => dialog.accept());
    await checkpointRow.getByRole('button', { name: 'Load' }).click();

    // Verify: Bob sees SITE_A (saved state), not SITE_X (Alice's later upload)
    await expect(bobFrame.locator('text=SITE_A').first()).toBeVisible({ timeout: 60000 });

    // Cleanup
    fs.unlinkSync(csv1Path);
    fs.unlinkSync(csv2Path);
    await bobCtx.close();
  });

  test('4. Time Machine: Restoring Historical States', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Climate Anomaly Detector');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame);

    await page.click('button:has-text("Load Checkpoint")');
    const modal = page.locator('app-modal');
    await expect(modal.getByRole('heading', { name: 'Load Checkpoint' })).toBeVisible({ timeout: 5000 });
    page.once('dialog', dialog => dialog.accept());
    await modal.getByRole('button', { name: 'Load', exact: true }).first().click();

    await expect(frame.locator('text=SITE_A').first()).toBeVisible({ timeout: 60000 });
  });
});