import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession, launchSolo, waitForShinyBoot, saveState, demoteUser } from './helpers';
import path from 'path';
import fs from 'fs';

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

test.describe('Climate Anomaly Detector: Core Four Matrix', () => {
  test.setTimeout(90000);
  const sharedSaveName = `Climate Checkpoint - ${Date.now()}`;

  test('1. Solo Mode: Analyze Climate Data & Save State', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Climate Anomaly Detector');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, '🟢 System Online');

    const csvPath = createSensorCsv();
    await frame.locator('input[type="file"]').setInputFiles(csvPath);

    // SHINY FIX: Wait 1.5 seconds for the AJAX upload to reach 100% before clicking!
    await page.waitForTimeout(1500);

    await frame.locator('button#process_data').click();

    await expect(frame.locator('text=SITE_A').first()).toBeVisible({ timeout: 30000 });
    await expect(frame.locator('text=Analysis triggered by')).toBeVisible({ timeout: 10000 });

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
    await waitForShinyBoot(aliceFrame, '🟢 System Online');
    await waitForShinyBoot(bobFrame, '🟢 System Online');

    const csvPath = createSensorCsv();
    await aliceFrame.locator('input[type="file"]').setInputFiles(csvPath);
    
    // SHINY FIX: Wait for upload in Collab mode too
    await alicePage.waitForTimeout(1500); 
    
    await aliceFrame.locator('button#process_data').click();

    await expect(aliceFrame.locator('text=SITE_A').first()).toBeVisible({ timeout: 30000 });
    await expect(bobFrame.locator('text=SITE_A').first()).toBeVisible({ timeout: 15000 });

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
    await waitForShinyBoot(charlieFrame, '🟢 System Online');

    await expect(charlieFrame.locator('button#process_data')).toBeEnabled();
    await demoteUser(alicePage, 'charlie');
    await expect(charlieFrame.locator('button#process_data')).toBeDisabled({ timeout: 10000 });

    await aliceCtx.close();
    await charlieCtx.close();
  });

  test('4. Time Machine: Restoring Historical States', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Climate Anomaly Detector');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, '🟢 System Online');

    await page.click('button:has-text("Load Checkpoint")');
    const modal = page.locator('app-modal');
    await expect(modal.getByRole('heading', { name: 'Load Checkpoint' })).toBeVisible({ timeout: 5000 });
    page.once('dialog', dialog => dialog.accept());
    await modal.getByRole('button', { name: 'Load', exact: true }).first().click();

    await expect(frame.locator('text=SITE_A').first()).toBeVisible({ timeout: 15000 });
  });
});