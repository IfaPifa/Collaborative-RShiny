import { test, expect } from '@playwright/test';

// Increase global timeout to 60s to account for Kafka rebalancing and R-Shiny startup
test.setTimeout(60000);

test('Advanced Analytics: State-Only Collaborative Sync', async ({ browser }) => {
  const aliceContext = await browser.newContext();
  const bobContext = await browser.newContext();
  const alicePage = await aliceContext.newPage();
  const bobPage = await bobContext.newPage();

  // --- ALICE: LOGIN & CREATE SESSION ---
  await alicePage.goto('/login');
  await alicePage.fill('input[name="username"]', 'alice');
  await alicePage.fill('input[name="password"]', 'password');
  
  await Promise.all([
    alicePage.waitForURL('**/library'),
    alicePage.click('button[type="submit"]')
  ]);

  await alicePage.goto('/collab-hub');
  await alicePage.click('button:has-text("+ New Session")');
  await alicePage.fill('input[placeholder="e.g. Q1 Budget Review"]', 'Eco Dashboard Sync');
  await alicePage.locator('select').selectOption({ label: 'Advanced Visual Analytics' });
  
  await Promise.all([
    alicePage.waitForURL('**/workspace/*'),
    alicePage.click('button:has-text("Create & Enter")')
  ]);
  
  const sessionId = alicePage.url().split('/').pop();

  // --- BOB: LOGIN & JOIN SESSION ---
  await bobPage.goto('/login');
  await bobPage.fill('input[name="username"]', 'bob');
  await bobPage.fill('input[name="password"]', 'password');
  
  await Promise.all([
    bobPage.waitForURL('**/library'), 
    bobPage.click('button[type="submit"]')
  ]);

  await bobPage.goto('/collab-hub');
  const joinInput = bobPage.locator('input[placeholder="Paste Session UUID here..."]');
  await expect(joinInput).toBeVisible({ timeout: 10000 });
  await joinInput.fill(sessionId!);
  
  await Promise.all([
    bobPage.waitForURL(`**/workspace/${sessionId}`),
    bobPage.click('button:has-text("Join Room")')
  ]);

  // --- KAFKA MESH SYNCHRONIZATION ---
  const aliceFrame = alicePage.frameLocator('iframe');
  const bobFrame = bobPage.frameLocator('iframe');

  // 1. Wait for R-Shiny UI to render in both frames
  await expect(aliceFrame.locator('.navbar-brand')).toBeVisible({ timeout: 15000 });
  await expect(bobFrame.locator('.navbar-brand')).toBeVisible({ timeout: 15000 });

  // 2. READINESS CHECK: Wait for Bob's 'Sync' button to be ENABLED
  // In the R code, this button is enabled only after state$connected is TRUE.
  // This confirms Bob's Kafka consumer has successfully established its connection.
  await expect(bobFrame.locator('button#update_plot')).toBeEnabled({ timeout: 20000 });
  
  // 3. Stabilization buffer for Kafka Partition Assignment
  await alicePage.waitForTimeout(5000);

  // 4. Alice triggers state change
  const mayCheckbox = aliceFrame.locator('input[name="months"][value="5"]');
  await mayCheckbox.uncheck();

  const syncBadge = bobFrame.locator('span.badge');
  
  // 5. ROBUST RETRY LOOP
  // If the first message is missed due to the 'latest' offset reset, 
  // Alice will retry the sync trigger until Bob's UI reflects the update.
  let attempts = 0;
  let success = false;
  
  while (attempts < 3 && !success) {
    await aliceFrame.locator('button#update_plot').click();
    try {
      // Check for the "Synced by: alice" badge that appears on message receipt
      await expect(syncBadge).toContainText('Synced by: alice', { timeout: 8000 });
      success = true;
    } catch (e) {
      attempts++;
      console.log(`⚠️ Kafka Sync Attempt ${attempts} failed. Retrying click...`);
      if (attempts === 3) throw new Error("Collaborative sync failed after 3 attempts.");
    }
  }

  // Final verification: Bob's internal state must now match Alice's
  await expect(bobFrame.locator('input[name="months"][value="5"]')).not.toBeChecked();

  console.log('✅ Collaborative Handshake & Sync successful!');

  await aliceContext.close();
  await bobContext.close();
});