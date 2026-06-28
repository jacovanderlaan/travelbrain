# Travel Curation Platform

An editorial **curation** engine for travel: a curated canon of trusted sources
(magazines, books, blogs, critics) emits structured **evidence** about venues; an
explicit, versioned **taste profile** scores venues into a shortlist; a human
**approves**; approved venues feed an AI drafting pipeline that writes in your
voice, fact-checked against the evidence, and publishes to affiliate-monetised sites.

This is the **editorial curation model** (taste + provenance as the moat) — not the
broad programmatic / price-data model. Both are described in the design reference:
`D:/vault/.../2026-06-27 Sat/data-ai-affiliate-platform-reference.md` (Part II).

> Target group for the first profile: **adults / design-led / quiet** — no kids,
> stylish, sensitive. Hard exclusions (family, chain, party) + weighted positive
> signals (adults-preferred, design coverage, independent, intimate).

## What's built (the brain)

```
travel-curation/
└── brain/
    ├── schema.sql      # DuckDB DDL: sources, venues, mentions, taste rubric,
    │                   #   curation_decision, content + provenance bridge
    ├── seed.sql        # 1 destination (Sicily/Palermo), 4 sources, 1 rubric, 3 venues
    ├── style_fit.sql   # the scoring "moat": hard-exclude gate + weighted signals
    │                   #   + source-authority x per-domain-competence corroboration
    ├── build_db.py     # creates curation.duckdb, applies schema, seeds, scores
    └── curation.duckdb # (generated; gitignored)
```

### Run it

```bash
cd travel-curation/brain
pip install duckdb
python build_db.py --reset
```

Expected shortlist from the seed:

```
  100.00  * shortlisted  Villa Igiea (hotel)          # adults-preferred + 2 in-domain mentions
   46.21    -            Gagini Social Restaurant      # below threshold: adults policy unknown
    0.00    -            Grand Resort Family Bay       # hard-excluded: family + chain
```

## The model in one diagram

```
canon (any medium) -> fact_mention (evidence) -> style_fit -> shortlist -> your approval -> draft -> publish
   dim_source            grain: one source        sec 16        curation_      (human)      agent
   + competence          x one venue x once                     decision                    pipeline
```

Key design calls (full rationale in the reference doc):

- **Heterogeneous in, conformed out** — every source type (magazine, book,
  podcast, critic) emits the same `fact_mention` record.
- **Authority is per-source AND per-domain** (`source_competence`) — a food critic
  doesn't lend weight to a hotel's *design* credibility.
- **Independent corroboration > volume** — per-source contribution is capped and
  summed with diminishing returns; three in-domain sources beat ten mentions from one.
- **Unknowns are flags, not penalties** — `adults_only = NULL` surfaces "research
  needed" on the shortlist rather than scoring zero.
- **Copyright discipline is in the schema** — store structured signals + provenance,
  never the publication's paragraphs; `quote_short` is rare, short, attributed.

## Next steps (not yet built)

1. **Research agent** — pull candidate venues for a destination from the canon +
   web research, extract `fact_mention` rows, score, present a shortlist.
2. **Drafting pipeline** — the brief -> draft -> fact-check -> editorial -> persist
   loop (reference doc sec 8), grounded against mentions, in your editorial voice.
3. **MCP surface** — expose the brain to Claude so you curate conversationally
   (`get_shortlist`, `approve_venue`, `draft_page`).
4. **Astro multi-site** + **legal/scraping/affiliate-approval** — the two threads
   the design reference flags as still open.
