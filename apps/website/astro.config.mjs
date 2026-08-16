import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

if ((process.env.NODE_ENV === 'production' || process.env.CI) && !process.env.SITE_URL) {
  throw new Error('SITE_URL env var is required for production builds');
}

const siteUrl = process.env.SITE_URL ?? 'http://localhost:4321';

export default defineConfig({
  site: siteUrl,
  base: '/',
  output: 'static',
  trailingSlash: 'always',
  integrations: [sitemap()],
});
