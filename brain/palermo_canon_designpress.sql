-- ============================================================
-- Palermo canon-gap pass: design-press coverage (Stage 3b)
-- Source-of-truth: deep-research run w31pm9qvp (2026-06-28), 3-vote verified.
--
-- HONEST RESULT: the design-press gap is mostly a VERIFIED NEGATIVE.
--   - ONE genuine new design-title find: Wallpaper* -> Cento 61.
--   - Two real venues with weaker/non-target coverage (Hotel Plaza Opera,
--     Morettino Caffe) added as research-flagged, no fabricated mentions.
--   - Monocle / Cereal / CNT etc. logged as verified negatives in source_review
--     + notes, so the canon remembers we checked and found nothing.
--
-- Runs AFTER palermo_research.sql (depends on its venues/sources existing).
-- Idempotent-ish via natural-key conflict targets; intended to run once.
-- ============================================================

-- ------------------------------------------------------------
-- 1. New source: Wallpaper* (design authority)
-- ------------------------------------------------------------
INSERT INTO dim_source (name, source_type, medium, authority_weight, editorial_lean, cadence, ingest_method, url_root, notes)
VALUES ('Wallpaper*', 'magazine', 'web', 0.88, ['design','architecture'], 'rolling', 'manual', 'https://www.wallpaper.com',
        'Design/architecture authority; thin Palermo coverage (one venue found: Cento 61, Oct 2022)')
ON CONFLICT (name) DO NOTHING;

INSERT INTO source_competence (source_sk, domain, weight) VALUES
  ((SELECT source_sk FROM dim_source WHERE name='Wallpaper*'), 'design',      0.92),
  ((SELECT source_sk FROM dim_source WHERE name='Wallpaper*'), 'hospitality', 0.55),
  ((SELECT source_sk FROM dim_source WHERE name='Wallpaper*'), 'food',        0.40)
ON CONFLICT (source_sk, domain) DO NOTHING;

-- ------------------------------------------------------------
-- 2. New venue: Cento 61 (Bistrot Cento61) — the one genuine design-press find
-- ------------------------------------------------------------
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, has_restaurant, child_policy, design_notes, website, canonical_hash)
VALUES ('restaurant', 'Cento 61',
        (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
        'independent', TRUE, 'unknown',
        'DiDeA-designed converted nightclub (Viale della Liberta 161): geometric walls, cobalt-blue sofas, Calacatta marble, Flos lamps',
        'https://www.wallpaper.com/travel/italy/sicily/restaurants/cento-61', 'cento-61-palermo')
ON CONFLICT (canonical_hash) DO NOTHING;

INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, quote_short)
VALUES (
  (SELECT venue_sk FROM dim_venue WHERE canonical_hash='cento-61-palermo'),
  (SELECT source_sk FROM dim_source WHERE name='Wallpaper*'),
  'design', DATE '2022-10-08', 'https://www.wallpaper.com/travel/italy/sicily/restaurants/cento-61',
  'praised', ['geometric walls','cobalt-blue','Calacatta marble','Flos lamps'],
  'breathed new life into an abandoned nightclub space')
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- ------------------------------------------------------------
-- 3. Real venues, but NO target-publication coverage -> add as research-flagged
--    (no mentions invented; adults_only/child_policy left NULL so they surface
--    as "research needed" rather than scoring on fabricated evidence)
-- ------------------------------------------------------------
-- Hotel Plaza Opera — real independent design-styled hotel; only self-marketing
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, has_restaurant, child_policy, design_notes, website, canonical_hash)
VALUES ('hotel', 'Hotel Plaza Opera',
        (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
        'independent', TRUE, 'unknown',
        'Central design-styled hotel (Via Nicolo Gallo 2); self-described "design hotel" — NO independent design-publication coverage found yet',
        'https://www.hotelplazaopera.com', 'hotel-plaza-opera-palermo')
ON CONFLICT (canonical_hash) DO NOTHING;

-- Morettino Caffe Palermo — cafe in 16th-c. Palazzo Guggino-Chiaramonte Bordonaro;
-- food-guide / PR coverage only; Monocle named the *roastery* in a coffee-business story
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, has_restaurant, child_policy, design_notes, canonical_hash)
VALUES ('bar', 'Morettino Caffe Palermo',
        (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
        'independent', FALSE, 'unknown',
        'Belle Epoque cafe revival in a 16th-c. palazzo (reopened Aug 2024); Monocle named the Morettino *roastery* in a coffee-business piece (not a design pick)',
        'morettino-caffe-palermo')
ON CONFLICT (canonical_hash) DO NOTHING;

-- ------------------------------------------------------------
-- 4. VERIFIED NEGATIVES — log so the canon remembers we checked
--    (source_review + notes on the seeded design titles)
-- ------------------------------------------------------------
UPDATE dim_source SET notes = 'NO dedicated Palermo city/travel guide (verified 2026-06, run w31pm9qvp). ~13 passing-mention articles only. "Sweet Dreams" piece = Susafa near the Madonie, NOT Palermo city. Beware /travel-guides/palma = Palma de Mallorca, a different city.'
WHERE name = 'Monocle';

UPDATE dim_source SET notes = 'City Guide series covers only London/Paris/NY/LA/Copenhagen — NO Italian/Sicilian/Palermo guide (verified 2026-06, run w31pm9qvp). Residual gap: readcereal.com/tag/italy is JS-rendered, unscraped.'
WHERE name = 'Cereal Guides';

INSERT INTO source_review (source_sk, action, reason) VALUES
  ((SELECT source_sk FROM dim_source WHERE name='Monocle'),       'decayed', 'Targeted pass found no Palermo-city design coverage (run w31pm9qvp). Keep in canon for other destinations; do not expect Palermo picks.'),
  ((SELECT source_sk FROM dim_source WHERE name='Cereal Guides'), 'decayed', 'No Cereal City Guide for Italy/Palermo exists (run w31pm9qvp). Residual unscraped JS gap on readcereal.com/tag/italy.'),
  ((SELECT source_sk FROM dim_source WHERE name='Wallpaper*'),    'added',   'One verified Palermo design find: Cento 61 (Oct 2022). Authority on design/architecture.');

-- Note for the editor: Condé Nast Traveler, Konfekt, Design Hotels, Tablet,
-- The Times, The Telegraph — NO findable Palermo-city coverage this pass. Not
-- added as sources (nothing to attach). Re-check periodically; CNT Gold List on
-- Villa Igiea is the most likely future hit (open question).
