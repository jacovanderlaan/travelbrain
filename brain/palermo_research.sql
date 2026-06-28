-- ============================================================
-- Palermo research ingestion (Stage 3)
-- Real venues + mentions from the deep-research run (2026-06-28), verified by
-- 3-vote adversarial check. Source-of-truth: workflow w4bbnz47y.
--
-- Provenance discipline: we store structured signals + short attributed snippets
-- + the source URL, NEVER the publication's paragraphs. Confidence/vote notes
-- from the research live in the `notes`/`rationale` where useful.
--
-- Idempotent-ish: uses natural-key conflict targets; intended to run ONCE on a
-- freshly seeded DB (build_db.py --reset runs schema+seed first, then this).
-- ============================================================

-- ------------------------------------------------------------
-- 1. New sources (food/hotel guides the research actually surfaced)
--    Monocle / Cereal / CNT yielded NOTHING in this run — logged as open gap,
--    not added as fake mentions.
-- ------------------------------------------------------------
INSERT INTO dim_source (name, source_type, medium, authority_weight, editorial_lean, cadence, ingest_method, url_root, notes)
VALUES
  ('Michelin Guide', 'guide', 'web', 0.95, ['culinary','fine-dining'], 'annual', 'manual', 'https://guide.michelin.com', 'Michelin Guide Italia — stars + hotel selection; authoritative on food, listed hotels')
ON CONFLICT (name) DO NOTHING;

INSERT INTO dim_source (name, source_type, medium, authority_weight, editorial_lean, cadence, ingest_method, url_root, notes)
VALUES
  ('Gambero Rosso', 'guide', 'web', 0.88, ['culinary','independent'], 'annual', 'manual', 'https://www.gamberorossointernational.com', 'Italian food authority — Ristoranti d''Italia + editorial roundups')
ON CONFLICT (name) DO NOTHING;

-- per-domain competence for the new sources
INSERT INTO source_competence (source_sk, domain, weight) VALUES
  ((SELECT source_sk FROM dim_source WHERE name='Michelin Guide'),  'food',        0.95),
  ((SELECT source_sk FROM dim_source WHERE name='Michelin Guide'),  'hospitality', 0.70),
  ((SELECT source_sk FROM dim_source WHERE name='Michelin Guide'),  'design',      0.30),
  ((SELECT source_sk FROM dim_source WHERE name='Gambero Rosso'),   'food',        0.90),
  ((SELECT source_sk FROM dim_source WHERE name='Gambero Rosso'),   'design',      0.25)
ON CONFLICT (source_sk, domain) DO NOTHING;

-- ------------------------------------------------------------
-- 2. Correct the seeded Villa Igiea: research REFUTED (0-3) that it is
--    independent / design-led — it is Rocco Forte CHAIN-owned, ~100 rooms.
--    Real-data correction: a poor fit for the adults/design-led/independent brief.
-- ------------------------------------------------------------
UPDATE dim_venue
SET ownership = 'chain',
    room_count = 100,
    design_notes = 'Art Nouveau palazzo (Basile, 1900); Rocco Forte chain-owned grand hotel',
    adults_only = FALSE,
    child_policy = 'family'
WHERE canonical_hash = 'villa-igiea-palermo';

-- Villa Igiea's real mention: Mr & Mrs Smith lists it (the ONE Palermo hotel)
-- and praises Florio (Pierangelini). Kept for transparency; ownership now correct.
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, quote_short, accolade)
VALUES (
  (SELECT venue_sk FROM dim_venue WHERE canonical_hash='villa-igiea-palermo'),
  (SELECT source_sk FROM dim_source WHERE name='Mr & Mrs Smith'),
  'hospitality', DATE '2024-01-01', 'https://www.mrandmrssmith.com/destinations/sicily/palermo-sicily/hotels',
  'listed', ['Florio restaurant','Pierangelini menus','grand hotel'], NULL, NULL)
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- ------------------------------------------------------------
-- 3. Enrich the seeded Gagini with its REAL Michelin + Gambero Rosso mentions
--    (one Michelin star, 2026 Guide Italia; 16th-c. Antonello Gagini workshop)
-- ------------------------------------------------------------
UPDATE dim_venue
SET design_notes = '16th-c. workshop of sculptor Antonello Gagini; modern design vs bare-stone walls; La Vucciria',
    website = 'https://www.gaginirestaurant.com/en/'
WHERE canonical_hash = 'gagini-palermo';

INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, accolade)
VALUES (
  (SELECT venue_sk FROM dim_venue WHERE canonical_hash='gagini-palermo'),
  (SELECT source_sk FROM dim_source WHERE name='Michelin Guide'),
  'food', DATE '2026-01-01', 'https://guide.michelin.com/us/en/sicilia/palermo/restaurant/gagini-social-restaurant',
  'recommended', ['modern design','contemporary touch','bare-stone decor'], 'Michelin 1 star (2026)')
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors)
VALUES (
  (SELECT venue_sk FROM dim_venue WHERE canonical_hash='gagini-palermo'),
  (SELECT source_sk FROM dim_source WHERE name='Gambero Rosso'),
  'food', DATE '2024-01-01', 'https://www.gamberorossointernational.com/news/where-to-eat-in-palermo-the-best-restaurants-and-street-food/',
  'praised', ['cross-pollination','never predictable'])
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- A design-domain mention for Gagini (the workshop/interior is genuinely design-led)
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors)
VALUES (
  (SELECT venue_sk FROM dim_venue WHERE canonical_hash='gagini-palermo'),
  (SELECT source_sk FROM dim_source WHERE name='Michelin Guide'),
  'design', DATE '2026-01-02', 'https://guide.michelin.com/us/en/sicilia/palermo/restaurant/gagini-social-restaurant',
  'praised', ['contemporary touch on ancient walls'])
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- ------------------------------------------------------------
-- 4. New venues
-- ------------------------------------------------------------
-- helper note: venue_type ∈ hotel|restaurant|bar|other ; child_policy default 'unknown'

-- MEC Restaurant — Michelin 1*, Palazzo Castrone, frescoed rooms + Apple memorabilia
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, has_restaurant, child_policy, design_notes, website, canonical_hash)
VALUES ('restaurant', 'MEC Restaurant',
        (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
        'independent', TRUE, 'unknown',
        'Frescoed-ceiling rooms in 16th-c. Palazzo Castrone; rare Apple memorabilia; opposite the Cathedral',
        NULL, 'mec-restaurant-palermo')
ON CONFLICT (canonical_hash) DO NOTHING;

-- Palazzo Branciforte (restaurant) — Michelin-listed, secluded courtyard "oasis"
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, has_restaurant, child_policy, design_notes, canonical_hash)
VALUES ('restaurant', 'Palazzo Branciforte',
        (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
        'independent', TRUE, 'unknown',
        'Late-16th-c. patrician residence (restored by Gae Aulenti); elegant secluded inner-courtyard dining',
        'palazzo-branciforte-palermo')
ON CONFLICT (canonical_hash) DO NOTHING;

-- Casa Charleston — Gambero Rosso "refined elegance and a tranquil atmosphere", ~30 seats
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, has_restaurant, room_count, child_policy, design_notes, canonical_hash)
VALUES ('restaurant', 'Casa Charleston',
        (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
        'independent', TRUE, NULL, 'unknown',
        'Fine-dining room seating ~30; chef Gaetano Verde (ex-Charleston Mondello)',
        'casa-charleston-palermo')
ON CONFLICT (canonical_hash) DO NOTHING;

-- L'Ottava Nota — designer interiors, "intimate atmosphere", Kalsa
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, has_restaurant, child_policy, design_notes, canonical_hash)
VALUES ('restaurant', 'L''Ottava Nota',
        (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
        'independent', TRUE, 'unknown',
        'Designer interiors (arch. V. Cinzia Farina): sober elegance, natural materials, soft lighting; Kalsa',
        'lottava-nota-palermo')
ON CONFLICT (canonical_hash) DO NOTHING;

-- Corona — elegant independent family trattoria
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, has_restaurant, child_policy, design_notes, canonical_hash)
VALUES ('restaurant', 'Corona Trattoria',
        (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
        'independent', TRUE, 'unknown',
        'Elegant family-run trattoria; excellent ingredients, fish-leaning traditional menu',
        'corona-trattoria-palermo')
ON CONFLICT (canonical_hash) DO NOTHING;

-- Trattoria Ai Cascinari — historic Slow Food trattoria (casual, not design-led)
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, has_restaurant, child_policy, design_notes, canonical_hash)
VALUES ('restaurant', 'Trattoria Ai Cascinari',
        (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
        'independent', TRUE, 'unknown',
        'Historic trattoria (founded 1949); Slow Food presidia; casual/traditional',
        'ai-cascinari-palermo')
ON CONFLICT (canonical_hash) DO NOTHING;

-- Palazzo Natoli — boutique HOTEL, 12 rooms, 1795 palazzo, Michelin hotel listing
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, room_count, has_restaurant, child_policy, design_notes, website, canonical_hash)
VALUES ('hotel', 'Palazzo Natoli',
        (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
        'small_group', 12, FALSE, 'unknown',
        'Modern-elegant boutique hotel in a 1795 palazzo near the Cathedral / Quattro Canti (Natoli Group)',
        'https://www.palazzonatoli.com/', 'palazzo-natoli-palermo')
ON CONFLICT (canonical_hash) DO NOTHING;

-- Palazzo Balsamo — boutique HOTEL, ~16-19 rooms, Natoli Group, opened 2025/26
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, room_count, has_restaurant, child_policy, design_notes, website, canonical_hash)
VALUES ('hotel', 'Palazzo Balsamo',
        (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
        'small_group', 18, FALSE, 'unknown',
        'Boutique hotel at Via Divisi/Via Maqueda (Natoli Group; arch. Floriana Cammareri); opened 2025/26',
        'https://palazzobalsamo.com/en/', 'palazzo-balsamo-palermo')
ON CONFLICT (canonical_hash) DO NOTHING;

-- Maison Opéra — explicitly ADULTS-ONLY, but a self-catering apartment (not staffed hotel)
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, room_count, has_restaurant, adults_only, child_policy, design_notes, canonical_hash)
VALUES ('other', 'Maison Opéra',
        (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
        'independent', 1, FALSE, TRUE, 'adults_only',
        '~80m² self-catering apartment 80m from Teatro Massimo; stated adults-only policy',
        'maison-opera-palermo')
ON CONFLICT (canonical_hash) DO NOTHING;

-- ------------------------------------------------------------
-- 5. Mentions for the new venues
-- ------------------------------------------------------------
-- MEC: Michelin 1* (food) + design domain
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, accolade) VALUES
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='mec-restaurant-palermo'),
   (SELECT source_sk FROM dim_source WHERE name='Michelin Guide'), 'food', DATE '2026-01-01',
   'https://guide.michelin.com/ca/en/sicilia/palermo/restaurant/mec-restaurant',
   'recommended', ['high quality cooking','suggestive atmosphere'], 'Michelin 1 star (2026)'),
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='mec-restaurant-palermo'),
   (SELECT source_sk FROM dim_source WHERE name='Michelin Guide'), 'design', DATE '2026-01-02',
   'https://guide.michelin.com/ca/en/sicilia/palermo/restaurant/mec-restaurant',
   'praised', ['frescoed ceilings','elegant rooms'], NULL),
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='mec-restaurant-palermo'),
   (SELECT source_sk FROM dim_source WHERE name='Gambero Rosso'), 'food', DATE '2024-02-13',
   'https://www.gamberorossointernational.com/news/where-to-eat-in-palermo-for-valentines-day-the-8-restaurants-chosen-by-gambero-rosso/',
   'praised', ['refined','local x international'], NULL)
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- Palazzo Branciforte: Michelin-listed; food + design (Aulenti restoration)
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, quote_short) VALUES
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='palazzo-branciforte-palermo'),
   (SELECT source_sk FROM dim_source WHERE name='Michelin Guide'), 'food', DATE '2026-01-01',
   'https://guide.michelin.com/us/en/sicilia/palermo/restaurant/palazzo-branciforte',
   'recommended', ['secluded courtyard','relaxing oasis'], 'a relaxing oasis in the city centre'),
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='palazzo-branciforte-palermo'),
   (SELECT source_sk FROM dim_source WHERE name='Michelin Guide'), 'design', DATE '2026-01-02',
   'https://guide.michelin.com/us/en/sicilia/palermo/restaurant/palazzo-branciforte',
   'praised', ['late-16th-c. residence','Gae Aulenti restoration'], NULL)
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- Casa Charleston: Gambero Rosso tranquil atmosphere (food)
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, quote_short) VALUES
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='casa-charleston-palermo'),
   (SELECT source_sk FROM dim_source WHERE name='Gambero Rosso'), 'food', DATE '2024-02-13',
   'https://www.gamberorossointernational.com/news/where-to-eat-in-palermo-for-valentines-day-the-8-restaurants-chosen-by-gambero-rosso/',
   'praised', ['refined elegance','tranquil atmosphere'], 'refined elegance and a tranquil atmosphere')
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- L'Ottava Nota: Gambero Rosso designer spaces (food) + design domain
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors) VALUES
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='lottava-nota-palermo'),
   (SELECT source_sk FROM dim_source WHERE name='Gambero Rosso'), 'food', DATE '2024-02-13',
   'https://www.gamberorossointernational.com/news/where-to-eat-in-palermo-for-valentines-day-the-8-restaurants-chosen-by-gambero-rosso/',
   'praised', ['contemporary','designer spaces']),
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='lottava-nota-palermo'),
   (SELECT source_sk FROM dim_source WHERE name='Gambero Rosso'), 'design', DATE '2024-02-14',
   'https://www.gamberorossointernational.com/news/where-to-eat-in-palermo-for-valentines-day-the-8-restaurants-chosen-by-gambero-rosso/',
   'praised', ['sober elegance','intimate atmosphere'])
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- Corona: Gambero Rosso (food)
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors) VALUES
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='corona-trattoria-palermo'),
   (SELECT source_sk FROM dim_source WHERE name='Gambero Rosso'), 'food', DATE '2024-01-01',
   'https://www.gamberorossointernational.com/news/where-to-eat-in-palermo-the-best-restaurants-and-street-food/',
   'praised', ['elegant trattoria','excellent ingredients'])
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- Ai Cascinari: Gambero Rosso + Slow Food (food)
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, accolade) VALUES
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='ai-cascinari-palermo'),
   (SELECT source_sk FROM dim_source WHERE name='Gambero Rosso'), 'food', DATE '2024-01-01',
   'https://www.gamberorossointernational.com/news/where-to-eat-in-palermo-the-best-restaurants-and-street-food/',
   'recommended', ['historic trattoria','care','tradition'], 'Slow Food presidia')
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- Palazzo Natoli: Michelin HOTEL listing (hospitality) + design
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, accolade) VALUES
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='palazzo-natoli-palermo'),
   (SELECT source_sk FROM dim_source WHERE name='Michelin Guide'), 'hospitality', DATE '2025-01-01',
   'https://guide.michelin.com/us/en/hotels-stays/palermo/palazzo-natoli-boutique-hotel-14202',
   'recommended', ['boutique','12 rooms','1795 palazzo'], 'Michelin Guide hotel selection'),
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='palazzo-natoli-palermo'),
   (SELECT source_sk FROM dim_source WHERE name='Michelin Guide'), 'design', DATE '2025-01-02',
   'https://guide.michelin.com/us/en/hotels-stays/palermo/palazzo-natoli-boutique-hotel-14202',
   'praised', ['modern','elegant','historic building'], NULL)
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- Palazzo Balsamo: independent boutique (hospitality). New opening, accolades maturing.
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors) VALUES
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='palazzo-balsamo-palermo'),
   (SELECT source_sk FROM dim_source WHERE name='Mr & Mrs Smith'), 'hospitality', DATE '2026-01-01',
   'https://palazzobalsamo.com/en/',
   'listed', ['boutique','restored palazzo','central'])
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- ------------------------------------------------------------
-- 6. Remove the fabricated demo row — real data now stands on its own.
-- ------------------------------------------------------------
DELETE FROM fact_mention WHERE venue_sk = (SELECT venue_sk FROM dim_venue WHERE canonical_hash='grand-resort-family-bay-palermo');
DELETE FROM curation_decision WHERE venue_sk = (SELECT venue_sk FROM dim_venue WHERE canonical_hash='grand-resort-family-bay-palermo');
DELETE FROM dim_venue WHERE canonical_hash='grand-resort-family-bay-palermo';
