import { test, expect } from '@playwright/test';
import { openApp, setShinyNumericInput } from './helpers';

test.describe('Monolithic Monte Carlo Simulator', () => {
  test.setTimeout(90000);

  test('App loads and shows title', async ({ page }) => {
    await openApp(page, 'montecarlo');
    await expect(page.locator('text=Population Viability Simulator')).toBeVisible();
  });

  test('Runs simulation and displays results', async ({ page }) => {
    await openApp(page, 'montecarlo');

    await setShinyNumericInput(page, '#n0', '200');
    await setShinyNumericInput(page, '#paths', '1000');
    await setShinyNumericInput(page, '#years', '20');
    await page.click('#run_sim');

    // Wait for simulation to complete — plotly chart should appear
    await expect(page.locator('#sim_plot .plotly')).toBeVisible({ timeout: 60000 });

    // Extinction risk KPI should render
    await expect(page.locator('#kpi_footer')).toContainText('Extinction Risk', { timeout: 10000 });
  });
});
