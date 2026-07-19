const { test, expect } = require('@playwright/test');
const path = require('path');

const unexpected = (page) => {
  const errors = [];
  const failed = [];
  page.on('pageerror', () => errors.push('pageerror'));
  page.on('console', message => {
    if (message.type() === 'error') errors.push('console');
  });
  page.on('requestfailed', request => {
    if (request.failure()?.errorText !== 'net::ERR_ABORTED') failed.push('request');
  });
  return () => expect({ errors, failed }).toEqual({ errors: [], failed: [] });
};

async function loginReady(page) {
  await expect.poll(() => page.evaluate(() => {
    return !document.querySelector('#boot-loader') && document.querySelectorAll('flutter-view').length === 1;
  }), { timeout: 60_000 }).toBe(true);
  const semantics = page.locator('flt-semantics-placeholder');
  if (await semantics.count()) {
    await semantics.focus();
    await page.keyboard.press('Enter');
  }
  await expect(page.getByRole('textbox', { name: 'رقم الهاتف' })).toBeVisible({ timeout: 60_000 });
  await expect(page.getByRole('textbox', { name: 'الرمز السري' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'دخول' })).toBeEnabled();
}

test('bootstrap cold load and two reloads retire one loader', async ({ page }) => {
  const clean = unexpected(page);
  await page.goto('/');
  await expect(page.locator('#boot-loader')).toHaveCount(1);
  await loginReady(page);
  await expect(page).toHaveTitle('زاد المحظرة');
  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
  await expect(page.locator('#boot-loader')).toHaveCount(0);
  await page.reload();
  await loginReady(page);
  await page.reload();
  await loginReady(page);
  clean();
});

test('bootstrap mobile layout has no overflow after loader retirement', async ({ page }) => {
  const clean = unexpected(page);
  await page.setViewportSize({ width: 320, height: 800 });
  await page.goto('/');
  await loginReady(page);
  await expect(page.locator('#boot-loader')).toHaveCount(0);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  clean();
});

test('production bootstrap helper retry is sanitized and one-shot', async ({ page }) => {
  const messages = [];
  page.on('console', message => messages.push(message.text()));
  await page.goto('/');
  await page.setContent('<div id="boot-loader"></div>');
  await page.addScriptTag({ path: path.resolve(__dirname, '../web/bootstrap_helpers.js') });
  await page.evaluate(() => {
    const loader = document.getElementById('boot-loader');
    const lifecycle = window.ZadBootstrap.create(loader, () => window.__reloads = (window.__reloads || 0) + 1);
    lifecycle.fail(); lifecycle.fail();
  });
  await expect(page.getByText('تعذر تشغيل التطبيق. يرجى تحديث الصفحة.')).toBeVisible();
  await expect(page.getByRole('button', { name: 'إعادة المحاولة' })).toBeVisible();
  await page.getByRole('button', { name: 'إعادة المحاولة' }).click();
  await page.getByRole('button', { name: 'إعادة المحاولة' }).click();
  expect(await page.evaluate(() => window.__reloads)).toBe(1);
  expect(messages.filter(message => message === 'ZAD_BOOTSTRAP_FAILED')).toHaveLength(1);
});
