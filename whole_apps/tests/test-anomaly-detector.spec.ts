import { test, expect } from '@playwright/test';
import { openApp } from './helpers';
import path from 'path';

test.describe('Monolithic Climate Anomaly Detector', () => {
  test.setTimeout(90000);

  test('App loads and shows title', async ({ page }) => {
    await openApp(page, 'anomaly_detector');
    await expect(page.locator('text=Anomaly Detector')).toBeVisible();
  });

  test('Uploads sensor CSV and runs analysis', async ({ page }) => {
    await openApp(page, 'anomaly_detector');

    const csvPath = path.join(__dirname, 'test-climate-data.csv');
    await page.setInputFiles('#file_upload', csvPath);
    await page.click('#process_data');

    // Table should update with daily summary
    await expect(page.locator('#data_table')).not.toContainText('Awaiting Data', { timeout: 30000 });
  });
});
