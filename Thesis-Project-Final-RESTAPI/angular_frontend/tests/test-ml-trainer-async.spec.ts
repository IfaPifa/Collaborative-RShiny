import { test, expect } from '@playwright/test';

// 60s timeout to allow for the 7.5s Random Forest simulation plus UI rendering
test.setTimeout(60000);

test('ML Trainer: Collaborative Async Compute Sync', async ({ browser }) => {
  const aliceContext = await browser.newContext();
  const bobContext = await browser.newContext();
  const alicePage = await aliceContext.newPage();
  const bobPage = await bobContext.newPage();

  // --- 1. ALICE: CREATE SESSION ---
  await alicePage.goto('/login');
  await alicePage.fill('input[name="username"]', 'alice');
  await alicePage.fill('input[name="password"]', 'password');
  await alicePage.click('button[type="submit"]');
  await alicePage.waitForURL('**/library'); 
  
  await alicePage.goto('/collab-hub');
  await alicePage.click('button:has-text("+ New Session")');
  await alicePage.fill('input[placeholder="e.g. Q1 Budget Review"]', 'ML Collab Test');
  await alicePage.locator('select').selectOption({ label: 'Habitat Suitability AI' });
  await alicePage.click('button:has-text("Create & Enter")');
  await alicePage.waitForURL('**/workspace/*');
  
  const sessionId = alicePage.url().split('/').pop();

  // --- 2. BOB: JOIN SESSION ---
  await bobPage.goto('/login');
  await bobPage.fill('input[name="username"]', 'bob');
  await bobPage.fill('input[name="password"]', 'password');
  await bobPage.click('button[type="submit"]');
  await bobPage.waitForURL('**/library'); 
  
  await bobPage.goto('/collab-hub');
  const joinInput = bobPage.locator('input[placeholder="Paste Session UUID here..."]');
  await expect(joinInput).toBeVisible({ timeout: 10000 });
  await joinInput.fill(sessionId!);
  await bobPage.click('button:has-text("Join Room")');
  await bobPage.waitForURL(`**/workspace/${sessionId}`);

  // --- 3. KAFKA MESH STABILIZATION ---
  const aliceFrame = alicePage.frameLocator('iframe');
  const bobFrame = bobPage.frameLocator('iframe');

  // Wait for the Shiny Apps to render
  await expect(aliceFrame.locator('text=Eco-ML: Biodiversity Predictor')).toBeVisible({ timeout: 15000 });
  await expect(bobFrame.locator('text=Eco-ML: Biodiversity Predictor')).toBeVisible({ timeout: 15000 });

  // 5-Second hard stabilization to let librdkafka assign partitions to Bob
  await alicePage.waitForTimeout(5000);

  // --- 4. ALICE TRIGGERS COMPUTE ---
  await aliceFrame.locator('button#train_btn').click();

  // --- 5. BOB OBSERVES THE ASYNC STREAM ---
  // PROOF OF ARCHITECTURE: Bob did not click anything, but his UI reacts to Alice's command
  
  // Wait explicitly for the button to disable. We give it 15 seconds to account for 
  // Kafka traversal, R backend wakeup time, and the initial 1.5s sleep in the first chunk.
  await expect(bobFrame.locator('button#train_btn')).toBeDisabled({ timeout: 15000 });

  // Verify the progress bar has actually moved past 0% (checking the inner text of bslib's bar)
  await expect(bobFrame.locator('.progress-bar')).not.toHaveText('0%', { timeout: 5000 });

  // --- 6. VERIFY FINAL RECONCILIATION ---
  // Wait for the final TRAINING_COMPLETE payload to unlock Bob's UI
  await expect(bobFrame.locator('button#train_btn')).toBeEnabled({ timeout: 30000 });

  // Bob should see the final SVG charts rendered from the Random Forest JSON payload
  await expect(bobFrame.locator('#importance_plot svg').first()).toBeVisible({ timeout: 15000 });
  await expect(bobFrame.locator('#loss_plot svg').first()).toBeVisible({ timeout: 15000 });

  console.log('✅ ML Trainer Collab passed! Alice triggered the math, Bob streamed the epochs.');

  await aliceContext.close();
  await bobContext.close();
});