import { test, expect } from '@playwright/test';
import { login, launchSolo, waitForShinyBoot, saveState, setShinyNumericInput } from './helpers';

test('Solo Workspace & Save State Pipeline', async ({ page }) => {
  test.setTimeout(60000);

  await login(page, 'alice');
  await launchSolo(page, 'Collaborative Calculator');

  const frame = page.frameLocator('iframe');
  await waitForShinyBoot(frame);

  // Interact with the app to generate state
  await setShinyNumericInput(frame, '#num1', '50');
  await setShinyNumericInput(frame, '#num2', '0');
  await frame.locator('button#calculate').click();

  await expect(frame.locator('#result')).toHaveText('50', { timeout: 15000 });

  // Save state
  const uniqueSaveName = `Playwright Test Save - ${Date.now()}`;
  await saveState(page, uniqueSaveName);

  // Verify it appears in saved apps
  await page.goto('/saved-apps');
  await expect(page.locator(`text=${uniqueSaveName}`)).toBeVisible();
});