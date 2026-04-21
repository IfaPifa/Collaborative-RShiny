import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession, launchSolo, waitForShinyBoot, saveState, demoteUser } from './helpers';

test.describe('Advanced Analytics: Core Four Matrix (REST)', () => {
  test.setTimeout(60000);
  const sharedSaveName = `Adv Analytics Checkpoint - ${Date.now()}`;

  // TEST 1: Solo Mode — Filter & Save
  test('1. Solo Mode: Compute & Save State', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Advanced Visual Analytics');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame);

    // Uncheck May and sync
    await frame.locator('input[name="months"][value="5"]').uncheck();
    await frame.locator('button#update_plot').click();

    // Verify May stays unchecked after sync
    await expect(frame.locator('input[name="months"][value="5"]')).not.toBeChecked({ timeout: 10000 });

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
    const sessionId = await createCollabSession(alicePage, 'Advanced Visual Analytics', 'Adv Analytics Sync Test');

    await login(bobPage, 'bob');
    await joinCollabSession(bobPage, sessionId);

    const aliceFrame = alicePage.frameLocator('iframe');
    const bobFrame = bobPage.frameLocator('iframe');
    await waitForShinyBoot(aliceFrame);
    await waitForShinyBoot(bobFrame);

    // Alice unchecks May and syncs
    await aliceFrame.locator('input[name="months"][value="5"]').uncheck();
    await aliceFrame.locator('button#update_plot').click();

    // Bob's UI polls and May becomes unchecked
    await expect(bobFrame.locator('input[name="months"][value="5"]')).not.toBeChecked({ timeout: 15000 });

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
    const sessionId = await createCollabSession(alicePage, 'Advanced Visual Analytics', 'Adv Analytics Security Test');

    await login(charliePage, 'charlie');
    await joinCollabSession(charliePage, sessionId);

    const charlieFrame = charliePage.frameLocator('iframe');
    await waitForShinyBoot(charlieFrame);

    // Charlie starts as Editor
    await expect(charlieFrame.locator('button#update_plot')).toBeEnabled();

    // Alice demotes Charlie
    await demoteUser(alicePage, 'charlie');

    // Charlie's controls lock
    await expect(charlieFrame.locator('button#update_plot')).toBeDisabled({ timeout: 10000 });
    await expect(charlieFrame.locator('input[name="months"][value="5"]')).toBeDisabled();

    await aliceCtx.close();
    await charlieCtx.close();
  });

  // TEST 4: Time Machine — Restore Checkpoint
  test('4. Time Machine: Restoring Historical States', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Advanced Visual Analytics');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame);

    // Ensure May is checked (set a known different state before restoring)
    await frame.locator('input[name="months"][value="5"]').check();

    // Load the most recent checkpoint (saved in Test 1, where May was unchecked)
    await page.click('button:has-text("Load Checkpoint")');
    const modal = page.locator('app-modal');
    await expect(modal.getByRole('heading', { name: 'Load Checkpoint' })).toBeVisible({ timeout: 5000 });
    page.once('dialog', dialog => dialog.accept());
    await modal.getByRole('button', { name: 'Load', exact: true }).first().click();

    // Verify May is now unchecked
    await expect(frame.locator('input[name="months"][value="5"]')).not.toBeChecked({ timeout: 10000 });
  });
});

