import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession, launchSolo, waitForShinyBoot, saveState, demoteUser } from './helpers';

test.describe('Calculator: Core Four Matrix (REST)', () => {
  test.setTimeout(60000);
  const sharedSaveName = `Calc Checkpoint - ${Date.now()}`;

  // TEST 1: Solo Mode — Compute & Save
  test('1. Solo Mode: Compute & Save State', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Collaborative Calculator');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame);

    // Interact: set inputs and calculate
    await frame.locator('#num1').fill('10');
    await frame.locator('#num2').fill('25');
    await frame.locator('button#calculate').click();

    // Verify result rendered
    await expect(frame.locator('#result')).toHaveText('35', { timeout: 15000 });

    // Save state
    await saveState(page, sharedSaveName);

    // Verify in saved-apps
    await page.goto('/saved-apps');
    await expect(page.locator(`text=${sharedSaveName}`)).toBeVisible();
  });

  // TEST 2: Real-Time Collaborative Sync
  test('2. Collab Mode: Real-Time Synchronization', async ({ browser }) => {
    const aliceCtx = await browser.newContext();
    const bobCtx = await browser.newContext();
    const alicePage = await aliceCtx.newPage();
    const bobPage = await bobCtx.newPage();

    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Collaborative Calculator', 'Calc Sync Test');

    await login(bobPage, 'bob');
    await joinCollabSession(bobPage, sessionId);

    const aliceFrame = alicePage.frameLocator('iframe');
    const bobFrame = bobPage.frameLocator('iframe');
    await waitForShinyBoot(aliceFrame);
    await waitForShinyBoot(bobFrame);

    // Alice calculates
    await aliceFrame.locator('#num1').fill('42');
    await aliceFrame.locator('#num2').fill('8');
    await aliceFrame.locator('button#calculate').click();

    // Alice sees result
    await expect(aliceFrame.locator('#result')).toHaveText('50', { timeout: 15000 });

    // Bob's UI polls and updates
    await expect(bobFrame.locator('#num1')).toHaveValue('42', { timeout: 15000 });
    await expect(bobFrame.locator('#num2')).toHaveValue('8', { timeout: 15000 });
    await expect(bobFrame.locator('#result')).toHaveText('50', { timeout: 15000 });

    await aliceCtx.close();
    await bobCtx.close();
  });

  // TEST 3: Permission Enforcement — Real-Time Demotion
  test('3. Security: Role-Based UI Locking', async ({ browser }) => {
    const aliceCtx = await browser.newContext();
    const charlieCtx = await browser.newContext();
    const alicePage = await aliceCtx.newPage();
    const charliePage = await charlieCtx.newPage();

    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Collaborative Calculator', 'Calc Security Test');

    await login(charliePage, 'charlie');
    await joinCollabSession(charliePage, sessionId);

    const charlieFrame = charliePage.frameLocator('iframe');
    await waitForShinyBoot(charlieFrame);

    // Charlie starts as Editor — controls enabled
    await expect(charlieFrame.locator('button#calculate')).toBeEnabled();

    // Alice demotes Charlie
    await demoteUser(alicePage, 'charlie');

    // Charlie's controls lock
    await expect(charlieFrame.locator('button#calculate')).toBeDisabled({ timeout: 10000 });
    await expect(charlieFrame.locator('#num1')).toBeDisabled();
    await expect(charlieFrame.locator('#num2')).toBeDisabled();

    await aliceCtx.close();
    await charlieCtx.close();
  });

  // TEST 4: Time Machine — Restore Checkpoint
  test('4. Time Machine: Restoring Historical States', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Collaborative Calculator');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame);

    // Default state: num1=0, num2=0
    await expect(frame.locator('#num1')).toHaveValue('0');

    // Load the checkpoint from Test 1
    await page.click('button:has-text("Load Checkpoint")');
    await page.locator(`text=${sharedSaveName}`).click();
    page.once('dialog', dialog => dialog.accept());
    await page.click('button:has-text("Load")');

    // Verify restored state
    await expect(frame.locator('#num1')).toHaveValue('10', { timeout: 10000 });
    await expect(frame.locator('#num2')).toHaveValue('25', { timeout: 10000 });
  });
});
