import { defineConfig } from 'astro/config';

// Static output — builds crawlable HTML, free on GitHub Pages.
// Served at https://jacovanderlaan.github.io/travelbrain/ , so base = '/travelbrain'.
// (Override with BASE env at build time if the path ever changes — e.g. '/' for a custom domain.)
export default defineConfig({
  output: 'static',
  site: 'https://jacovanderlaan.github.io',
  base: process.env.BASE ?? '/travelbrain',
});
