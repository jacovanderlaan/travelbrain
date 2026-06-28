# Travel Curation Site (Astro)

Stage 5 of the [vertical slice](../PLAN.md): renders the curated page from the brain
as a fast, static, crawlable site. Free to build, free to host.

## How it works

```
curation.duckdb ──(export_content.py)──> src/content.json ──(Astro build)──> dist/*.html
```

- `scripts/export_content.py` — build-time export: reads `dim_content` (ready/published
  pages) for the active site, resolves affiliate links from `map_venue_provider` +
  `dim_provider.tracking_template`, attaches per-venue source provenance. Writes
  `src/content.json`. DuckDB stays out of the Node toolchain; the brain is the source of truth.
- `src/pages/index.astro` — renders the markdown body + a shortlist panel showing each
  venue's sources and a booking link (or an honest "no booking link yet" where no
  affiliate mapping exists — never a fabricated URL).

## Run it

```bash
cd travel-curation/site
npm install
npm run dev        # exports content.json, then serves at localhost:4321
npm run build      # exports + builds static HTML into dist/
npm run preview    # preview the built site
```

`npm run dev`/`build` run the Python export first (needs `duckdb` in the active
Python env and a built `../brain/curation.duckdb`).

## Deploy free

Static output hosts free on **Cloudflare Pages** (no bandwidth cap) or **Netlify**:
build command `npm run build`, output dir `dist`. You get a free `*.pages.dev` /
`*.netlify.app` URL; a custom domain (~€10/yr) is the only optional cost.

## Status

One page renders end-to-end (Palermo, adults/design-led). Affiliate links show the
honest "no link yet" state until venue→provider mappings are added to the brain.
Footer shows the source brief hash + version — provenance visible on the page itself.
