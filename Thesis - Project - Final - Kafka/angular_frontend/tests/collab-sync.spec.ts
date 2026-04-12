import { test, expect } from '@playwright/test';

test('Kafka Real-Time Data Synchronization', async ({ browser }) => {
  const aliceContext = await browser.newContext();
  const bobContext = await browser.newContext();
  const alicePage = await aliceContext.newPage();
  const bobPage = await bobContext.newPage();

  // --- 1. SETUP THE SESSION ---
  // Alice logs in and creates a session
  await alicePage.goto('/login');
  await alicePage.fill('input[name="username"]', 'alice');
  await alicePage.fill('input[name="password"]', 'password');
  await alicePage.click('button[type="submit"]');
  
  // WAIT FOR LOGIN TO FINISH BEFORE NAVIGATING
  await alicePage.waitForURL('**/library'); 
  
  await alicePage.goto('/collab-hub');
  await alicePage.click('button:has-text("+ New Session")');
  await alicePage.fill('input[placeholder="e.g. Q1 Budget Review"]', 'Kafka Sync Test');
  await alicePage.locator('select').selectOption({ index: 1 });
  await alicePage.click('button:has-text("Create & Enter")');
  await alicePage.waitForURL('**/workspace/*');
  
  const sessionId = alicePage.url().split('/').pop();

  // Bob logs in and joins the session
  await bobPage.goto('/login');
  await bobPage.fill('input[name="username"]', 'bob');
  await bobPage.fill('input[name="password"]', 'password');
  await bobPage.click('button[type="submit"]');
  
  // WAIT FOR LOGIN TO FINISH BEFORE NAVIGATING
  await bobPage.waitForURL('**/library'); 
  
  await bobPage.goto('/collab-hub');
  await bobPage.fill('input[placeholder="Paste Session UUID here..."]', sessionId!);
  await bobPage.click('button:has-text("Join Room")');
  await bobPage.waitForURL(`**/workspace/${sessionId}`);

  // --- 2. INTERACT WITH THE SHINY APP ---
  const aliceFrame = alicePage.frameLocator('iframe');
  const bobFrame = bobPage.frameLocator('iframe');

  // Wait for Shiny to boot and Kafka to connect inside the iframe
  await expect(aliceFrame.locator('text=✅ Online')).toBeVisible({ timeout: 15000 });
  await expect(bobFrame.locator('text=✅ Online')).toBeVisible({ timeout: 15000 });

  // Alice changes the inputs and clicks Calculate
  await aliceFrame.locator('#num1').fill('10');
  await aliceFrame.locator('#num2').fill('25');
  await aliceFrame.locator('button#calculate').click();

  // If this fails, it proves the backend math service is broken.
  await expect(aliceFrame.locator('h1')).toHaveText('35', { timeout: 15000 });

  // --- 3. VERIFY KAFKA SYNC ON BOB'S SCREEN ---
  // Bob's UI should update via Kafka to show the new inputs and who sent them
  // We wait for Bob's screen to receive the Kafka consumer payload and render it
  await expect(bobFrame.locator('#num1')).toHaveValue('10', { timeout: 30000 });
  await expect(bobFrame.locator('#num2')).toHaveValue('25', { timeout: 30000 });
  
  // Verify the UI shows that Alice was the last one to update the state
  await expect(bobFrame.locator('text=Last updated by: alice')).toBeVisible();

  console.log('✅ Kafka Sync test passed! Messages are routing successfully through the microservices.');

  await aliceContext.close();
  await bobContext.close();
});