import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession, waitForShinyBoot, setShinyNumericInput } from './helpers';

test('Real-Time Data Synchronization', async ({ browser }) => {
  test.setTimeout(60000);

  const aliceCtx = await browser.newContext();
  const bobCtx = await browser.newContext();
  const alicePage = await aliceCtx.newPage();
  const bobPage = await bobCtx.newPage();

  await login(alicePage, 'alice');
  const sessionId = await createCollabSession(alicePage, 'Collaborative Calculator', 'Sync Test');

  await login(bobPage, 'bob');
  await joinCollabSession(bobPage, sessionId);

  const aliceFrame = alicePage.frameLocator('iframe');
  const bobFrame = bobPage.frameLocator('iframe');
  await waitForShinyBoot(aliceFrame);
  await waitForShinyBoot(bobFrame);

  // Alice enters values and syncs
  await setShinyNumericInput(aliceFrame, '#num1', '10');
  await setShinyNumericInput(aliceFrame, '#num2', '25');
  await aliceFrame.locator('button#calculate').click();

  await expect(aliceFrame.locator('#result')).toHaveText('35', { timeout: 15000 });

  // Bob's UI polls and sees the same values
  await expect(bobFrame.locator('#num1')).toHaveValue('10', { timeout: 15000 });
  await expect(bobFrame.locator('#num2')).toHaveValue('25', { timeout: 15000 });
  await expect(bobFrame.locator('#result')).toHaveText('35', { timeout: 15000 });

  await aliceCtx.close();
  await bobCtx.close();
});
