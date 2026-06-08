import { test, expect } from '@playwright/test';
import { openApp } from './helpers';
import path from 'path';

test.describe('Monolithic Data Exchange', () => {
  test.setTimeout(60000);

  test('App loads and shows title', async ({ page }) => {
    await openApp(page, 'data_exchange');
    await expect(page.locator('text=Data Exchange')).toBeVisible();
  });

  test('Uploads CSV and displays cleaned data', async ({ page }) => {
    await openApp(page, 'data_exchange');

    // Upload a test CSV
    const csvPath = path.join(__dirname, 'test-data.csv');
    await page.setInputFiles('#file_upload', csvPath);
    await page.click('#process_data');

    // Table should update with cleaned data (uppercased)
    await expect(page.locator('#data_table')).not.toContainText('Awaiting Data', { timeout: 15000 });
  });
});
