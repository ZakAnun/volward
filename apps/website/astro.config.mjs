import { readFileSync } from 'node:fs';
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

if ((process.env.NODE_ENV === 'production' || process.env.CI) && !process.env.SITE_URL) {
  throw new Error('SITE_URL env var is required for production builds');
}

const siteUrl = process.env.SITE_URL ?? 'http://localhost:4321';
const aptabaseWebKey = process.env.APTABASE_WEB_KEY ?? '';
const aptabaseHost = process.env.APTABASE_HOST ?? 'https://analytics.volwardapp.com';
const packageJson = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf-8'));
const websiteVersion = typeof packageJson.version === 'string' ? packageJson.version : '0.0.0';

export default defineConfig({
  site: siteUrl,
  base: '/',
  output: 'static',
  trailingSlash: 'always',
  integrations: [sitemap()],
  vite: {
    define: {
      __APTABASE_WEB_KEY__: JSON.stringify(aptabaseWebKey),
      __APTABASE_HOST__: JSON.stringify(aptabaseHost),
      __VOLWARD_WEBSITE_VERSION__: JSON.stringify(websiteVersion),
    },
  },
});
