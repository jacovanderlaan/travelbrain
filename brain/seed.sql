-- ============================================================
-- Travel Curation Brain — minimal seed
-- One destination, one site, one taste profile, a small heterogeneous canon,
-- and a couple of venues+mentions so style_fit has something to chew on.
-- Idempotent via natural-key conflict targets where supported; intended for a
-- fresh DB built by build_db.py. Re-running on a populated DB may raise on the
-- UNIQUE constraints (by design — seed once).
-- ============================================================

-- ---- destination (Sicily as region, Palermo nested under it) ----
INSERT INTO dim_destination (geonames_id, name, dest_type, country_code, latitude, longitude, timezone)
VALUES (2523119, 'Sicily', 'region', 'IT', 37.6, 14.0, 'Europe/Rome');

INSERT INTO dim_destination (geonames_id, name, dest_type, parent_sk, country_code, latitude, longitude, timezone)
VALUES (2523920, 'Palermo', 'city',
        (SELECT destination_sk FROM dim_destination WHERE geonames_id = 2523119),
        'IT', 38.1157, 13.3615, 'Europe/Rome');

-- ---- provider (Booking direct, affiliate) ----
INSERT INTO dim_provider (name, affiliate_network, commission_model, commission_rate, tracking_template)
VALUES ('Booking.com', 'booking_direct', 'cpa', 0.0400,
        'https://www.booking.com/hotel/{provider_ref}.html?aid={site}');

-- ---- site (the editorial brand for this target group) ----
INSERT INTO dim_site (slug, domain, niche_filter, theme)
VALUES ('adults-design-led', NULL,
        '{"venue_type":["hotel","restaurant"],"taste":"adults / design-led / quiet"}',
        'editorial-quiet');

-- ---- source canon (heterogeneous: magazine, book, blog, critic) ----
INSERT INTO dim_source (name, source_type, medium, authority_weight, editorial_lean, cadence, ingest_method, url_root, notes)
VALUES ('Monocle', 'magazine', 'mixed', 0.90, ['design','independent','slow-travel'], 'monthly', 'manual', 'https://monocle.com', 'Design + considered-travel authority');

INSERT INTO dim_source (name, source_type, medium, authority_weight, editorial_lean, cadence, ingest_method, notes, author, publisher, publication_year)
VALUES ('Cereal Guides', 'book', 'print', 0.80, ['design','slow-travel'], 'evergreen', 'manual', 'Minimalist design-led city/region guides', 'Rosa Park & Rich Stapleton', 'Cereal', 2018);

INSERT INTO dim_source (name, source_type, medium, authority_weight, editorial_lean, cadence, ingest_method, url_root, notes, person_name)
VALUES ('Mr & Mrs Smith', 'hotel_collection', 'web', 0.85, ['design','luxury','independent'], 'rolling', 'scrape', 'https://www.mrandmrssmith.com', 'Curated boutique/adults-led hotels', NULL);

INSERT INTO dim_source (name, source_type, medium, authority_weight, editorial_lean, cadence, ingest_method, notes, person_name)
VALUES ('Marina O''Loughlin', 'critic', 'web', 0.88, ['culinary'], 'rolling', 'manual', 'Restaurant critic; sharp, independent palate', 'Marina O''Loughlin');

-- ---- source competence (per-domain weights; keep each source in its lane) ----
INSERT INTO source_competence (source_sk, domain, weight) VALUES
  ((SELECT source_sk FROM dim_source WHERE name='Monocle'),              'design',      0.90),
  ((SELECT source_sk FROM dim_source WHERE name='Monocle'),              'hospitality', 0.80),
  ((SELECT source_sk FROM dim_source WHERE name='Monocle'),              'location',    0.70),
  ((SELECT source_sk FROM dim_source WHERE name='Cereal Guides'),        'design',      0.85),
  ((SELECT source_sk FROM dim_source WHERE name='Cereal Guides'),        'location',    0.75),
  ((SELECT source_sk FROM dim_source WHERE name='Mr & Mrs Smith'),       'hospitality', 0.90),
  ((SELECT source_sk FROM dim_source WHERE name='Mr & Mrs Smith'),       'design',      0.70),
  ((SELECT source_sk FROM dim_source WHERE name='Marina O''Loughlin'),   'food',        0.95),
  ((SELECT source_sk FROM dim_source WHERE name='Marina O''Loughlin'),   'design',      0.20);

-- ---- taste profile (the target group as a versioned rubric) ----
INSERT INTO dim_taste_profile (name, version, rubric, is_active)
VALUES ('adults / design-led / quiet', 1,
'{
  "exclude": {
    "child_policy": ["family"],
    "ownership": ["chain"],
    "descriptors_any": ["kids club", "all-inclusive", "party", "lively pool"]
  },
  "boost": {
    "adults_only_or_preferred": 0.25,
    "design_or_architecture_coverage": 0.30,
    "independent_or_small_group": 0.15,
    "small_room_count": 0.10,
    "has_real_restaurant": 0.10,
    "descriptors_any": {
      "terms": ["restrained", "quiet", "design-led", "considered", "intimate", "material"],
      "weight": 0.10
    }
  }
}', TRUE);

-- ---- venues (one strong fit, one likely-exclude, one unknown) ----
INSERT INTO dim_venue (venue_type, name, destination_sk, adults_only, child_policy, room_count, ownership, has_restaurant, design_notes, canonical_hash)
VALUES ('hotel', 'Villa Igiea',
        (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
        FALSE, 'adults_preferred', 100, 'small_group', TRUE,
        'Belle Epoque villa, restrained restoration, sea-facing terraces', 'villa-igiea-palermo');

INSERT INTO dim_venue (venue_type, name, destination_sk, adults_only, child_policy, room_count, ownership, has_restaurant, design_notes, canonical_hash)
VALUES ('hotel', 'Grand Resort Family Bay',
        (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
        FALSE, 'family', 420, 'chain', TRUE,
        'Large family resort with kids club and pool complex', 'grand-resort-family-bay-palermo');

INSERT INTO dim_venue (venue_type, name, destination_sk, adults_only, child_policy, room_count, ownership, has_restaurant, design_notes, canonical_hash)
VALUES ('restaurant', 'Gagini Social Restaurant',
        (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
        NULL, 'unknown', NULL, 'independent', TRUE,
        'Stone-vaulted room, contemporary Sicilian, considered plating', 'gagini-palermo');

-- ---- mentions (the evidence) ----
INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, accolade)
VALUES (
  (SELECT venue_sk FROM dim_venue WHERE canonical_hash='villa-igiea-palermo'),
  (SELECT source_sk FROM dim_source WHERE name='Mr & Mrs Smith'),
  'hospitality', DATE '2023-05-01', 'https://www.mrandmrssmith.com/luxury-hotels/villa-igiea',
  'recommended', ['design-led','restrained','adults-preferred','sea-facing'], NULL);

INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, locator, sentiment, descriptors, accolade)
VALUES (
  (SELECT venue_sk FROM dim_venue WHERE canonical_hash='villa-igiea-palermo'),
  (SELECT source_sk FROM dim_source WHERE name='Cereal Guides'),
  'design', DATE '2022-01-01', 'Sicily guide, p.88',
  'praised', ['considered','material','intimate'], NULL);

INSERT INTO fact_mention (venue_sk, source_sk, domain, published_date, source_url, sentiment, descriptors, accolade)
VALUES (
  (SELECT venue_sk FROM dim_venue WHERE canonical_hash='gagini-palermo'),
  (SELECT source_sk FROM dim_source WHERE name='Marina O''Loughlin'),
  'food', DATE '2024-09-01', 'https://example.com/review/gagini',
  'praised', ['quiet','considered'], NULL);
