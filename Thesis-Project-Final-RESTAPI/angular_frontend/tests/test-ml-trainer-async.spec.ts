import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession, launchSolo, waitForShinyBoot, saveState, demoteUser } from './helpers';

test.describe('ML Trainer: Core Four Matrix (REST)', () => {
  test.setTimeout(90000); // Model training can take time
  const sharedSaveName = `ML Checkpoint - ${Date.now()}`;

  // TEST 1: Solo Mode — Train Model & Save
  test('1. Solo Mode: Train Model & Save State', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Habitat Suitability AI');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, 'HTTP GET/POST');

    // Use default 500 trees (slider can't be filled directly) and train
    await frame.locator('button#train_btn').click();

    // Wait for training to complete — feature importance chart renders
    // The plotly chart container will have data
    await expect(frame.locator('#importance_plot')).toBeVisible({ timeout: 60000 });

    // Verify button re-enables
    await expect(frame.locator('button#train_btn')).toBeEnabled();

    // Verify status shows COMPLETE
    await expect(frame.locator('text=COMPLETE')).toBeVisible();

    // Save state
    await saveState(page, sharedSaveName);

  });

  // TEST 2: Real-Time Collaborative Sync
  test('2. Collab Mode: Real-Time Synchronization', async ({ browser }) => {
    const aliceCtx = await browser.newContext();
    const bobCtx = await browser.newContext();
    const alicePage = await aliceCtx.newPage();
    const bobPage = await bobCtx.newPage();

    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Habitat Suitability AI', 'ML Sync Test');

    await login(bobPage, 'bob');
    await joinCollabSession(bobPage, sessionId);

    const aliceFrame = alicePage.frameLocator('iframe');
    const bobFrame = bobPage.frameLocator('iframe');
    await waitForShinyBoot(aliceFrame, 'HTTP GET/POST');
    await waitForShinyBoot(bobFrame, 'HTTP GET/POST');

    // Alice trains model
    await aliceFrame.locator('button#train_btn').click();

    // Alice sees results
    await expect(aliceFrame.locator('#importance_plot')).toBeVisible({ timeout: 60000 });

    // Bob's UI polls and sees the results too
    await expect(bobFrame.locator('#importance_plot')).toBeVisible({ timeout: 15000 });
    await expect(bobFrame.locator('text=COMPLETE')).toBeVisible();

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
    const sessionId = await createCollabSession(alicePage, 'Habitat Suitability AI', 'ML Security Test');

    await login(charliePage, 'charlie');
    await joinCollabSession(charliePage, sessionId);

    const charlieFrame = charliePage.frameLocator('iframe');
    await waitForShinyBoot(charlieFrame, 'HTTP GET/POST');

    // Charlie starts as Editor
    await expect(charlieFrame.locator('button#train_btn')).toBeEnabled();

    // Alice demotes Charlie
    await demoteUser(alicePage, 'charlie');

    // Charlie's controls lock
    await expect(charlieFrame.locator('button#train_btn')).toBeDisabled({ timeout: 10000 });
    await expect(charlieFrame.locator('#trees')).toBeDisabled();

    await aliceCtx.close();
    await charlieCtx.close();
  });

  // TEST 4: Time Machine — Restore Checkpoint
  test('4. Time Machine: Restoring Historical States', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Habitat Suitability AI');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, 'HTTP GET/POST');

    // Load the most recent checkpoint (saved in Test 1)
    await page.click('button:has-text("Load Checkpoint")');
    const modal = page.locator('app-modal');
    await expect(modal.getByRole('heading', { name: 'Load Checkpoint' })).toBeVisible({ timeout: 5000 });
    page.once('dialog', dialog => dialog.accept());
    await modal.getByRole('button', { name: 'Load', exact: true }).first().click();

    // Verify restored results — plotly chart appears
    await expect(frame.locator('#importance_plot')).toBeVisible({ timeout: 15000 });
  });
});



