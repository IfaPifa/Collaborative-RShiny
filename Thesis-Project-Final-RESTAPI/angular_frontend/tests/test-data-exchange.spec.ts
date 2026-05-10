import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession, launchSolo, waitForShinyBoot, saveState, demoteUser } from './helpers';
import path from 'path';
import fs from 'fs';

// Create a small test CSV file for upload
function createTestCsv(): string {
  const csvPath = path.join(__dirname, 'test-data.csv');
  fs.writeFileSync(csvPath, 'Name,City,Score\nalice,basel,95\nbob,zurich,88\ncharlie,bern,72\n');
  return csvPath;
}

test.describe('Data Exchange: Core Four Matrix (REST)', () => {
  test.setTimeout(60000);
  const sharedSaveName = `CSV Checkpoint - ${Date.now()}`;

  // TEST 1: Solo Mode — Upload, Process & Save
  test('1. Solo Mode: Upload CSV & Save State', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Data Exchange');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, 'HTTP GET/POST');

    // Upload test CSV
    const csvPath = createTestCsv();
    const fileInput = frame.locator('input[type="file"]');
    await fileInput.setInputFiles(csvPath);

    // Click process
    await frame.locator('button#process_data').click();

    // Verify cleaned data appears in the table (uppercase transformation)
    await expect(frame.locator('text=ALICE').first()).toBeVisible({ timeout: 15000 });
    await expect(frame.locator('text=BASEL')).toBeVisible();

    // Save state
    await saveState(page, sharedSaveName);


    // Cleanup
    fs.unlinkSync(csvPath);
  });

  // TEST 2: Real-Time Collaborative Sync
  test('2. Collab Mode: Real-Time Synchronization', async ({ browser }) => {
    const aliceCtx = await browser.newContext();
    const bobCtx = await browser.newContext();
    const alicePage = await aliceCtx.newPage();
    const bobPage = await bobCtx.newPage();

    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Data Exchange', 'CSV Sync Test');

    await login(bobPage, 'bob');
    await joinCollabSession(bobPage, sessionId);

    const aliceFrame = alicePage.frameLocator('iframe');
    const bobFrame = bobPage.frameLocator('iframe');
    await waitForShinyBoot(aliceFrame, 'HTTP GET/POST');
    await waitForShinyBoot(bobFrame, 'HTTP GET/POST');

    // Alice uploads and processes
    const csvPath = createTestCsv();
    await aliceFrame.locator('input[type="file"]').setInputFiles(csvPath);
    await aliceFrame.locator('button#process_data').click();

    // Alice sees cleaned data
    await expect(aliceFrame.locator('text=ALICE').first()).toBeVisible({ timeout: 15000 });

    // Bob's UI polls and sees the same cleaned data
    await expect(bobFrame.locator('text=ALICE').first()).toBeVisible({ timeout: 15000 });
    await expect(bobFrame.locator('text=BASEL')).toBeVisible();

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
    const sessionId = await createCollabSession(alicePage, 'Data Exchange', 'CSV Security Test');

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
    await launchSolo(page, 'Data Exchange');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, 'HTTP GET/POST');

    // Load the most recent checkpoint (saved in Test 1)
    await page.click('button:has-text("Load Checkpoint")');
    const modal = page.locator('app-modal');
    await expect(modal.getByRole('heading', { name: 'Load Checkpoint' })).toBeVisible({ timeout: 5000 });
    page.once('dialog', dialog => dialog.accept());
    await modal.getByRole('button', { name: 'Load', exact: true }).first().click();

    // Verify restored data appears
    await expect(frame.locator('text=ALICE').first()).toBeVisible({ timeout: 10000 });
  });
});

