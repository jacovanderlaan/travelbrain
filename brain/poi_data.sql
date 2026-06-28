-- ============================================================
-- POIs extracted from Jaco's own Sicily 2022 photos (GPS-clustered + vision-confirmed).
-- Each: a representative own-photo + an original-prose blurb from researched facts.
-- Location method: timeline-point GPS match on photo capture time.
-- ============================================================

-- Fonte Aretusa (Ortigia) — 126-photo cluster at 37.062,15.296; vision-confirmed.
INSERT INTO dim_poi (destination_sk, name, poi_type, latitude, longitude, photo_count, rep_photo, photo_date, blurb, info_source, canonical_hash)
VALUES (
  (SELECT destination_sk FROM dim_destination WHERE name='Ortigia'),
  'Fonte Aretusa', 'fountain', 37.0621, 15.2959, 126, '/photos/poi/fonte-aretusa.jpg', DATE '2022-04-05',
  'A freshwater spring that surfaces metres from the sea, ringed by papyrus — one of the only places in Europe it grows wild. The Greeks settled Ortigia partly for this water; Ovid tied it to the myth of the nymph Arethusa. The present semicircular basin dates to 1843.',
  'Wikipedia (Fountain of Arethusa); Italia.it', 'fonte-aretusa-ortigia'
)
ON CONFLICT (canonical_hash) DO UPDATE SET blurb=excluded.blurb, rep_photo=excluded.rep_photo, photo_count=excluded.photo_count;

-- Piazza del Duomo / Palazzo Vermexio (Ortigia) — 58-photo cluster at 37.066,15.293.
INSERT INTO dim_poi (destination_sk, name, poi_type, latitude, longitude, photo_count, rep_photo, photo_date, blurb, info_source, canonical_hash)
VALUES (
  (SELECT destination_sk FROM dim_destination WHERE name='Ortigia'),
  'Piazza del Duomo', 'square', 37.0590, 15.2933, 58, '/photos/poi/piazza-duomo-ortigia.jpg', DATE '2022-04-05',
  'Ortigia''s Baroque heart — a long pedestrian square of honey-coloured stone, framed by the Cathedral (built into an ancient Greek temple) and the 17th-century Palazzo Vermexio, the town hall. Quiet in the morning, golden in the late afternoon.',
  'on-site observation; municipal records', 'piazza-duomo-ortigia'
)
ON CONFLICT (canonical_hash) DO UPDATE SET blurb=excluded.blurb, rep_photo=excluded.rep_photo, photo_count=excluded.photo_count;

-- Palermo — 100-photo cluster at 38.124,13.356 (Politeama/Teatro district; vision = Baroque facades).
-- Labelled honestly by GPS (180m from Teatro Politeama), NOT claimed as Quattro Canti (1km away).
INSERT INTO dim_poi (destination_sk, name, poi_type, latitude, longitude, photo_count, rep_photo, photo_date, blurb, info_source, canonical_hash)
VALUES (
  (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
  'Around the Politeama theatre district', 'landmark', 38.1240, 13.3560, 100, '/photos/poi/palermo-politeama.jpg', DATE '2022-04-07',
  'The streets around Teatro Politeama — Palermo''s grand 19th-century theatre — open into a stretch of ornate facades, balconies and shopfronts. A good base for walking south into the Baroque historic core toward the Quattro Canti and the Cathedral.',
  'GPS-located; on-site observation', 'palermo-politeama-district'
)
ON CONFLICT (canonical_hash) DO UPDATE SET blurb=excluded.blurb, rep_photo=excluded.rep_photo, photo_count=excluded.photo_count;

-- Palermo Cathedral — 40-photo cluster, vision-confirmed (38.114,13.357 GPS match).
INSERT INTO dim_poi (destination_sk, name, poi_type, latitude, longitude, photo_count, rep_photo, photo_date, blurb, info_source, canonical_hash)
VALUES (
  (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
  'Palermo Cathedral', 'church', 38.1145, 13.3563, 40, '/photos/poi/palermo-cathedral.jpg', DATE '2022-04-07',
  'A building that is its own history lesson: begun in 1185 on the site of a Byzantine basilica that the Arabs had turned into a mosque, then altered for six centuries. The result is the Arab-Norman fusion — pointed arches, lava-stone inlay, crenellations — that earned it UNESCO status in 2015. Inside lie the tombs of Roger II and Frederick II.',
  'UNESCO; Wikipedia (Palermo Cathedral)', 'palermo-cathedral'
)
ON CONFLICT (canonical_hash) DO UPDATE SET blurb=excluded.blurb, rep_photo=excluded.rep_photo, photo_count=excluded.photo_count;
