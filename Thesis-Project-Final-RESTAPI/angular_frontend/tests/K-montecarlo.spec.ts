import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession, launchSolo, waitForShinyBoot, saveState, demoteUser, setShinyNumericInput } from './helpers';

test.describe('Monte Carlo Simulator: Core Four Matrix', () => {
  test.describe.configure({ mode: 'serial' });
  test.setTimeout(90000); // Simulations can take time
  let sharedSaveName: string;

  test.beforeAll(() => {
    sharedSaveName = `MC Checkpoint - ${Date.now()}`;
  });

  // TEST 1: Solo Mode — Run Simulation & Save
  test('1. Solo Mode: Run Simulation & Save State', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Monte Carlo Simulator');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame);

    // Set parameters and launch
    await setShinyNumericInput(frame, '#n0', '200');
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
    await waitForShinyBoot(aliceFrame);
    await waitForShinyBoot(bobFrame);

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
    await waitForShinyBoot(charlieFrame);

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

  // TEST 5: RQ5 — Cross-User Checkpoint Restore
  test('5. RQ5: Cross-User Checkpoint Restore', async ({ browser }) => {
    test.setTimeout(180000); // Two full simulations

    const aliceCtx = await browser.newContext();
    const bobCtx = await browser.newContext();
    const alicePage = await aliceCtx.newPage();
    const bobPage = await bobCtx.newPage();

    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Monte Carlo Simulator', 'RQ5 MC Test');

    const aliceFrame = alicePage.frameLocator('iframe');
    await waitForShinyBoot(aliceFrame);

    // Alice runs simulation with n0=200
    await setShinyNumericInput(aliceFrame, '#n0', '200');
    await aliceFrame.locator('button#run_sim').click();
    await expect(aliceFrame.locator('text=Extinction Risk')).toBeVisible({ timeout: 45000 });
    await expect(aliceFrame.locator('button#run_sim')).toBeEnabled();

    const saveName = `RQ5-MC-${Date.now()}`;
    await saveState(alicePage, saveName);

    // Alice runs a DIFFERENT simulation with n0=500
    await setShinyNumericInput(aliceFrame, '#n0', '500');
    await aliceFrame.locator('button#run_sim').click();
    await expect(aliceFrame.locator('text=Extinction Risk')).toBeVisible({ timeout: 45000 });
    await expect(aliceFrame.locator('button#run_sim')).toBeEnabled();

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

    // Verify: Bob sees n0=200 (saved state), not n0=500 (Alice's later run)
    await expect(bobFrame.locator('#n0')).toHaveValue('200', { timeout: 15000 });
    await expect(bobFrame.locator('text=Extinction Risk')).toBeVisible({ timeout: 15000 });

    await bobCtx.close();
  });

  // TEST 4: Time Machine — Restore Checkpoint
  test('4. Time Machine: Restoring Historical States', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Monte Carlo Simulator');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame);

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