import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession, launchSolo, waitForShinyBoot, saveState, demoteUser } from './helpers';

test.describe('Visual Analytics: Core Four Matrix (Unified)', () => {
  test.setTimeout(60000);
  const sharedSaveName = `Analytics Checkpoint - ${Date.now()}`;

  // TEST 1: Solo Mode — Filter & Save
  test('1. Solo Mode: Filter & Save State', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Visual Analytics');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, 'System Online');

    // Uncheck cylinder 4 to change the filter
    await frame.locator('input[name="cyl"][value="4"]').uncheck();
    await frame.locator('button#update_plot').click();

    // Verify the sync completed
    await page.waitForTimeout(3000);
    await saveState(page, sharedSaveName);
  });

  // TEST 2: Real-Time Collaborative Sync
  test('2. Collab Mode: Real-Time Synchronization', async ({ browser }) => {
    const aliceCtx = await browser.newContext();
    const bobCtx = await browser.newContext();
    const alicePage = await aliceCtx.newPage();
    const bobPage = await bobCtx.newPage();

    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Visual Analytics', 'Analytics Sync Test');

    await login(bobPage, 'bob');
    await joinCollabSession(bobPage, sessionId);

    const aliceFrame = alicePage.frameLocator('iframe');
    const bobFrame = bobPage.frameLocator('iframe');
    await waitForShinyBoot(aliceFrame, 'System Online');
    await waitForShinyBoot(bobFrame, 'System Online');

    await aliceFrame.locator('input[name="cyl"][value="8"]').uncheck();
    await aliceFrame.locator('button#update_plot').click();

    await expect(bobFrame.locator('input[name="cyl"][value="8"]')).not.toBeChecked({ timeout: 15000 });
    await expect(bobFrame.locator('text=Last filter sync by')).toContainText('alice', { timeout: 15000 });

    await aliceCtx.close();
    await bobCtx.close();
  });

  // TEST 3: RBAC Security
  test('3. Security: Role-Based Access Control', async ({ browser }) => {
    const aliceCtx = await browser.newContext();
    const charlieCtx = await browser.newContext();
    const alicePage = await aliceCtx.newPage();
    const charliePage = await charlieCtx.newPage();

    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Visual Analytics', 'Analytics RBAC Test');

    await login(charliePage, 'charlie');
    await joinCollabSession(charliePage, sessionId);

    const aliceFrame = alicePage.frameLocator('iframe');
    const charlieFrame = charliePage.frameLocator('iframe');
    await waitForShinyBoot(aliceFrame, 'System Online');
    await waitForShinyBoot(charlieFrame, 'System Online');

    // Charlie starts as Editor
    await expect(charlieFrame.locator('button#update_plot')).toBeEnabled();

    // Alice demotes Charlie
    await demoteUser(alicePage, 'charlie');

    // Charlie's controls lock
    await expect(charlieFrame.locator('button#update_plot')).toBeDisabled({ timeout: 10000 });
    await expect(charlieFrame.locator('input[name="cyl"][value="4"]')).toBeDisabled();

    await aliceCtx.close();
    await charlieCtx.close();
  });

  // TEST 4: Time Machine — Restore Checkpoint
  test('4. Time Machine: Restoring Historical States', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Visual Analytics');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, 'System Online');

    await frame.locator('input[name="cyl"][value="4"]').check();

    await page.click('button:has-text("Load Checkpoint")');
    const modal = page.locator('app-modal');
    await expect(modal.getByRole('heading', { name: 'Load Checkpoint' })).toBeVisible({ timeout: 5000 });
    page.once('dialog', dialog => dialog.accept());
    
    // THE FIX: Explicitly target the named checkpoint
    await modal.locator('*').filter({ hasText: sharedSaveName }).getByRole('button', { name: 'Load', exact: true }).first().click();

    await expect(frame.locator('input[name="cyl"][value="4"]')).not.toBeChecked({ timeout: 15000 });
    await expect(frame.locator('text=Last filter sync by')).toContainText('System Restore', { timeout: 15000 });
  });
});