-- ============================================================
-- POI expansion — more places from the Sicily 2022 trip (GPS+vision confirmed).
-- Adds two lightweight "places I visited" destinations (Agrigento, Cefalù) that
-- carry POIs but no eat/stay venue research (yet), plus a food-culture POI to Ortigia.
-- ============================================================

-- ---- new lightweight destinations under Sicily ----
INSERT INTO dim_destination (geonames_id, name, dest_type, parent_sk, country_code, latitude, longitude, timezone)
VALUES (2873386, 'Agrigento', 'city',
        (SELECT destination_sk FROM dim_destination WHERE name='Sicily'),
        'IT', 37.3111, 13.5765, 'Europe/Rome')
ON CONFLICT (geonames_id) DO NOTHING;

INSERT INTO dim_destination (geonames_id, name, dest_type, parent_sk, country_code, latitude, longitude, timezone)
VALUES (2525222, 'Cefalù', 'city',
        (SELECT destination_sk FROM dim_destination WHERE name='Sicily'),
        'IT', 38.0394, 14.0228, 'Europe/Rome')
ON CONFLICT (geonames_id) DO NOTHING;

-- ---- Agrigento: Temple of Concordia (59-photo cluster, vision-confirmed) ----
INSERT INTO dim_poi (destination_sk, name, poi_type, latitude, longitude, photo_count, rep_photo, photo_date, blurb, info_source, canonical_hash)
VALUES (
  (SELECT destination_sk FROM dim_destination WHERE name='Agrigento'),
  'Temple of Concordia', 'monument', 37.2903, 13.5917, 59, '/photos/poi/temple-concordia-agrigento.jpg', DATE '2022-04-04',
  'The largest and best-preserved Doric temple in Sicily, built around 440-430 BC in the Valley of the Temples. It survived because it was turned into a Christian basilica in the 6th century; the later additions were stripped out in 1785, leaving 34 honey-gold columns standing almost intact.',
  'Wikipedia (Temple of Concordia, Agrigento)', 'temple-concordia-agrigento'
)
ON CONFLICT (canonical_hash) DO UPDATE SET blurb=excluded.blurb, rep_photo=excluded.rep_photo, photo_count=excluded.photo_count;

-- ---- Cefalù: old-town beach (35 photos across clusters, vision-confirmed) ----
INSERT INTO dim_poi (destination_sk, name, poi_type, latitude, longitude, photo_count, rep_photo, photo_date, blurb, info_source, canonical_hash)
VALUES (
  (SELECT destination_sk FROM dim_destination WHERE name='Cefalù'),
  'Cefalù old town & beach', 'view', 38.0356, 14.0228, 35, '/photos/poi/cefalu-old-town-beach.jpg', DATE '2022-04-06',
  'A medieval fishing town where stone houses meet a golden crescent of sand, the limestone Rocca rising behind. The Arab-Norman street plan survives in its lanes and piazzas; the 12th-century cathedral (a UNESCO site) holds one of the finest Byzantine Christ Pantocrator mosaics anywhere.',
  'Wikipedia (Cefalù); UNESCO', 'cefalu-old-town-beach'
)
ON CONFLICT (canonical_hash) DO UPDATE SET blurb=excluded.blurb, rep_photo=excluded.rep_photo, photo_count=excluded.photo_count;

-- ---- Ortigia: a Sicilian antipasto spread (food-culture POI, evening) ----
INSERT INTO dim_poi (destination_sk, name, poi_type, latitude, longitude, photo_count, rep_photo, photo_date, blurb, info_source, canonical_hash)
VALUES (
  (SELECT destination_sk FROM dim_destination WHERE name='Ortigia'),
  'A Sicilian antipasto table', 'view', 37.0610, 15.2960, 29, '/photos/poi/ortigia-antipasto.jpg', DATE '2022-04-04',
  'Part of the point of Ortigia in the evening: a shared antipasto of arancini, pistachio-crumbed bites, cured meats and cheeses, served in painted ceramic. Less a sight than a habit worth keeping.',
  'own observation', 'ortigia-antipasto'
)
ON CONFLICT (canonical_hash) DO UPDATE SET blurb=excluded.blurb, rep_photo=excluded.rep_photo, photo_count=excluded.photo_count;
