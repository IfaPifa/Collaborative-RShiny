import { Page, expect } from '@playwright/test';

/**
 * Log in as a user. All test users share password 'password'.
 */
export async function login(page: Page, username: string) {
  await page.goto('/login');
  await page.fill('input[name="username"]', username);
  await page.fill('input[name="password"]', 'password');
  await page.click('button[type="submit"]');
  await page.waitForURL('**/library');
}

/**
 * Create a collaborative session from the collab-hub and return the sessionId.
 */
export async function createCollabSession(page: Page, appName: string, sessionName: string): Promise<string> {
  await page.goto('/collab-hub');
  await page.click('button:has-text("+ New Session")');
  await page.fill('input[placeholder="e.g. Q1 Budget Review"]', sessionName);
  await page.locator('select').selectOption({ label: appName });
  await page.click('button:has-text("Create & Enter")');
  await page.waitForURL('**/workspace/*');
  return page.url().split('/').pop()!;
}

/**
 * Join an existing collaborative session by pasting the UUID.
 */
export async function joinCollabSession(page: Page, sessionId: string) {
  await page.goto('/collab-hub');
  const joinInput = page.locator('input[placeholder="Paste Session UUID here..."]');
  await expect(joinInput).toBeVisible({ timeout: 10000 });
  await joinInput.fill(sessionId);
  await page.click('button:has-text("Join Room")');
  await page.waitForURL(`**/workspace/${sessionId}`);
}

/**
 * Launch an app in solo mode by clicking "Launch Solo" on the matching card.
 */
export async function launchSolo(page: Page, appName: string) {
  const appCard = page.locator('.bg-white.rounded-xl').filter({
    has: page.locator('h3', { hasText: appName })
  });
  await appCard.locator('button:has-text("Launch Solo")').click();
  await page.waitForURL('**/workspace/solo');
}

/**
 * Wait for the Shiny iframe to boot by checking for the connection status text.
 */
export async function waitForShinyBoot(frame: ReturnType<Page['frameLocator']>, statusText = 'Async GET/POST') {
  await expect(frame.locator(`text=${statusText}`)).toBeVisible({ timeout: 20000 });
}

/**
 * Set a Shiny numericInput value properly.
 * Playwright's fill() doesn't trigger Shiny's input binding events.
 * We need to triple-click (select all), type the value, then press Tab to trigger the change event.
 */
export async function setShinyNumericInput(frame: ReturnType<Page['frameLocator']>, selector: string, value: string) {
  const input = frame.locator(selector);
  await input.click({ clickCount: 3 }); // select all existing text
  await input.type(value);
  await input.press('Tab'); // triggers Shiny's change event
}

/**
 * Save the current state via the Angular "Save State" modal.
 */
export async function saveState(page: Page, saveName: string) {
  await page.click('button:has-text("Save State")');
  await page.fill('input[placeholder="Name this save..."]', saveName);
  page.once('dialog', dialog => dialog.accept());
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await page.waitForTimeout(1000);
}

/**
 * Demote a user from Editor to Viewer via the Manage Roles modal.
 * Waits for the user to appear in the active users list (WebSocket presence).
 */
export async function demoteUser(page: Page, username: string) {
  // Wait for the target user's avatar to appear (WebSocket JOIN must arrive first)
  await expect(page.locator(`text=${username}`).first()).toBeVisible({ timeout: 15000 });

  await page.locator('button', { hasText: '⚙️ Manage Roles' }).click();
  await expect(page.locator('h3', { hasText: 'Manage Team Roles' })).toBeVisible();

  // Find the row with the username and uncheck the Editor checkbox
  const userRow = page.locator('div.flex.justify-between').filter({ hasText: username });
  await expect(userRow).toBeVisible({ timeout: 5000 });
  const checkbox = userRow.locator('input[type="checkbox"]');
  await expect(checkbox).toBeChecked({ timeout: 5000 });
  await checkbox.uncheck();

  // Wait for the API call to complete
  await page.waitForTimeout(1000);

  await page.locator('button', { hasText: 'Done' }).click();
  await expect(page.locator('h3', { hasText: 'Manage Team Roles' })).toBeHidden();

  // Wait for the WebSocket ROLE_UPDATE to propagate to the demoted user's iframe
  await page.waitForTimeout(2000);
}
