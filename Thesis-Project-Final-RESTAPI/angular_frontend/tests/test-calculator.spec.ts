import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession, launchSolo, waitForShinyBoot, saveState, demoteUser, setShinyNumericInput } from './helpers';

test.describe('Calculator: Core Four Matrix', () => {
  test.setTimeout(60000);
  const sharedSaveName = `Calc Checkpoint - ${Date.now()}`;

  test('1. Solo Mode: Compute & Save State', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Collaborative Calculator');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, '🟢 System Online');

    await setShinyNumericInput(frame, '#num1', '10');
    await setShinyNumericInput(frame, '#num2', '25');
    await frame.locator('button#calculate').click();

    await expect(frame.locator('#result')).toHaveText('35', { timeout: 25000 });

    await saveState(page, sharedSaveName);

    await page.goto('/saved-apps');
    await expect(page.locator(`text=${sharedSaveName}`)).toBeVisible();
  });

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
    await waitForShinyBoot(aliceFrame, '🟢 System Online');
    await waitForShinyBoot(bobFrame, '🟢 System Online');

    await setShinyNumericInput(aliceFrame, '#num1', '42');
    await setShinyNumericInput(aliceFrame, '#num2', '8');
    await aliceFrame.locator('button#calculate').click();

    await expect(aliceFrame.locator('#result')).toHaveText('50', { timeout: 15000 });

    await expect(bobFrame.locator('#num1')).toHaveValue('42', { timeout: 15000 });
    await expect(bobFrame.locator('#num2')).toHaveValue('8', { timeout: 15000 });
    await expect(bobFrame.locator('#result')).toHaveText('50', { timeout: 15000 });

    await aliceCtx.close();
    await bobCtx.close();
  });

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
    await waitForShinyBoot(charlieFrame, '🟢 System Online');

    await expect(charlieFrame.locator('button#calculate')).toBeEnabled();

    await demoteUser(alicePage, 'charlie');

    await expect(charlieFrame.locator('button#calculate')).toBeDisabled({ timeout: 10000 });
    await expect(charlieFrame.locator('#num1')).toBeDisabled();
    await expect(charlieFrame.locator('#num2')).toBeDisabled();

    await aliceCtx.close();
    await charlieCtx.close();
  });

  test('4. Time Machine: Restoring Historical States', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Collaborative Calculator');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, '🟢 System Online');

    await setShinyNumericInput(frame, '#num1', '99');
    await setShinyNumericInput(frame, '#num2', '99');
    await frame.locator('button#calculate').click();
    await expect(frame.locator('#result')).toHaveText('198', { timeout: 15000 });

    await page.click('button:has-text("Load Checkpoint")');
    const modal = page.locator('app-modal');
    await expect(modal.getByRole('heading', { name: 'Load Checkpoint' })).toBeVisible({ timeout: 5000 });
    page.once('dialog', dialog => dialog.accept());
    await modal.getByRole('button', { name: 'Load', exact: true }).first().click();

    await expect(frame.locator('#num1')).toHaveValue('10', { timeout: 10000 });
    await expect(frame.locator('#num2')).toHaveValue('25', { timeout: 10000 });
  });
});