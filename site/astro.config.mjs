import { defineConfig } from 'astro/config';
import react from '@astrojs/react';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';

import { aliases } from './configs/folder-paths-aliases.ts';

const SITE_URL = process.env.SITE_URL ?? 'https://raboj.vercel.app';

export default defineConfig({
  compressHTML: true,
  integrations: [react(), sitemap()],
  site: SITE_URL,
  trailingSlash: 'ignore',
  vite: {
    plugins: [tailwindcss()],
    resolve: { alias: aliases },
    server: { fs: { allow: [aliases.Root, aliases.Docs] } },
  },
});
