import { test, expect } from '@playwright/test';

test('Kafka Real-Time Data Synchronization', async ({ browser }) => {
  const aliceContext = await browser.newContext();
  const bobContext = await browser.newContext();
  const alicePage = await aliceContext.newPage();
  const bobPage = await bobContext.newPage();

  // --- 1. SETUP THE SESSION ---
  await alicePage.goto('/login');
  await alicePage.fill('input[name="username"]', 'alice');
  await alicePage.fill('input[name="password"]', 'password');
  await alicePage.click('button[type="submit"]');
  await alicePage.waitForURL('**/library'); 
  
  await alicePage.goto('/collab-hub');
  await alicePage.click('button:has-text("+ New Session")');
  await alicePage.fill('input[placeholder="e.g. Q1 Budget Review"]', 'Kafka Sync Test');
  await alicePage.locator('select').selectOption({ index: 1 });
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

  // --- 2. WAIT FOR KAFKA TO STABILIZE ---
  const aliceFrame = alicePage.frameLocator('iframe');
  const bobFrame = bobPage.frameLocator('iframe');

  // Wait for the R-Shiny UI to boot
  await expect(aliceFrame.locator('text=✅ Online')).toBeVisible({ timeout: 15000 });
  await expect(bobFrame.locator('text=✅ Online')).toBeVisible({ timeout: 15000 });

  // FIX: The Kafka Stabilization Delay
  // Give librdkafka 4 seconds to successfully negotiate consumer group partitions 
  // before Alice starts firing messages into the void.
  await alicePage.waitForTimeout(4000);

  // --- 3. INTERACT WITH THE SHINY APP ---
  await aliceFrame.locator('#num1').fill('10');
  await aliceFrame.locator('#num2').fill('25');
  await aliceFrame.locator('button#calculate').click();

  // Verify Backend calculated it
  await expect(aliceFrame.locator('#result')).toHaveText('35', { timeout: 15000 });

  // --- 4. VERIFY KAFKA SYNC ON BOB'S SCREEN ---
  // Bob should now successfully receive the payload and update his inputs
  await expect(bobFrame.locator('#num1')).toHaveValue('10', { timeout: 15000 });
  await expect(bobFrame.locator('#num2')).toHaveValue('25', { timeout: 15000 });
  
  await expect(bobFrame.locator('text=Last updated by: alice')).toBeVisible();

  console.log('✅ Kafka Sync test passed! Messages are routing successfully through the microservices.');

  await aliceContext.close();
  await bobContext.close();
});