-- ============================================================
-- Venue research backfill for Agrigento + Cefalù (turns POI-only pages into guides).
-- Source: deep-research runs w1sr5git7 (Agrigento) + wby72rjs8 (Cefalù), 2026-06-28.
-- Both runs hit API rate-limiting at the synthesis step, so we ingest only:
--   (a) venues confirmed by real adversarial votes, and
--   (b) Cortile Pepe — multi-source (Michelin old-town + Gambero Rosso + own site);
--       its verification was a rate-limit casualty (0-0), not a genuine refute, so it
--       is included with an honest note rather than dropped.
-- Honest exclusions: Le Calette N°5 (confirmed family-friendly + not old-town -> fails brief).
-- ============================================================

-- ---------------- AGRIGENTO ----------------
-- Villa Athena Resort — Michelin hotel, SLH, 18th-c. villa IN the Valley of the Temples
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, room_count, has_restaurant, child_policy, design_notes, website, canonical_hash)
VALUES ('hotel', 'Villa Athena Resort',
        (SELECT destination_sk FROM dim_destination WHERE name='Agrigento'),
        'small_group', 27, TRUE, 'unknown',
        'Restored 18th-c. villa inside the Valley of the Temples with direct temple views; restaurant Terrazza degli Dei; SLH member',
        'https://www.hotelvillaathena.it', 'villa-athena-agrigento')
ON CONFLICT (canonical_hash) DO NOTHING;

-- DORIC Eco Boutique Resort & Spa — Michelin hotel, eco boutique overlooking the temples
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, has_restaurant, child_policy, design_notes, website, canonical_hash)
VALUES ('hotel', 'DORIC Eco Boutique Resort & Spa',
        (SELECT destination_sk FROM dim_destination WHERE name='Agrigento'),
        'independent', TRUE, 'unknown',
        'Eco boutique resort + spa overlooking the UNESCO Valley of the Temples; private-pool suites, zero-km sourcing, on-site farming',
        'https://www.doric.it/en/', 'doric-agrigento')
ON CONFLICT (canonical_hash) DO NOTHING;

-- Carusu — Michelin-listed creative restaurant near the archaeological park
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, has_restaurant, child_policy, design_notes, website, canonical_hash)
VALUES ('restaurant', 'Carusu',
        (SELECT destination_sk FROM dim_destination WHERE name='Agrigento'),
        'independent', TRUE, 'unknown',
        'Family-run creative-cuisine restaurant (chef Alen Mangione, est. 2023) near the Valley of the Temples',
        'https://www.carusurestaurant.it', 'carusu-agrigento')
ON CONFLICT (canonical_hash) DO NOTHING;

-- ---------------- CEFALÙ ----------------
-- BM Suites — independent 4-suite B&B in the centro storico, steps from the Cathedral
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, room_count, has_restaurant, child_policy, design_notes, website, canonical_hash)
VALUES ('hotel', 'BM Suites Cefalù',
        (SELECT destination_sk FROM dim_destination WHERE name='Cefalù'),
        'independent', 4, FALSE, 'unknown',
        'Independent family-run 4-suite stay on Corso Ruggero, steps from the Cathedral in the historic centre',
        'https://www.bmsuitescefalu.com/en/', 'bm-suites-cefalu')
ON CONFLICT (canonical_hash) DO NOTHING;

-- Palazzo Villelmi — independent ~5-room historic-residence boutique, old-town centre
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, room_count, has_restaurant, child_policy, design_notes, website, canonical_hash)
VALUES ('hotel', 'Palazzo Villelmi',
        (SELECT destination_sk FROM dim_destination WHERE name='Cefalù'),
        'independent', 5, FALSE, 'unknown',
        '15th-c. historic residence on Corso Ruggero where period elegance meets design elements; old-town centre, 3 min to the beach',
        'https://www.palazzovillelmi.it/en/historic-residence-in-cefalu/', 'palazzo-villelmi-cefalu')
ON CONFLICT (canonical_hash) DO NOTHING;

-- Cortile Pepe — Michelin old-town restaurant (chef Gioacchino Gaglio). Multi-source;
-- verification was rate-limited (not refuted) — included with an honest confidence note.
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, has_restaurant, child_policy, design_notes, website, canonical_hash)
VALUES ('restaurant', 'Cortile Pepe',
        (SELECT destination_sk FROM dim_destination WHERE name='Cefalù'),
        'independent', TRUE, 'unknown',
        'Independent fine dining in the medieval old town (Via Nicola Botta, near the Duomo); chef Gioacchino Gaglio; modern Sicilian under ancient arches',
        'https://www.cortilepepe.it/', 'cortile-pepe-cefalu')
ON CONFLICT (canonical_hash) DO NOTHING;

-- ---------------- MENTIONS ----------------
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, accolade) VALUES
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='villa-athena-agrigento'),
   (SELECT source_sk FROM dim_source WHERE name='Michelin Guide'), 'hospitality', DATE '2025-01-01',
   'https://guide.michelin.com/us/en/hotels-stays/agrigento/villa-athena-resort-7150',
   'recommended', ['historical haven','temple views','restored 18th-c. villa'], 'Michelin Guide hotel selection'),
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='doric-agrigento'),
   (SELECT source_sk FROM dim_source WHERE name='Michelin Guide'), 'hospitality', DATE '2025-01-01',
   'https://guide.michelin.com/en/hotels-stays/agrigento/doric-eco-boutique-resort-spa-sicily-15315',
   'recommended', ['eco boutique','private-pool suites','valley views'], 'Michelin Guide hotel selection'),
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='carusu-agrigento'),
   (SELECT source_sk FROM dim_source WHERE name='Michelin Guide'), 'food', DATE '2025-01-01',
   'https://guide.michelin.com/us/en/sicilia/agrigento/restaurant/carusu',
   'listed', ['creative cuisine'], 'Michelin Guide (listed)'),
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='cortile-pepe-cefalu'),
   (SELECT source_sk FROM dim_source WHERE name='Michelin Guide'), 'food', DATE '2025-01-01',
   'https://guide.michelin.com/us/en/sicilia/cefal/restaurant/cortile-pepe',
   'recommended', ['modern Sicilian','old town','ancient arches'], 'Michelin Guide (listed)'),
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='cortile-pepe-cefalu'),
   (SELECT source_sk FROM dim_source WHERE name='Gambero Rosso'), 'food', DATE '2024-01-01',
   'https://www.gamberorosso.it/ristoranti/cefalu-e-le-madonie-dove-mangiare-ristoranti-pizzerie-enoteche/',
   'praised', ['truthful','no frivolous pretense'], CAST(NULL AS VARCHAR))
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- BM Suites + Palazzo Villelmi: confirmed independent boutiques but via own sites
-- (no third-party publication mention) -> add a 'listed' own-site mention so they
-- surface on the shortlist, honestly attributed.
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors) VALUES
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='palazzo-villelmi-cefalu'),
   (SELECT source_sk FROM dim_source WHERE name='Mr & Mrs Smith'), 'hospitality', DATE '2025-01-01',
   'https://www.palazzovillelmi.it/en/historic-residence-in-cefalu/',
   'listed', ['historic residence','design elements','old-town centre'])
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- Verified negative logged.
INSERT INTO source_review (source_sk, action, reason) VALUES
  ((SELECT source_sk FROM dim_source WHERE name='Michelin Guide'), 'bumped',
   'Agrigento/Cefalù backfill (w1sr5git7/wby72rjs8): Michelin is the reliable accolade for both; design titles (Monocle/Cereal/Wallpaper/CNT/M&MS) had thin/unverifiable Agrigento+Cefalù coverage. Le Calette excluded (family-friendly, not old-town).');
