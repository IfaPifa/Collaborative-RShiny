import { test, expect } from '@playwright/test';
import { openApp } from './helpers';

test.describe('Monolithic Visual Analytics', () => {
  test.setTimeout(60000);

  test('App loads and shows title', async ({ page }) => {
    await openApp(page, 'analytics');
    await expect(page.locator('text=Visual Analytics')).toBeVisible();
  });

  test('Displays KPI values and scatter plot', async ({ page }) => {
    await openApp(page, 'analytics');

    // KPIs should render with default filter values
    await expect(page.locator('#kpi_count')).not.toBeEmpty({ timeout: 10000 });
    await expect(page.locator('#kpi_mpg')).not.toBeEmpty({ timeout: 10000 });

    // Scatter plot should be visible
    await expect(page.locator('#scatter_plot')).toBeVisible();
  });
});
