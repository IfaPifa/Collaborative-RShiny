import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession, launchSolo, waitForShinyBoot, saveState, demoteUser } from './helpers';

test.describe('Monte Carlo Simulator: Core Four Matrix (REST)', () => {
  test.setTimeout(90000); // Simulations can take time
  const sharedSaveName = `MC Checkpoint - ${Date.now()}`;

  // TEST 1: Solo Mode — Run Simulation & Save
  test('1. Solo Mode: Run Simulation & Save State', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Monte Carlo Simulator');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, 'HTTP GET/POST');

    // Set parameters and launch
    await frame.locator('#n0').fill('200');
    await frame.locator('button#run_sim').click();

    // Wait for the simulation to complete — Extinction Risk KPI appears
    await expect(frame.locator('text=Extinction Risk')).toBeVisible({ timeout: 45000 });

    // Verify button re-enables
    await expect(frame.locator('button#run_sim')).toBeEnabled();

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
    const sessionId = await createCollabSession(alicePage, 'Monte Carlo Simulator', 'MC Sync Test');

    await login(bobPage, 'bob');
    await joinCollabSession(bobPage, sessionId);

    const aliceFrame = alicePage.frameLocator('iframe');
    const bobFrame = bobPage.frameLocator('iframe');
    await waitForShinyBoot(aliceFrame, 'HTTP GET/POST');
    await waitForShinyBoot(bobFrame, 'HTTP GET/POST');

    // Alice runs simulation
    await aliceFrame.locator('button#run_sim').click();

    // Alice sees result
    await expect(aliceFrame.locator('text=Extinction Risk')).toBeVisible({ timeout: 45000 });

    // Bob's UI polls and sees the result too
    await expect(bobFrame.locator('text=Extinction Risk')).toBeVisible({ timeout: 15000 });

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
    const sessionId = await createCollabSession(alicePage, 'Monte Carlo Simulator', 'MC Security Test');

    await login(charliePage, 'charlie');
    await joinCollabSession(charliePage, sessionId);

    const charlieFrame = charliePage.frameLocator('iframe');
    await waitForShinyBoot(charlieFrame, 'HTTP GET/POST');

    // Charlie starts as Editor
    await expect(charlieFrame.locator('button#run_sim')).toBeEnabled();

    // Alice demotes Charlie
    await demoteUser(alicePage, 'charlie');

    // Charlie's controls lock
    await expect(charlieFrame.locator('button#run_sim')).toBeDisabled({ timeout: 10000 });
    await expect(charlieFrame.locator('#n0')).toBeDisabled();

    await aliceCtx.close();
    await charlieCtx.close();
  });

  // TEST 4: Time Machine — Restore Checkpoint
  test('4. Time Machine: Restoring Historical States', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Monte Carlo Simulator');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, 'HTTP GET/POST');

    // Load the most recent checkpoint (saved in Test 1)
    await page.click('button:has-text("Load Checkpoint")');
    const modal = page.locator('app-modal');
    await expect(modal.getByRole('heading', { name: 'Load Checkpoint' })).toBeVisible({ timeout: 5000 });
    page.once('dialog', dialog => dialog.accept());
    await modal.getByRole('button', { name: 'Load', exact: true }).first().click();

    // Verify restored results appear
    await expect(frame.locator('text=Extinction Risk')).toBeVisible({ timeout: 15000 });
  });
});