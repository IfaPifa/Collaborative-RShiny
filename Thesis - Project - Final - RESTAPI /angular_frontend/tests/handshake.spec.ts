import { test, expect } from '@playwright/test';

test('Alice and Bob Collaborative Handshake', async ({ browser }) => {
  // 1. Setup two completely isolated browser contexts (like two incognito windows)
  const aliceContext = await browser.newContext();
  const bobContext = await browser.newContext();

  const alicePage = await aliceContext.newPage();
  const bobPage = await bobContext.newPage();

  // --- ALICE LOGS IN & CREATES SESSION ---
  await alicePage.goto('/login');
  
  // Note: Adjust 'alice' and 'password' if your database requires different test users
  await alicePage.fill('input[name="username"]', 'alice'); 
  await alicePage.fill('input[name="password"]', 'password');
  await alicePage.click('button[type="submit"]');

  await alicePage.waitForURL('**/library');
  await alicePage.goto('/collab-hub');

  // Alice creates a new session
  await alicePage.click('button:has-text("+ New Session")');
  await alicePage.fill('input[placeholder="e.g. Q1 Budget Review"]', 'Thesis Test Session');
  
  // Select the first available Shiny app from the dropdown (index 1 skips the disabled placeholder)
  await alicePage.locator('select').selectOption({ index: 1 });
  await alicePage.click('button:has-text("Create & Enter")');

  // Wait for workspace to load and extract the Session UUID from the URL
  await alicePage.waitForURL('**/workspace/*');
  const workspaceUrl = alicePage.url();
  const sessionId = workspaceUrl.split('/').pop();
  expect(sessionId).toBeTruthy(); // Ensure the ID was created

  // --- BOB LOGS IN & JOINS SESSION ---
  await bobPage.goto('/login');
  await bobPage.fill('input[name="username"]', 'bob');
  await bobPage.fill('input[name="password"]', 'password');
  await bobPage.click('button[type="submit"]');

  await bobPage.waitForURL('**/library');
  await bobPage.goto('/collab-hub');

  // Bob pastes the UUID into the join box
  await bobPage.fill('input[placeholder="Paste Session UUID here..."]', sessionId!);
  await bobPage.click('button:has-text("Join Room")');

  // Bob should be automatically routed to the workspace
  await bobPage.waitForURL(`**/workspace/${sessionId}`);

  // --- VERIFY WEBSOCKET PRESENCE ---
  // If the WebSockets are working, Alice's screen should show Bob's 'B' avatar, 
  // and Bob's screen should show Alice's 'A' avatar.
  await expect(alicePage.locator('.bg-indigo-500', { hasText: 'B' })).toBeVisible({ timeout: 10000 });
  await expect(bobPage.locator('.bg-indigo-500', { hasText: 'A' })).toBeVisible({ timeout: 10000 });

  console.log('✅ Handshake successful! Both users are in the room and see each other.');

  // Clean up
  await aliceContext.close();
  await bobContext.close();
});