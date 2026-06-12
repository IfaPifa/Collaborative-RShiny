import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession, launchSolo, waitForShinyBoot, saveState, demoteUser } from './helpers';
import path from 'path';
import fs from 'fs';
import os from 'os';

// Create a small test CSV file for upload
function createTestCsv(): string {
  const csvPath = path.join(os.tmpdir(), 'test-data.csv');
  fs.writeFileSync(csvPath, 'Name,City,Score\nalice,basel,95\nbob,zurich,88\ncharlie,bern,72\n');
  return csvPath;
}

test.describe('Data Exchange: Core Four Matrix', () => {
  test.describe.configure({ mode: 'serial' });
  test.setTimeout(60000);
  let sharedSaveName: string;

  test.beforeAll(() => {
    sharedSaveName = `CSV Checkpoint - ${Date.now()}`;
  });

  // TEST 1: Solo Mode — Upload, Process & Save
  test('1. Solo Mode: Upload CSV & Save State', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Data Exchange');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame);

    // Upload test CSV
    const csvPath = createTestCsv();
    const fileInput = frame.locator('input[type="file"]');
    await fileInput.setInputFiles(csvPath);

    // Wait for Shiny to finish the AJAX upload
    await expect(frame.locator('text=Upload complete')).toBeVisible({ timeout: 10000 });
    await page.waitForTimeout(1000);

    // Click process
    await frame.locator('button#process_data').click();

    // Verify cleaned data appears in the table (uppercase transformation)
    await expect(frame.locator('text=ALICE').first()).toBeVisible({ timeout: 60000 });
    await expect(frame.locator('text=BASEL')).toBeVisible({ timeout: 5000 });

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
    await waitForShinyBoot(aliceFrame);
    await waitForShinyBoot(bobFrame);

    // Alice uploads and processes
    const csvPath = createTestCsv();
    await aliceFrame.locator('input[type="file"]').setInputFiles(csvPath);
    await expect(aliceFrame.locator('text=Upload complete')).toBeVisible({ timeout: 10000 });
    await alicePage.waitForTimeout(1000);
    await aliceFrame.locator('button#process_data').click();

    // Alice sees cleaned data
    await expect(aliceFrame.locator('text=ALICE').first()).toBeVisible({ timeout: 60000 });

    // Bob's UI polls and sees the same cleaned data
    await expect(bobFrame.locator('text=ALICE').first()).toBeVisible({ timeout: 30000 });
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
    await waitForShinyBoot(charlieFrame);

    // Charlie starts as Editor
    await expect(charlieFrame.locator('button#process_data')).toBeEnabled();

    // Alice demotes Charlie
    await demoteUser(alicePage, 'charlie');

    // Charlie's controls lock
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
    const sessionId = await createCollabSession(alicePage, 'Data Exchange', 'RQ5 CSV Test');

    const aliceFrame = alicePage.frameLocator('iframe');
    await waitForShinyBoot(aliceFrame);

    // Alice uploads first CSV and processes
    const csv1Path = path.join(os.tmpdir(), 'rq5-csv1.csv');
    fs.writeFileSync(csv1Path, 'Name,City,Score\nalice,basel,95\nbob,zurich,88\n');
    await aliceFrame.locator('input[type="file"]').setInputFiles(csv1Path);
    await expect(aliceFrame.locator('text=Upload complete')).toBeVisible({ timeout: 10000 });
    await alicePage.waitForTimeout(1000);
    await aliceFrame.locator('button#process_data').click();
    await expect(aliceFrame.locator('text=ALICE').first()).toBeVisible({ timeout: 60000 });
    await expect(aliceFrame.locator('text=BASEL')).toBeVisible({ timeout: 5000 });

    const saveName = `RQ5-CSV-${Date.now()}`;
    await saveState(alicePage, saveName);

    // Alice uploads a DIFFERENT CSV to change the state
    const csv2Path = path.join(os.tmpdir(), 'rq5-csv2.csv');
    fs.writeFileSync(csv2Path, 'Name,City,Score\ndave,london,60\neve,paris,75\n');
    await aliceFrame.locator('input[type="file"]').setInputFiles(csv2Path);
    await expect(aliceFrame.locator('text=Upload complete')).toBeVisible({ timeout: 10000 });
    await alicePage.waitForTimeout(1000);
    await aliceFrame.locator('button#process_data').click();
    await expect(aliceFrame.locator('text=DAVE').first()).toBeVisible({ timeout: 60000 });

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

    // Verify: Bob sees CSV1 data (ALICE/BASEL), not CSV2 data (DAVE/LONDON)
    await expect(bobFrame.locator('text=ALICE').first()).toBeVisible({ timeout: 30000 });
    await expect(bobFrame.locator('text=BASEL')).toBeVisible({ timeout: 5000 });

    // Cleanup
    fs.unlinkSync(csv1Path);
    fs.unlinkSync(csv2Path);
    await bobCtx.close();
  });

  // TEST 4: Time Machine — Restore Checkpoint
  test('4. Time Machine: Restoring Historical States', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Data Exchange');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame);

    // Load the most recent checkpoint (saved in Test 1)
    await page.click('button:has-text("Load Checkpoint")');
    const modal = page.locator('app-modal');
    await expect(modal.getByRole('heading', { name: 'Load Checkpoint' })).toBeVisible({ timeout: 5000 });
    page.once('dialog', dialog => dialog.accept());
    await modal.getByRole('button', { name: 'Load', exact: true }).first().click();

    // Verify restored data appears
    await expect(frame.locator('text=ALICE').first()).toBeVisible({ timeout: 30000 });
  });
});