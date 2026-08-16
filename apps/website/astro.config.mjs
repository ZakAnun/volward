import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

const siteUrl = process.env.SITE_URL ?? 'http://localhost:4321';

export default defineConfig({
  site: siteUrl,
  base: '/',
  output: 'static',
  trailingSlash: 'always',
  integrations: [sitemap()],
});
