# Răboj website

The landing page for Răboj: a cloth-bound usage ledger that opens as you scroll, with a tally stick
notched in the margin. Built with [Astro](https://astro.build), React islands and Tailwind CSS.

```sh
yarn install
yarn start        # dev server on http://localhost:4321
yarn build        # type-check and build to dist/
yarn lint
```

Set `SITE_URL` when building for a domain other than `https://raboj.vercel.app`. It drives the
canonical URL, Open Graph image URLs, `robots.txt` and the sitemap.

## Structure

```
src/
  pages/
    index.astro              the page, composed from sections
    robots.txt.ts            robots.txt pointing at the sitemap
  show/
    layouts/BaseLayout/      HTML shell: meta tags, Open Graph, JSON-LD, font preloads
    sections/                one folder per ledger section (static Astro)
    islands/                 interactive React parts: the app popover, Pace, Menu bar
    components/              index cards, stamp, tick, tally stick, copy command
    styles/global.css        design tokens and shared ledger styles
  process/
    constants/               copy, demo accounts, providers, FAQ, links
    helpers/                 pure functions (metric values, the pace projection)
    seo/                     structured data for search engines
public/                      favicons, Open Graph image, web manifest
```

Fonts are self-hosted through Fontsource: the page makes no third-party requests.
The pace projection in `helpers` mirrors `PlanWindow.pace` in the app.
