import { test, expect } from '@playwright/test';
import { openApp } from './helpers';

test.describe('Monolithic ML Trainer', () => {
  test.setTimeout(120000);

  test('App loads and shows title', async ({ page }) => {
    await openApp(page, 'ml_trainer');
    await expect(page.locator('text=Biodiversity Predictor')).toBeVisible();
  });

  test('Trains model and displays convergence + importance', async ({ page }) => {
    await openApp(page, 'ml_trainer');

    await page.click('#train_btn');

    // Wait for training to complete — progress bar should show COMPLETE
    await expect(page.locator('text=COMPLETE')).toBeVisible({ timeout: 90000 });

    // Convergence plot (plotly) should render
    await expect(page.locator('#loss_plot .plotly')).toBeVisible({ timeout: 10000 });

    // Feature importance plot should render
    await expect(page.locator('#importance_plot .plotly')).toBeVisible({ timeout: 10000 });
  });
});
