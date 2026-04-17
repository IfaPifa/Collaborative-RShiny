import { test, expect, Page } from '@playwright/test';

// =====================================================================
// HELPER FUNCTIONS (Write once, use everywhere)
// =====================================================================
async function login(page: Page, username: string) {
  await page.goto('/login');
  await page.fill('input[name="username"]', username);
  await page.fill('input[name="password"]', 'password');
  await page.click('button[type="submit"]');
  await page.waitForURL('**/library');
}

async function createCollabSession(page: Page, appName: string, sessionName: string) {
  await page.goto('/collab-hub');
  await page.click('button:has-text("+ New Session")');
  await page.fill('input[placeholder="e.g. Q1 Budget Review"]', sessionName);
  await page.locator('select').selectOption({ label: appName });
  await page.click('button:has-text("Create & Enter")');
  await page.waitForURL('**/workspace/*');
  return page.url().split('/').pop(); // Returns the sessionId
}

// =====================================================================
// THE CORE FOUR MATRIX: Advanced Visual Analytics
// =====================================================================
test.describe('Advanced Analytics: The Core Four Matrix (REST)', () => {
  
  // Set global timeout to 60s for these heavy operations
  test.setTimeout(60000);
  
  // We will store this to reuse the save state in Test 4
  let sharedSaveName = `Analytics Checkpoint - ${Date.now()}`;

  // -------------------------------------------------------------------
  // TEST 1: SOLO STATE PIPELINE
  // -------------------------------------------------------------------
  test('1. Solo Mode: Compute & Save State', async ({ page }) => {
    await login(page, 'alice');

    // Launch Solo App
    const appContainer = page.locator('.bg-white.rounded-xl').filter({ 
      has: page.locator('h3', { hasText: 'Advanced Visual Analytics' }) 
    });
    await appContainer.locator('button:has-text("Launch Solo")').click();
    await page.waitForURL('**/workspace/solo');

    const shinyFrame = page.frameLocator('iframe');
    await expect(shinyFrame.locator('text=🌐 Async GET/POST"')).toBeVisible({ timeout: 15000 });

    // Interact to generate state
    await shinyFrame.locator('input[name="months"][value="5"]').uncheck();
    await shinyFrame.locator('button#update_plot').click();
    
    // Verify Shiny UI reacted (Wait for an SVG or a specific badge)
    await expect(shinyFrame.locator('span.badge')).toContainText('alice', { timeout: 10000 });

    // Angular Save State
    await page.click('button:has-text("Save State")');
    await page.fill('input[placeholder="Name this save..."]', sharedSaveName);
    
    page.once('dialog', dialog => dialog.accept());
    await page.getByRole('button', { name: 'Save', exact: true }).click();

    // Verify in Library
    await page.waitForTimeout(1000);
    await page.goto('/saved-apps');
    await expect(page.locator('h1', { hasText: 'Saved Workspaces' })).toBeVisible(); // Using updated text
    await expect(page.locator(`text=${sharedSaveName}`)).toBeVisible();
  });

  // -------------------------------------------------------------------
  // TEST 2: REAL-TIME COLLABORATIVE SYNC
  // -------------------------------------------------------------------
  test('2. Collab Mode: Real-Time Synchronization', async ({ browser }) => {
    const aliceContext = await browser.newContext();
    const bobContext = await browser.newContext();
    const alicePage = await aliceContext.newPage();
    const bobPage = await bobContext.newPage();

    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Advanced Visual Analytics', 'Collab Sync Test');

    await login(bobPage, 'bob');
    await bobPage.goto('/collab-hub');
    await bobPage.fill('input[placeholder="Paste Session UUID here..."]', sessionId!);
    await bobPage.click('button:has-text("Join Room")');
    await bobPage.waitForURL(`**/workspace/${sessionId}`);

    const aliceFrame = alicePage.frameLocator('iframe');
    const bobFrame = bobPage.frameLocator('iframe');

    await expect(aliceFrame.locator('text=🌐 HTTP GET/POST')).toBeVisible({ timeout: 15000 });
    await expect(bobFrame.locator('text=🌐 HTTP GET/POST')).toBeVisible({ timeout: 15000 });

    // NO MORE KAFKA WAITS OR RETRY LOOPS!
    // Alice unchecks May and hits update
    await aliceFrame.locator('input[name="months"][value="5"]').uncheck();
    await aliceFrame.locator('button#update_plot').click();

    // Bob's UI naturally polls Redis and updates within 500ms
    await expect(bobFrame.locator('input[name="months"][value="5"]')).not.toBeChecked({ timeout: 10000 });
    
    await aliceContext.close();
    await bobContext.close();
  });

  // -------------------------------------------------------------------
  // TEST 3: PERMISSION ENFORCEMENT & REAL-TIME DEMOTION
  // -------------------------------------------------------------------
  test('3. Security: Role-Based UI Locking', async ({ browser }) => {
    const aliceContext = await browser.newContext();
    const charlieContext = await browser.newContext();
    const alicePage = await aliceContext.newPage();
    const charliePage = await charlieContext.newPage();

    // 1. Alice creates the session
    await login(alicePage, 'alice');
    const sessionId = await createCollabSession(alicePage, 'Advanced Visual Analytics', 'Security Test');

    // 2. Charlie joins the session (defaults to Editor when joining via code)
    await login(charliePage, 'charlie');
    await charliePage.goto('/collab-hub');
    await charliePage.fill('input[placeholder="Paste Session UUID here..."]', sessionId!);
    await charliePage.click('button:has-text("Join Room")');
    await charliePage.waitForURL(`**/workspace/${sessionId}`);

    const charlieFrame = charliePage.frameLocator('iframe');
    await expect(charlieFrame.locator('text=🌐 HTTP GET/POST')).toBeVisible({ timeout: 15000 });

    // 3. Verify Charlie starts as an EDITOR (his UI should be unlocked)
    await expect(charlieFrame.locator('button#update_plot')).toBeEnabled();

    // 4. ALICE DEMOTES CHARLIE
    // Open the "Manage Roles" modal
    await alicePage.locator('button', { hasText: '⚙️ Manage Roles' }).click();
    await expect(alicePage.locator('h3', { hasText: 'Manage Team Roles' })).toBeVisible();

    // Find Charlie in the list and uncheck the "Editor" checkbox
    const charlieRow = alicePage.locator('div.border-b').filter({ hasText: 'charlie' });
    await charlieRow.locator('input[type="checkbox"]').uncheck();

    // Close the modal
    await alicePage.locator('button', { hasText: 'Done' }).click();
    await expect(alicePage.locator('h3', { hasText: 'Manage Team Roles' })).toBeHidden();

    // 5. VERIFY CHARLIE IS INSTANTLY LOCKED OUT
    // Because Java sent a WebSocket ROLE_UPDATE, Angular should immediately tell 
    // the Shiny iframe to lock down Charlie's controls.
    await expect(charlieFrame.locator('button#update_plot')).toBeDisabled({ timeout: 10000 });
    await expect(charlieFrame.locator('input[name="months"][value="5"]')).toBeDisabled();

    console.log('✅ Real-Time Role Demotion & Security test passed!');

    await aliceContext.close();
    await charlieContext.close();
  });

  // -------------------------------------------------------------------
  // TEST 4: THE TIME MACHINE (RESTORE CHECKPOINT)
  // -------------------------------------------------------------------
  test('4. Time Machine: Restoring Historical States', async ({ page }) => {
    await login(page, 'alice');
    
    // Launch a completely fresh Solo session
    const appContainer = page.locator('.bg-white.rounded-xl').filter({ 
      has: page.locator('h3', { hasText: 'Advanced Visual Analytics' }) 
    });
    await appContainer.locator('button:has-text("Launch Solo")').click();
    await page.waitForURL('**/workspace/solo');

    const shinyFrame = page.frameLocator('iframe');
    await expect(shinyFrame.locator('text=🌐 HTTP GET/POST')).toBeVisible({ timeout: 15000 });

    // Verify default state (Month 5 should be CHECKED by default)
    await expect(shinyFrame.locator('input[name="months"][value="5"]')).toBeChecked();

    // Alice restores the checkpoint from Test 1 (where Month 5 was UNCHECKED)
    await page.click('button:has-text("Load Checkpoint")');
    
    // Assuming your modal has a list of saves, click the one we made in Test 1
    await page.click(`text=${sharedSaveName}`); 
    await page.click('button:has-text("Restore")'); // Adjust to your actual button text

    // Verification: The Shiny UI automatically polled Redis and visually changed!
    await expect(shinyFrame.locator('input[name="months"][value="5"]')).not.toBeChecked({ timeout: 10000 });
  });

});