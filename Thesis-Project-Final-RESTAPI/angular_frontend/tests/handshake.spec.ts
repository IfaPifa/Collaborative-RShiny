import { test, expect } from '@playwright/test';
import { login, createCollabSession, joinCollabSession } from './helpers';

test('Alice and Bob Collaborative Handshake', async ({ browser }) => {
  test.setTimeout(60000);

  const aliceCtx = await browser.newContext();
  const bobCtx = await browser.newContext();
  const alicePage = await aliceCtx.newPage();
  const bobPage = await bobCtx.newPage();

  await login(alicePage, 'alice');
  const sessionId = await createCollabSession(alicePage, 'Collaborative Calculator', 'Handshake Test');

  await login(bobPage, 'bob');
  await joinCollabSession(bobPage, sessionId);

  // Verify WebSocket presence — each user sees the other's avatar
  await expect(alicePage.locator('.bg-indigo-500', { hasText: 'B' })).toBeVisible({ timeout: 10000 });
  await expect(bobPage.locator('.bg-indigo-500', { hasText: 'A' })).toBeVisible({ timeout: 10000 });

  await aliceCtx.close();
  await bobCtx.close();
});
