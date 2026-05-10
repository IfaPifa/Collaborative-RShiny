import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession, launchSolo, waitForShinyBoot, saveState, demoteUser } from './helpers';

test.describe('Geospatial Editor: Core Four Matrix (REST)', () => {
  test.setTimeout(60000);
  const sharedSaveName = `Map Checkpoint - ${Date.now()}`;

  // TEST 1: Solo Mode — Place Sensor on Map
  test('1. Solo Mode: Place Sensor Marker', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Geospatial Editor');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, 'HTTP GET/POST');

    // Wait for Leaflet map to render
    const mapContainer = frame.locator('#map');
    await expect(mapContainer).toBeVisible({ timeout: 15000 });

    // Default is already "Camera Trap" — click the map to place a marker
    const mapBox = await mapContainer.boundingBox();
    if (mapBox) {
      await frame.locator('#map').click({ position: { x: mapBox.width / 2 + 50, y: mapBox.height / 2 } });
    }

    // Verify a marker appeared on the map
    await expect(frame.locator('.awesome-marker').first()).toBeVisible({ timeout: 15000 });

    // Verify the round-trip completed
    await expect(frame.locator('text=Last sensor placed by')).toBeVisible({ timeout: 10000 });

    // Wait for state to settle in Redis before saving
    await page.waitForTimeout(3000);

    // Save state
    await saveState(page, sharedSaveName);
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

    // Alice places a sensor (default Camera Trap)
    const aliceMap = aliceFrame.locator('#map');
    const aliceMapBox = await aliceMap.boundingBox();
    if (aliceMapBox) {
      await aliceMap.click({ position: { x: aliceMapBox.width / 2, y: aliceMapBox.height / 2 } });
    }

    // Alice sees her marker
    await expect(aliceFrame.locator('.awesome-marker').first()).toBeVisible({ timeout: 15000 });

    // Bob's map polls and the marker appears on his map too
    await expect(bobFrame.locator('.awesome-marker').first()).toBeVisible({ timeout: 15000 });

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

    // Charlie starts as Editor — selectize control is interactive
    await expect(charlieFrame.locator('.selectize-input')).toBeVisible();

    // Alice demotes Charlie
    await demoteUser(alicePage, 'charlie');

    // Charlie's controls lock
    await expect(charlieFrame.locator('select#sensor_type')).toBeDisabled({ timeout: 10000 });

    await aliceCtx.close();
    await charlieCtx.close();
  });

  // TEST 4: Time Machine — Restore Checkpoint
  test('4. Time Machine: Restoring Historical States', async ({ page }) => {
    await login(page, 'alice');
    await launchSolo(page, 'Geospatial Editor');

    const frame = page.frameLocator('iframe');
    await waitForShinyBoot(frame, 'HTTP GET/POST');
    await expect(frame.locator('#map')).toBeVisible({ timeout: 15000 });

    // Load the most recent checkpoint (saved in Test 1)
    await page.click('button:has-text("Load Checkpoint")');
    const modal = page.locator('app-modal');
    await expect(modal.getByRole('heading', { name: 'Load Checkpoint' })).toBeVisible({ timeout: 5000 });
    page.once('dialog', dialog => dialog.accept());
    await modal.getByRole('button', { name: 'Load', exact: true }).first().click();

    // Wait for restore → Redis → poll cycle
    await page.waitForTimeout(5000);

    // Verify the restored marker appears on the map
    await expect(frame.locator('.awesome-marker').first()).toBeVisible({ timeout: 15000 });

    // Verify the sender info was restored
    await expect(frame.locator('text=Last sensor placed by')).toBeVisible({ timeout: 10000 });
  });

  // TEST 5: Multi-User Marker Accumulation
  test('5. Delta Sync: Multiple Markers from Multiple Users', async ({ browser }) => {
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

    // Alice places a marker
    const aliceMap = aliceFrame.locator('#map');
    const aliceBox = await aliceMap.boundingBox();
    if (aliceBox) {
      await aliceMap.click({ position: { x: aliceBox.width / 3, y: aliceBox.height / 3 } });
    }
    await expect(aliceFrame.locator('.awesome-marker').first()).toBeVisible({ timeout: 15000 });

    // Wait for Bob to see it
    await expect(bobFrame.locator('.awesome-marker').first()).toBeVisible({ timeout: 15000 });

    // Bob places a marker at a different spot
    const bobMap = bobFrame.locator('#map');
    const bobBox = await bobMap.boundingBox();
    if (bobBox) {
      await bobMap.click({ position: { x: bobBox.width * 2 / 3, y: bobBox.height * 2 / 3 } });
    }

    // Both maps should now show 2 markers
    await expect(aliceFrame.locator('.awesome-marker')).toHaveCount(2, { timeout: 15000 });
    await expect(bobFrame.locator('.awesome-marker')).toHaveCount(2, { timeout: 15000 });

    await aliceCtx.close();
    await bobCtx.close();
  });
});

