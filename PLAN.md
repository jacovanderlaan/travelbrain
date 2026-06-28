# Travel Curation — Vertical Slice Plan

Goal: **one destination, end-to-end, demo-ready.** Prove the whole chain
(canon → mentions → style_fit → your approval → one published page in your voice)
on a single destination before generalising anything. Demo-first; affiliate income
is upside, not the success metric.

Anchor destination: **Sicily / Palermo** (already seeded). Taste profile:
**adults / design-led / quiet** (already seeded, v1).

## Definition of done (the demo artifact)

A single published page (one venue profile or a "where to stay in Palermo"
shortlist), where you can show, live:

1. The **rules** (taste rubric) doing the trustworthy filtering — deterministic, queryable.
2. The **AI** writing only the prose, grounded against frozen evidence.
3. **Full provenance** — every claim traces from the published sentence back to a
   named source (`bridge_content_subject` → `fact_mention` → `dim_source`).
4. **Human-in-the-loop** — the venue was on a shortlist *you* approved.

That provenance trail IS the positioning pitch: rules do the trustworthy part,
AI does the prose, and nothing ships you didn't bless.

## Stages

### Stage 1 — Brain (DONE)
`brain/schema.sql` + `seed.sql` + `style_fit.sql` + `build_db.py`. Verified:
Villa Igiea 100/shortlisted, family-chain 0/excluded, unknown-policy 46/below.

### Stage 2 — Conversational curation surface (MCP) — NEXT
Expose the brain to Claude so you curate by talking, not by SQL. Read-only +
decision tools (see `mcp-server/README.md`):
- `get_shortlist(destination, taste?)` — ranked candidates + style_fit + open-question flags
- `get_venue(venue_sk)` — full evidence dossier (every mention, source, descriptor)
- `list_sources()` / `get_canon()` — inspect + sanity-check the source canon
- `approve_venue(venue_sk, decision, rationale)` — record your call (writes `curation_decision`)
- `add_mention(...)` / `add_venue(...)` — capture evidence you find while researching

This is the interface for "approve shortlists, trust the rest" — it's part of the
slice, not a separate project.

### Stage 3 — Research agent (fill the canon for one destination)
A script (or Claude session driven by the MCP tools) that, for Palermo:
1. pulls candidate venues from the seeded canon + targeted web research,
2. extracts `fact_mention` rows (source, sentiment, descriptors, accolade, provenance),
3. re-runs `style_fit.sql`,
4. presents you a shortlist with provenance + "research needed" flags.
Target: ~10–15 real venues with ≥1 in-domain mention each. Keep it honest —
log what was NOT covered (sources not read, policies unconfirmed).

### Stage 4 — Drafting pipeline (one page, in your voice)
The brief → draft → fact-check → editorial → persist loop (reference doc sec 8),
repurposed for curation:
- **Brief** = approved venue + its mentions + style_fit + your rationale, hashed (frozen).
- **Writer agent** (Sonnet) — prose only, every claim from the brief, claims itemised,
  system prompt encodes YOUR editorial voice + the taste profile.
- **Fact-check** (Haiku) — each claim grounded against the brief, not the web.
- **Persist** — `dim_content` + `bridge_content_subject` (venue + the justifying mentions).

### Stage 5 — Render one page (Astro, minimal)
A single Astro page reading `dim_content` at build time, affiliate link resolved
from `map_venue_provider` + `dim_provider.tracking_template`. Just enough to be a
real, shareable URL — not the multi-site abstraction yet.

## Sequencing notes

- **Stages 2–3 are the highest-leverage demo content** — the provenance + rules +
  human-approval story is visible even before a page is rendered. If time is short,
  a great `get_shortlist` + `get_venue` demo already sells the concept.
- **Do NOT build the multi-site / many-destinations abstraction** until one slice is
  fully working (reference doc sec 4 trap).
- Voice fidelity in Stage 4 matters most for the demo — pull the writer's voice from
  real samples (see memory `ai-context-voice-layer`), not generic "travel blog" tone.

## Open threads (deferred, from the design reference)
- Astro multi-site config structure (sec 4) — only after slice #2.
- Legal / scraping / affiliate-approval detail (NL/EU) — before any real scraping or
  affiliate-program application.
