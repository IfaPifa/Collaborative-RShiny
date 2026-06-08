import { test, expect } from '@playwright/test';
import { openApp, setShinyNumericInput } from './helpers';

test.describe('Monolithic Calculator', () => {
  test.setTimeout(60000);

  test('App loads and shows title', async ({ page }) => {
    await openApp(page, 'calculator');
    await expect(page.locator('text=Sensor Calculator')).toBeVisible();
  });

  test('Calculates sum correctly', async ({ page }) => {
    await openApp(page, 'calculator');

    await setShinyNumericInput(page, '#num1', '10');
    await setShinyNumericInput(page, '#num2', '25');
    await page.click('#calculate');

    await expect(page.locator('#result')).toContainText('35', { timeout: 10000 });
  });
});
