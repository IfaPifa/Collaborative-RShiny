import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession, launchSolo, waitForShinyBoot, demoteUser } from './helpers';

test.describe('Geospatial Editor: Core Four Matrix (REST)', () => {
  test.setTimeout(60000);

  // TEST 1: Solo Mode — Place Sensor on Map
  test('1. Solo Mode: Place Sensor Marker', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Geospatial Editor');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, 'HTTP GET/POST');

    // Wait for Leaflet map to render
    const mapContainer = frame.locator('#map');
    await expect(mapContainer).toBeVisible({ timeout: 15000 });

    // Select sensor type
    await frame.locator('select#sensor_type').selectOption('Camera Trap');

    // Click on the map to place a marker (center of the map element)
    const mapBox = await mapContainer.boundingBox();
    if (mapBox) {
      // Click slightly off-center to avoid any map controls
      await frame.locator('#map').click({ position: { x: mapBox.width / 2 + 50, y: mapBox.height / 2 } });
    }

    // Verify a marker appeared (Leaflet adds markers as img elements with class leaflet-marker-icon)
    await expect(frame.locator('.leaflet-marker-icon')).toBeVisible({ timeout: 10000 });

    // Verify the "Last sensor placed by" text appears
    await expect(frame.locator('text=alice')).toBeVisible({ timeout: 10000 });
  });

  // TEST 2: Real-Time Collaborative Sync — Delta Markers
  test('2. Collab Mode: Delta Marker Synchronization', async ({ browser }) => {
    const aliceCtx = await browser.newContext();
    const bobCtx = await browser.newContext();
    const alicePage = await aliceCtx.newPage();
    const bobPage = await bobCtx.newPage();

    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Geospatial Editor', 'Map Sync Test');

    await login(bobPage, 'bob');
    await joinCollabSession(bobPage, sessionId);

    const aliceFrame = alicePage.frameLocator('iframe');
    const bobFrame = bobPage.frameLocator('iframe');
    await waitForShinyBoot(aliceFrame, 'HTTP GET/POST');
    await waitForShinyBoot(bobFrame, 'HTTP GET/POST');

    // Wait for both maps to render
    await expect(aliceFrame.locator('#map')).toBeVisible({ timeout: 15000 });
    await expect(bobFrame.locator('#map')).toBeVisible({ timeout: 15000 });

    // Alice places a sensor
    await aliceFrame.locator('select#sensor_type').selectOption('Soil Moisture');
    const aliceMap = aliceFrame.locator('#map');
    const aliceMapBox = await aliceMap.boundingBox();
    if (aliceMapBox) {
      await aliceMap.click({ position: { x: aliceMapBox.width / 2, y: aliceMapBox.height / 2 } });
    }

    // Alice sees her marker
    await expect(aliceFrame.locator('.leaflet-marker-icon')).toBeVisible({ timeout: 10000 });

    // Bob's map polls and the marker appears on his map too
    await expect(bobFrame.locator('.leaflet-marker-icon')).toBeVisible({ timeout: 15000 });

    await aliceCtx.close();
    await bobCtx.close();
  });

  // TEST 3: Permission Enforcement
  test('3. Security: Role-Based UI Locking', async ({ browser }) => {
    const aliceCtx = await browser.newContext();
    const charlieCtx = await browser.newContext();
    const alicePage = await aliceCtx.newPage();
    const charliePage = await charlieCtx.newPage();

    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Geospatial Editor', 'Map Security Test');

    await login(charliePage, 'charlie');
    await joinCollabSession(charliePage, sessionId);

    const charlieFrame = charliePage.frameLocator('iframe');
    await waitForShinyBoot(charlieFrame, 'HTTP GET/POST');

    // Charlie starts as Editor — sensor type dropdown is enabled
    await expect(charlieFrame.locator('select#sensor_type')).toBeEnabled();

    // Alice demotes Charlie
    await demoteUser(alicePage, 'charlie');

    // Charlie's controls lock — map clicks should be ignored (viewer mode)
    // The select dropdown should be disabled
    await expect(charlieFrame.locator('select#sensor_type')).toBeDisabled({ timeout: 10000 });

    await aliceCtx.close();
    await charlieCtx.close();
  });

  // TEST 4: Multi-User Marker Accumulation
  test('4. Delta Sync: Multiple Markers from Multiple Users', async ({ browser }) => {
    const aliceCtx = await browser.newContext();
    const bobCtx = await browser.newContext();
    const alicePage = await aliceCtx.newPage();
    const bobPage = await bobCtx.newPage();

    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Geospatial Editor', 'Multi-Marker Test');

    await login(bobPage, 'bob');
    await joinCollabSession(bobPage, sessionId);

    const aliceFrame = alicePage.frameLocator('iframe');
    const bobFrame = bobPage.frameLocator('iframe');
    await waitForShinyBoot(aliceFrame, 'HTTP GET/POST');
    await waitForShinyBoot(bobFrame, 'HTTP GET/POST');

    await expect(aliceFrame.locator('#map')).toBeVisible({ timeout: 15000 });
    await expect(bobFrame.locator('#map')).toBeVisible({ timeout: 15000 });

    // Alice places a Camera Trap
    await aliceFrame.locator('select#sensor_type').selectOption('Camera Trap');
    const aliceMap = aliceFrame.locator('#map');
    const aliceBox = await aliceMap.boundingBox();
    if (aliceBox) {
      await aliceMap.click({ position: { x: aliceBox.width / 3, y: aliceBox.height / 3 } });
    }
    await expect(aliceFrame.locator('.leaflet-marker-icon')).toHaveCount(1, { timeout: 10000 });

    // Wait for Bob to see it
    await expect(bobFrame.locator('.leaflet-marker-icon')).toHaveCount(1, { timeout: 15000 });

    // Bob places an Audio Recorder at a different spot
    await bobFrame.locator('select#sensor_type').selectOption('Audio Recorder');
    const bobMap = bobFrame.locator('#map');
    const bobBox = await bobMap.boundingBox();
    if (bobBox) {
      await bobMap.click({ position: { x: bobBox.width * 2 / 3, y: bobBox.height * 2 / 3 } });
    }

    // Both maps should now show 2 markers
    await expect(aliceFrame.locator('.leaflet-marker-icon')).toHaveCount(2, { timeout: 15000 });
    await expect(bobFrame.locator('.leaflet-marker-icon')).toHaveCount(2, { timeout: 15000 });

    await aliceCtx.close();
    await bobCtx.close();
  });
});

