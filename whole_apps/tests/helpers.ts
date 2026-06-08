import { Page, expect } from '@playwright/test';

// Port mapping matching docker-compose.yml / nginx.conf
export const APPS = {
  calculator:          { port: 7080, name: 'Calculator' },
  analytics:           { port: 7081, name: 'Visual Analytics' },
  data_exchange:       { port: 7082, name: 'Data Exchange' },
  montecarlo:          { port: 7083, name: 'Monte Carlo' },
  map:                 { port: 7084, name: 'Geospatial Map' },
  anomaly_detector:    { port: 7086, name: 'Anomaly Detector' },
  analytics_advanced:  { port: 7087, name: 'Advanced Analytics' },
  ml_trainer:          { port: 7088, name: 'ML Trainer' },
} as const;

/**
 * Navigate to a monolithic Shiny app and wait for it to be ready.
 * Shiny apps render a <body> with class "shiny-busy" while loading,
 * then switch to "shiny-idle" when ready.
 */
export async function openApp(page: Page, appKey: keyof typeof APPS) {
  const app = APPS[appKey];
  await page.goto(`http://localhost:${app.port}`);
  // Wait for Shiny to finish initializing
  await page.waitForSelector('html.shiny-ready, body:not(.shiny-busy)', { timeout: 30000 });
  // Extra settle time for rendering
  await new Promise(resolve => setTimeout(resolve, 2000));
}

/**
 * Set a numeric input value in Shiny using triple-click + type + Tab.
 * Playwright's fill() doesn't trigger Shiny's input binding.
 */
export async function setShinyNumericInput(page: Page, selector: string, value: string) {
  const input = page.locator(selector);
  await input.click({ clickCount: 3 });
  await input.pressSequentially(value, { delay: 50 });
  await page.keyboard.press('Tab');
  await new Promise(resolve => setTimeout(resolve, 300));
}
