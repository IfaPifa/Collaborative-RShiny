import { test, expect } from '@playwright/test';
import { openApp } from './helpers';

test.describe('Monolithic Advanced Visual Analytics', () => {
  test.setTimeout(60000);

  test('App loads and shows title', async ({ page }) => {
    await openApp(page, 'analytics_advanced');
    await expect(page.locator('text=Microclimate Sensors')).toBeVisible();
  });

  test('Displays KPI values and plotly chart', async ({ page }) => {
    await openApp(page, 'analytics_advanced');

    await expect(page.locator('#kpi_count')).not.toBeEmpty({ timeout: 10000 });
    await expect(page.locator('#kpi_ozone')).not.toBeEmpty({ timeout: 10000 });

    // Plotly chart container
    await expect(page.locator('#scatter_plot .plotly')).toBeVisible({ timeout: 15000 });
  });
});
