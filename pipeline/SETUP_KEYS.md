# Setting up the optional API keys

All three keys are **free, read-only, revocable** → low-risk tier → store as Windows
**User env vars** (per the secrets pattern). None is required; each just unlocks a feature.

## Unsplash (venue images)

1. Go to https://unsplash.com/developers → "Register as a developer" → "New Application"
   (accept the API terms; a demo app is fine — 50 requests/hour, plenty for curation).
2. Copy the **Access Key** (not the Secret Key — we only read).
3. Set it as a User env var (PowerShell):

   ```powershell
   [Environment]::SetEnvironmentVariable('UNSPLASH_ACCESS_KEY','<your-access-key>','User')
   ```

4. **Open a new terminal** (env vars load at shell start), then:

   ```bash
   cd travel-curation/pipeline
   pip install httpx
   python fetch_images.py --all        # fetch candidates for all shortlisted venues
   python fetch_images.py --list Gagini   # review candidates for a venue
   python fetch_images.py --approve <image_sk>   # approve one (clears the others)
   cd ../site && npm run build         # picture appears on the page with credit
   ```

## Pexels (alternative/additional image source) — optional

Same idea: https://www.pexels.com/api/ → get the key →
`[Environment]::SetEnvironmentVariable('PEXELS_API_KEY','<key>','User')`.
The fetcher uses whichever key(s) are present.

## Anthropic (live page generation) — optional

Only needed for unattended `draft_page.py` runs (the page is already drafted; this is
for regenerating). `[Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY','<key>','User')`.

## Attribution note (important, not optional)

Unsplash & Pexels free tiers REQUIRE crediting the photographer with a link back.
The pipeline stores the credit and the page renders it automatically — don't strip it.
