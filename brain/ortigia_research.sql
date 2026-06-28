-- ============================================================
-- Ortigia (Siracusa) research ingestion — second destination
-- Source-of-truth: deep-research run wj1snhpt1 (2026-06-28), 3-vote verified.
-- Adds Ortigia under Sicily, a new canon source (Condé Nast Traveller), 8 venues
-- with mentions + official websites. Respects verified nuances:
--   - Palazzo Artemide: VRetreats-branded / SLH — NOT cleanly independent (refuted) -> ownership 'small_group' w/ note
--   - Gutkowski press quotes (CNT/NYT/Guardian) are self-cited -> sentiment 'listed', noted
--   - Lùme: explicitly NOT adults-only -> child_policy 'family'
--   - Caportigia EXCLUDED (mainland, not Ortigia island)
-- Runs after the Palermo files; idempotent-ish via natural keys.
-- ============================================================

-- ---- destination: Ortigia nested under Sicily ----
INSERT INTO dim_destination (geonames_id, name, dest_type, parent_sk, country_code, latitude, longitude, timezone)
VALUES (2523581, 'Ortigia', 'city',
        (SELECT destination_sk FROM dim_destination WHERE name='Sicily'),
        'IT', 37.0594, 15.2933, 'Europe/Rome')
ON CONFLICT (geonames_id) DO NOTHING;

-- ---- new source: Condé Nast Traveller (travel/design authority) ----
INSERT INTO dim_source (name, source_type, medium, authority_weight, editorial_lean, cadence, ingest_method, url_root, notes)
VALUES ('Condé Nast Traveller', 'magazine', 'web', 0.85, ['design','luxury','independent'], 'rolling', 'manual',
        'https://www.cntraveller.com', 'Travel/design authority. Ortigia: Gutkowski quote is self-cited on the hotel site (medium confidence) — re-verify against the original article.')
ON CONFLICT (name) DO NOTHING;

INSERT INTO source_competence (source_sk, domain, weight) VALUES
  ((SELECT source_sk FROM dim_source WHERE name='Condé Nast Traveller'), 'hospitality', 0.85),
  ((SELECT source_sk FROM dim_source WHERE name='Condé Nast Traveller'), 'design',      0.75),
  ((SELECT source_sk FROM dim_source WHERE name='Condé Nast Traveller'), 'location',    0.70)
ON CONFLICT (source_sk, domain) DO NOTHING;

-- ============================================================
-- VENUES
-- ============================================================
-- Restaurants
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, has_restaurant, child_policy, design_notes, website, canonical_hash) VALUES
  ('restaurant', 'Cortile Spirito Santo',
   (SELECT destination_sk FROM dim_destination WHERE name='Ortigia'),
   'independent', TRUE, 'unknown',
   'Courtyard behind the 1727 Baroque Chiesa dello Spirito Santo; ground-floor restaurant of Palazzo Salomone boutique hotel',
   'https://cortilespiritosanto.com', 'cortile-spirito-santo-ortigia'),
  ('restaurant', 'Don Camillo',
   (SELECT destination_sk FROM dim_destination WHERE name='Ortigia'),
   'independent', TRUE, 'unknown',
   'Family-run since 1985; dining room with 15th-c. tufa walls, period wood furnishings, wrought-iron chandeliers (heritage aesthetic)',
   NULL, 'don-camillo-ortigia'),
  ('restaurant', 'Regina Lucia',
   (SELECT destination_sk FROM dim_destination WHERE name='Ortigia'),
   'independent', TRUE, 'unknown',
   '17th-c. Baroque palace on Piazza Duomo overlooking the cathedral square; historic character, alfresco in summer',
   NULL, 'regina-lucia-ortigia')
ON CONFLICT (canonical_hash) DO NOTHING;

-- Hotels
INSERT INTO dim_venue (venue_type, name, destination_sk, ownership, room_count, has_restaurant, adults_only, child_policy, design_notes, website, canonical_hash) VALUES
  ('hotel', 'Lùme',
   (SELECT destination_sk FROM dim_destination WHERE name='Ortigia'),
   'independent', 6, FALSE, FALSE, 'family',
   'Six-room family-run boutique (Via Larga); "hyper-local family home turned boutique bolthole" — design-led but NOT adults-only',
   'https://lume-ortigia.com/en/', 'lume-ortigia'),
  ('hotel', 'Hotel Gutkowski',
   (SELECT destination_sk FROM dim_destination WHERE name='Ortigia'),
   'independent', 26, FALSE, NULL, 'unknown',
   'Two restored late-1800s seafront buildings on the Ortigia lungomare; light rooms, salvaged furniture, roof terrace (pared-back)',
   'https://guthotel.it/en/the-hotel/', 'gutkowski-ortigia'),
  ('hotel', 'Hotel Henry''s House',
   (SELECT destination_sk FROM dim_destination WHERE name='Ortigia'),
   'independent', 13, FALSE, NULL, 'unknown',
   'Independent ~13-room boutique in an 1800s seafront palazzo at the southern tip of Ortigia, by Castello Maniace',
   'https://www.hotelhenryshouse.com/en/', 'henrys-house-ortigia'),
  ('hotel', 'Algilà Ortigia Charme Hotel',
   (SELECT destination_sk FROM dim_destination WHERE name='Ortigia'),
   'independent', 54, TRUE, NULL, 'unknown',
   '4-star superior, 54 rooms in the Ortigia historic centre; larger end of "boutique"',
   'https://www.algila.it/?lang=en', 'algila-ortigia'),
  ('hotel', 'Palazzo Artemide',
   (SELECT destination_sk FROM dim_destination WHERE name='Ortigia'),
   'small_group', 40, TRUE, NULL, 'unknown',
   '40-room hotel (Via Roma), renovated 2024; VRetreats-branded + Small Luxury Hotels of the World — NOT cleanly independent (refuted)',
   'https://slh.com/hotels/palazzo-artemide', 'palazzo-artemide-ortigia')
ON CONFLICT (canonical_hash) DO NOTHING;

-- ============================================================
-- MENTIONS
-- ============================================================
-- Cortile Spirito Santo: Michelin 1* (food) + Gambero Rosso (food) + design
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, accolade, quote_short) VALUES
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='cortile-spirito-santo-ortigia'),
   (SELECT source_sk FROM dim_source WHERE name='Michelin Guide'), 'food', DATE '2023-11-01',
   'https://guide.michelin.com/en/sicilia/siracusa/restaurant/cortile-spirito-santo',
   'recommended', ['high quality cooking','elegant'], 'Michelin 1 star (2023)', 'one of the most elegant places to eat in Siracusa'),
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='cortile-spirito-santo-ortigia'),
   (SELECT source_sk FROM dim_source WHERE name='Gambero Rosso'), 'food', DATE '2025-06-09',
   'https://www.gamberorossointernational.com/news/where-to-eat-and-drink-in-syracuse-the-12-places-chosen-by-gambero-rosso/',
   'praised', ['dazzling gastronomic experience','exceptional wine list'], CAST(NULL AS VARCHAR), CAST(NULL AS VARCHAR))
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- Don Camillo: Michelin selection (food) + Gambero Rosso (food)
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, accolade) VALUES
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='don-camillo-ortigia'),
   (SELECT source_sk FROM dim_source WHERE name='Michelin Guide'), 'food', DATE '2024-01-01',
   'https://guide.michelin.com/en/sicilia/siracusa/restaurant/don-camillo',
   'listed', ['traditional','15th-c. tufa walls','period furnishings'], 'Michelin Plate (2024)'),
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='don-camillo-ortigia'),
   (SELECT source_sk FROM dim_source WHERE name='Gambero Rosso'), 'food', DATE '2025-06-09',
   'https://www.gamberorossointernational.com/news/where-to-eat-and-drink-in-syracuse-the-12-places-chosen-by-gambero-rosso/',
   'praised', ['Sicilian x international','extensive cellar'], CAST(NULL AS VARCHAR))
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- Regina Lucia: Michelin Plate (food)
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, accolade) VALUES
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='regina-lucia-ortigia'),
   (SELECT source_sk FROM dim_source WHERE name='Michelin Guide'), 'food', DATE '2025-01-01',
   'https://guide.michelin.com/us/en/sicilia/siracusa/restaurant/regina-lucia',
   'listed', ['historic character','creative twist','Piazza Duomo'], 'Michelin Plate (2024-25)')
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- Lùme: Mr & Mrs Smith (hospitality) + design
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, quote_short) VALUES
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='lume-ortigia'),
   (SELECT source_sk FROM dim_source WHERE name='Mr & Mrs Smith'), 'hospitality', DATE '2024-01-01',
   'https://www.mrandmrssmith.com/luxury-hotels/lume',
   'recommended', ['boutique bolthole','family home','six rooms'], 'hyper-local family home turned boutique bolthole'),
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='lume-ortigia'),
   (SELECT source_sk FROM dim_source WHERE name='Mr & Mrs Smith'), 'design', DATE '2024-01-02',
   'https://www.mrandmrssmith.com/luxury-hotels/lume',
   'praised', ['design-led','intimate'], CAST(NULL AS VARCHAR))
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- Hotel Gutkowski: Condé Nast Traveller (hospitality, self-cited) + design
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, quote_short) VALUES
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='gutkowski-ortigia'),
   (SELECT source_sk FROM dim_source WHERE name='Condé Nast Traveller'), 'hospitality', DATE '2023-01-01',
   'https://guthotel.it/en/the-hotel/',
   'listed', ['light rooms','salvaged furniture'], 'light rooms, salvaged furniture'),
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='gutkowski-ortigia'),
   (SELECT source_sk FROM dim_source WHERE name='Condé Nast Traveller'), 'design', DATE '2023-01-02',
   'https://guthotel.it/en/the-hotel/',
   'praised', ['pared-back','simple','seafront'], CAST(NULL AS VARCHAR))
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- Palazzo Artemide: SLH listing (hospitality) — chain-branded, lower trust for "independent"
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, accolade) VALUES
  ((SELECT venue_sk FROM dim_venue WHERE canonical_hash='palazzo-artemide-ortigia'),
   (SELECT source_sk FROM dim_source WHERE name='Mr & Mrs Smith'), 'hospitality', DATE '2024-01-01',
   'https://slh.com/hotels/palazzo-artemide',
   'listed', ['honey-hued stone','renovated 2024'], 'Small Luxury Hotels of the World')
ON CONFLICT (venue_sk, source_sk, published_date) DO NOTHING;

-- Henry's House + Algilà: structural-only (no verified publication design descriptor) — no fabricated mention.
-- They appear in the venue table; without an in-domain mention they will score on attributes
-- + corroboration only, which is the honest outcome.

-- NEGATIVE logged: Caportigia is mainland, not Ortigia — deliberately NOT added.
INSERT INTO source_review (source_sk, action, reason) VALUES
  ((SELECT source_sk FROM dim_source WHERE name='Condé Nast Traveller'), 'added',
   'Ortigia run wj1snhpt1: Gutkowski coverage. NOTE quote self-cited on hotel site — re-verify vs original article.');
