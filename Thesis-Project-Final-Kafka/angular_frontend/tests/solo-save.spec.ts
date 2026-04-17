import { test, expect } from '@playwright/test';

test('Solo Workspace & Save State Pipeline', async ({ page }) => {
  // 1. Log in as Alice
  await page.goto('/login');
  await page.fill('input[name="username"]', 'alice');
  await page.fill('input[name="password"]', 'password');
  await page.click('button[type="submit"]');

  // 2. Wait for the Library to load and verify the DOM has updated
  await page.waitForURL('**/library');
  await expect(page.locator('h1', { hasText: 'Application Library' })).toBeVisible();

  // 3. Click the FIRST 'Launch Solo' button (prevents strict-mode errors if multiple apps exist)
  await page.locator('button', { hasText: 'Launch Solo' }).first().click();
  await page.waitForURL('**/workspace/solo');

  // 4. Verify the iframe loaded the Shiny App
  // We wait up to 15 seconds for the iframe to exist and load the R-Shiny UI
  const shinyFrame = page.frameLocator('iframe');
  await expect(shinyFrame.locator('h2', { hasText: 'ShinySwarm: Collaborative Calc' })).toBeVisible({ timeout: 15000 });

  // 5. Trigger a "Save State"
  await page.click('button:has-text("Save State")');
  
  // 6. Fill out the modal and save
  const uniqueSaveName = `Playwright Test Save - ${Date.now()}`;
  await page.fill('input[placeholder="Name this save..."]', uniqueSaveName);
  
  // Handle the browser alert that pops up ("Solo State Saved!")
  page.once('dialog', dialog => {
    expect(dialog.message()).toContain('Saved');
    dialog.accept();
  });
  
  await page.getByRole('button', { name: 'Save', exact: true }).click();

  // 7. Navigate to "Saved Apps" and verify it appears in the database
  // Give PostgreSQL 1 second to actually write the data before we check for it
  await page.waitForTimeout(1000); 
  
  await page.goto('/saved-apps');
  await expect(page.locator(`h3:has-text("${uniqueSaveName}")`)).toBeVisible({ timeout: 10000 });

  console.log('✅ Solo Save test passed! State is persisting to the database.');
});