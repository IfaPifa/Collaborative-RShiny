import { test, expect } from '@playwright/test';

test('REST Real-Time Data Synchronization', async ({ browser }) => {
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
  await alicePage.fill('input[placeholder="e.g. Q1 Budget Review"]', 'REST Sync Test');
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
  const joinInput = bobPage.locator('input[placeholder="Paste Session UUID here..."]');
  await expect(joinInput).toBeVisible({ timeout: 10000 });
  await joinInput.fill(sessionId!);
  await bobPage.click('button:has-text("Join Room")');
  await bobPage.waitForURL(`**/workspace/${sessionId}`);

  // --- 2. WAIT FOR REST UI TO BOOT ---
  const aliceFrame = alicePage.frameLocator('iframe');
  const bobFrame = bobPage.frameLocator('iframe');

  // FIX: Look for the new REST indicator instead of Kafka's "✅ Online"
  await expect(aliceFrame.locator('text=🌐 Async GET/POST')).toBeVisible({ timeout: 15000 });
  await expect(bobFrame.locator('text=🌐 Async GET/POST')).toBeVisible({ timeout: 15000 });

  // (Removed the 4-second Kafka stabilization wait! REST is instantly ready.)

  // --- 3. INTERACT WITH THE SHINY APP ---
  await aliceFrame.locator('#num1').fill('10');
  await aliceFrame.locator('#num2').fill('25');
  await aliceFrame.locator('button#calculate').click();

  // Verify Backend calculated it (via Spring Boot -> Plumber -> Redis)
  await expect(aliceFrame.locator('#result')).toHaveText('35', { timeout: 15000 });

  // --- 4. VERIFY REST POLLING ON BOB'S SCREEN ---
  // Bob's UI will naturally poll Redis and pull this down within 500ms
  await expect(bobFrame.locator('#num1')).toHaveValue('10', { timeout: 15000 });
  await expect(bobFrame.locator('#num2')).toHaveValue('25', { timeout: 15000 });
  
  await expect(bobFrame.locator('text=35')).toBeVisible({ timeout: 15000 });

  console.log('✅ REST Collaborative Sync Test passed!');

  await aliceContext.close();
  await bobContext.close();
});