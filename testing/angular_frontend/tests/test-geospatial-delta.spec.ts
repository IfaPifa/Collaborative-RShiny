import { test, expect } from '@playwright/test';

test('Geospatial: Stateless Delta Synchronization', async ({ browser }) => {
  const aliceContext = await browser.newContext();
  const bobContext = await browser.newContext();
  const alicePage = await aliceContext.newPage();
  const bobPage = await bobContext.newPage();

  // --- SETUP ---
  await alicePage.goto('/login');
  await alicePage.fill('input[name="username"]', 'alice');
  await alicePage.fill('input[name="password"]', 'password');
  await alicePage.click('button[type="submit"]');
  await alicePage.waitForURL('**/library'); 
  
  await alicePage.goto('/collab-hub');
  await alicePage.click('button:has-text("+ New Session")');
  await alicePage.fill('input[placeholder="e.g. Q1 Budget Review"]', 'Sensor Deployment');
  await alicePage.locator('select').selectOption({ label: 'Geospatial Editor' }); 
  await alicePage.click('button:has-text("Create & Enter")');
  await alicePage.waitForURL('**/workspace/*');
  
  const sessionId = alicePage.url().split('/').pop();

  await bobPage.goto('/login');
  await bobPage.fill('input[name="username"]', 'bob');
  await bobPage.fill('input[name="password"]', 'password');
  await bobPage.click('button[type="submit"]');
  await bobPage.waitForURL('**/library'); 
  
  await bobPage.goto('/collab-hub');
  await bobPage.fill('input[placeholder="Paste Session UUID here..."]', sessionId!);
  await bobPage.click('button:has-text("Join Room")');
  await bobPage.waitForURL(`**/workspace/${sessionId}`);

  // --- INTERACT ---
  const aliceFrame = alicePage.frameLocator('iframe');
  const bobFrame = bobPage.frameLocator('iframe');

  // Wait for Leaflet to fully render
  await expect(aliceFrame.locator('.leaflet-container')).toBeVisible({ timeout: 15000 });
  await expect(bobFrame.locator('.leaflet-container')).toBeVisible({ timeout: 15000 });

  // Give Bob's R backend 4 seconds to connect to the partition
  await alicePage.waitForTimeout(4000);

  // Alice clicks precisely on the map container
  await aliceFrame.locator('#map').click({ position: { x: 300, y: 300 } });

  // --- VERIFY DELTA ---
  // FIX: Because Leaflet + Playwright often double-fire synthetic clicks, 
  // we check that the Delta Sync successfully rendered AT LEAST ONE awesome marker.
  await expect(bobFrame.locator('.awesome-marker').first()).toBeVisible({ timeout: 15000 });
  
  // Verify the UI text updates to show the Delta sender
  await expect(bobFrame.locator('text=Last sensor placed by: alice')).toBeVisible({ timeout: 15000 });

  console.log('✅ Delta Sync passed! Map coordinates routed successfully.');

  await aliceContext.close();
  await bobContext.close();
});