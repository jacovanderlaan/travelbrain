# Deploying the site (GitHub Pages)

The site auto-deploys to **GitHub Pages** via `.github/workflows/deploy-travel-curation.yml`
on every push that touches `travel-curation/`. It builds the brain + the Astro site on
CI and publishes `travel-curation/site/dist`.

Live URL (once enabled): **https://jacovanderlaan.github.io/ai/**

## One-time setup (you must do this once in the GitHub UI)

1. Go to the repo on GitHub → **Settings → Pages**.
2. Under **Build and deployment → Source**, choose **GitHub Actions** (not "Deploy from a branch").
3. That's it. The next push to `travel-curation/**` (or a manual run) deploys.

To trigger manually: repo → **Actions → "Deploy travel-curation site" → Run workflow**.

## How it works on CI

- `actions/setup-node` + `setup-python` (DuckDB installed for the content export).
- `python ../brain/build_db.py --reset` rebuilds the brain (the .duckdb is gitignored).
- The venue pages live in `dim_content`, which `--reset` wipes, so CI re-drafts them from
  the committed `pipeline/*_draft.json` files (no API key needed — uses `--draft-file`).
- `npm run build` (which runs the Python export first) → `dist/` → uploaded to Pages.

## Sub-path note

The repo is `ai`, so Pages serves at `…/ai/` — `astro.config.mjs` sets `base: '/ai'`
and all internal links/images are prefixed via `import.meta.env.BASE_URL`. If you ever
move this to its own repo or a custom domain at root, set the `BASE` env to `/` (or
update the config) and rebuild.

## Local preview (matches production base)

```bash
cd travel-curation/site
npm run build && npm run preview   # serves at /ai/ like production
# or: npm run dev                  # dev server (base applies too)
```
