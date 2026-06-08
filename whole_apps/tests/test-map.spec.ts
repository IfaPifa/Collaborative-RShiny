import { test, expect } from '@playwright/test';
import { openApp } from './helpers';

test.describe('Monolithic Geospatial Map', () => {
  test.setTimeout(60000);

  test('App loads and shows map', async ({ page }) => {
    await openApp(page, 'map');
    await expect(page.locator('text=Sensor Mesh Deployment')).toBeVisible();
    // Leaflet map container should be rendered
    await expect(page.locator('.leaflet-container')).toBeVisible({ timeout: 15000 });
  });

  test('Click on map places a sensor marker', async ({ page }) => {
    await openApp(page, 'map');
    await expect(page.locator('.leaflet-container')).toBeVisible({ timeout: 15000 });

    // Click on the map to place a sensor
    await page.locator('.leaflet-container').click({ position: { x: 400, y: 350 } });

    // Sensor count should update
    await expect(page.locator('#sensor_count')).toContainText('1', { timeout: 10000 });
  });
});
