import { test, expect } from '@playwright/test';

test('Solo Workspace & Save State Pipeline (REST)', async ({ page }) => {
  // 1. Log in as Alice
  await page.goto('/login');
  await page.fill('input[name="username"]', 'alice');
  await page.fill('input[name="password"]', 'password');
  await page.click('button[type="submit"]');

  // 2. Wait for the Library
  await page.waitForURL('**/library');
  await expect(page.locator('h1', { hasText: 'Application Library' })).toBeVisible();

  // 3. Click the FIRST 'Launch Solo' button
  await page.locator('button', { hasText: 'Launch Solo' }).first().click();
  await page.waitForURL('**/workspace/solo');

  // 4. Verify the iframe loaded the Shiny App
  const shinyFrame = page.frameLocator('iframe');
  await expect(shinyFrame.locator('.navbar-brand', { hasText: 'LTER-LIFE: Sensor Deployment' })).toBeVisible({ timeout: 15000 });

  // FIX: Look for the new REST indicator
  await expect(shinyFrame.locator('text=🌐 Async GET/POST')).toBeVisible({ timeout: 15000 });

  // (Removed the 4-second Kafka stabilization wait!)

  // 5. INTERACT WITH THE APP TO GENERATE REST STATE
  // The Java "Smart Vault" refuses to save an empty state. We must push data to Redis first.
  await shinyFrame.locator('#num1').fill('50');
  await shinyFrame.locator('button#calculate').click(); // "Sync to Vault" button
  
  // Wait for Plumber to process the math and return it, proving state exists in Redis
  await expect(shinyFrame.locator('#result')).toHaveText('50', { timeout: 15000 });

  // 6. Trigger a "Save State"
  await page.click('button:has-text("Save State")');
  
  // 7. Fill out the modal and save
  const uniqueSaveName = `Playwright Test Save - ${Date.now()}`;
  await page.fill('input[placeholder="Name this save..."]', uniqueSaveName);
  
  // Handle the browser alert
  page.once('dialog', dialog => {
    expect(dialog.message()).toContain('Saved');
    dialog.accept();
  });
  
  await page.getByRole('button', { name: 'Save', exact: true }).click();

  // 8. Navigate to "Saved Apps" and verify it appears
  await page.waitForTimeout(1000); 
  await page.goto('/saved-apps');
  await expect(page.locator('h1', { hasText: 'Saved Workspaces' })).toBeVisible();
  
  // Verify our specific save is in the table
  await expect(page.locator(`text=${uniqueSaveName}`)).toBeVisible();
  console.log('✅ Solo Save State Test passed!');
});