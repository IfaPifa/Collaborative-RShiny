import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession, waitForShinyBoot, saveState, setShinyNumericInput } from './helpers';

/**
 * RQ5 — Reproducibility: Cross-User Checkpoint Restore
 *
 * Validates that a checkpoint saved by one user can be restored by
 * another user in the same collaboration session, producing an
 * identical application state without recomputation.
 */
test.describe('RQ5: Cross-User Checkpoint Restore', () => {
  test.setTimeout(120000);

  test('Alice saves checkpoint, Bob restores it — state matches exactly', async ({ browser }) => {
    const aliceCtx = await browser.newContext();
    const bobCtx = await browser.newContext();
    const alicePage = await aliceCtx.newPage();
    const bobPage = await bobCtx.newPage();

    // --- Alice: create session, compute, save ---
    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Collaborative Calculator', 'RQ5 Reproducibility Test');

    const aliceFrame = alicePage.frameLocator('iframe');
    await waitForShinyBoot(aliceFrame);

    await setShinyNumericInput(aliceFrame, '#num1', '42');
    await setShinyNumericInput(aliceFrame, '#num2', '58');
    await aliceFrame.locator('button#calculate').click();
    await expect(aliceFrame.locator('#result')).toHaveText('100', { timeout: 25000 });

    const saveName = `RQ5-Cross-User-${Date.now()}`;
    await saveState(alicePage, saveName);

    // --- Bob: join same session, restore Alice's checkpoint ---
    await login(bobPage, 'bob');
    await joinCollabSession(bobPage, sessionId);

    const bobFrame = bobPage.frameLocator('iframe');
    await waitForShinyBoot(bobFrame);

    // Bob opens Load Checkpoint modal
    await bobPage.click('button:has-text("Load Checkpoint")');
    const modal = bobPage.locator('app-modal');
    await expect(modal.getByRole('heading', { name: 'Load Checkpoint' })).toBeVisible({ timeout: 5000 });

    // Bob should see Alice's checkpoint (cross-user visibility)
    // Target the specific row container that has the Load button as a sibling
    const checkpointRow = modal.locator('div.flex.justify-between').filter({ hasText: saveName });
    await expect(checkpointRow).toBeVisible({ timeout: 10000 });

    // Verify it shows "by alice"
    await expect(checkpointRow.locator('text=by alice')).toBeVisible();

    // Bob clicks Load on Alice's checkpoint
    bobPage.once('dialog', dialog => dialog.accept());
    await checkpointRow.getByRole('button', { name: 'Load' }).click();

    // --- Verify: Bob's UI matches Alice's saved state exactly ---
    await expect(bobFrame.locator('#num1')).toHaveValue('42', { timeout: 15000 });
    await expect(bobFrame.locator('#num2')).toHaveValue('58', { timeout: 15000 });
    await expect(bobFrame.locator('#result')).toHaveText('100', { timeout: 15000 });

    await aliceCtx.close();
    await bobCtx.close();
  });

  test('Non-participant cannot see session checkpoints', async ({ browser }) => {
    const aliceCtx = await browser.newContext();
    const charlieSoloCtx = await browser.newContext();
    const alicePage = await aliceCtx.newPage();
    const charliePage = await charlieSoloCtx.newPage();

    // Alice creates a session and saves a checkpoint
    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Collaborative Calculator', 'RQ5 Isolation Test');

    const aliceFrame = alicePage.frameLocator('iframe');
    await waitForShinyBoot(aliceFrame);

    await setShinyNumericInput(aliceFrame, '#num1', '77');
    await setShinyNumericInput(aliceFrame, '#num2', '33');
    await aliceFrame.locator('button#calculate').click();
    await expect(aliceFrame.locator('#result')).toHaveText('110', { timeout: 25000 });

    const saveName = `RQ5-Isolation-${Date.now()}`;
    await saveState(alicePage, saveName);

    // Charlie is NOT in the session — opens saved-apps page
    await login(charliePage, 'charlie');
    await charliePage.goto('/saved-apps');

    // Charlie should NOT see Alice's session checkpoint
    await charliePage.waitForTimeout(2000);
    await expect(charliePage.locator(`text=${saveName}`)).not.toBeVisible();

    await aliceCtx.close();
    await charlieSoloCtx.close();
  });
});
