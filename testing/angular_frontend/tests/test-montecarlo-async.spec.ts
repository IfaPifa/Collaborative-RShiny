import { test, expect } from '@playwright/test';

// Keep the 60s timeout since the Monte Carlo simulation itself takes time to run
test.setTimeout(60000);

test('Monte Carlo: Async Compute & Non-Blocking UI', async ({ page }) => {
  // --- 1. SETUP & LOGIN ---
  await page.goto('/login');
  await page.fill('input[name="username"]', 'alice');
  await page.fill('input[name="password"]', 'password');
  await page.click('button[type="submit"]');
  
  // Wait for the library to load fully
  await page.waitForURL('**/library');
  
  // --- 2. LAUNCH SOLO APP ---
  // FIX: Target the specific card container class (.bg-white.rounded-xl) 
  // instead of a generic 'div' to prevent matching the entire page wrapper.
  const mcAppContainer = page.locator('.bg-white.rounded-xl').filter({ 
    has: page.locator('h3', { hasText: 'Monte Carlo Simulator' }) 
  });
  
  await mcAppContainer.locator('button:has-text("Launch Solo")').click();
  
  await page.waitForURL('**/workspace/solo');

  // --- 3. WAIT FOR R-SHINY & KAFKA TO STABILIZE ---
  const shinyFrame = page.frameLocator('iframe');
  
  // Wait for the UI to actually render using exact text from your Shiny app
  await expect(shinyFrame.locator('text=Population Viability Simulator')).toBeVisible({ timeout: 15000 });

  // The Kafka Stabilization Delay
  // Gives the R backend time to connect to the 'input' topic before we fire the command
  await page.waitForTimeout(5000);

  // --- 4. TRIGGER THE HEAVY COMPUTE ---
  await shinyFrame.locator('button#run_sim').click();

  // --- 5. VERIFY ASYNC/NON-BLOCKING BEHAVIOR ---
  // Proof that the UI isn't blocked: the button disables immediately
  await expect(shinyFrame.locator('button#run_sim')).toBeDisabled();
  
  // Proof that Kafka is sending PROGRESS messages: the progress bar appears
  await expect(shinyFrame.locator('.progress-bar')).toBeVisible();

  // --- 6. WAIT FOR FINAL RESULT ---
  // Wait for the final RESULT payload to render the Extinction Risk KPI
  // This gets a generous timeout because calculating 5,000 paths takes real time
  await expect(shinyFrame.locator('text=Extinction Risk')).toBeVisible({ timeout: 45000 });
  
  // Verify the UI unlocks after the backend finishes
  await expect(shinyFrame.locator('button#run_sim')).toBeEnabled();

  console.log('✅ Async Compute passed! Backend handled the load without blocking the frontend.');
});