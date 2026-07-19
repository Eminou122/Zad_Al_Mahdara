const { defineConfig } = require('@playwright/test');

module.exports = defineConfig({
  testDir: __dirname,
  timeout: 60_000,
  retries: 0,
  reporter: 'line',
  use: {
    baseURL: 'http://127.0.0.1:4180',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'off',
  },
  webServer: {
    command: 'python -m http.server 4180 --directory build/web',
    cwd: require('path').resolve(__dirname, '..'),
    url: 'http://127.0.0.1:4180',
    reuseExistingServer: false,
    timeout: 15_000,
  },
});
