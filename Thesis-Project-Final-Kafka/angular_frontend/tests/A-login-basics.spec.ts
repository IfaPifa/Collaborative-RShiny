import { test, expect } from '@playwright/test';

test('Login page loads', async ({ page }) => {
  await page.goto('/login');
  await expect(page.locator('input[name="username"]')).toBeVisible();
  await expect(page.locator('input[name="password"]')).toBeVisible();
  await expect(page.locator('button[type="submit"]')).toBeVisible();
});

test('Library page requires authentication', async ({ page }) => {
  await page.goto('/library');
  // Should redirect to login if not authenticated
  await expect(page).toHaveURL(/login/);
});
