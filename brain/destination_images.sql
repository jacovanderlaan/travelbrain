-- ============================================================
-- Destination header images — Jaco's OWN photos (Sicily, April 2022 trip).
-- Replaces the earlier Unsplash stock headers. These are owned, copyright-clean,
-- authentic photos from the real April-2022 Sicily trip (with Annemarie + mother).
-- Credit: Jaco van der Laan. Served locally from /photos/ (committed to the site).
-- See memory sicily-2022-trip-real.
-- ============================================================

INSERT INTO dim_destination_image (destination_sk, provider, url_full, photographer, photographer_url, credit_url, alt_text)
VALUES (
  (SELECT destination_sk FROM dim_destination WHERE name='Palermo'),
  'own',
  '/photos/palermo-sicily-2022.jpg',
  'Jaco van der Laan',
  NULL,
  NULL,
  'A Palermo palazzo facade — wrought-iron balconies and shutters — Jaco van der Laan, April 2022'
)
ON CONFLICT (destination_sk) DO UPDATE SET provider=excluded.provider, url_full=excluded.url_full,
  photographer=excluded.photographer, photographer_url=excluded.photographer_url,
  credit_url=excluded.credit_url, alt_text=excluded.alt_text;

INSERT INTO dim_destination_image (destination_sk, provider, url_full, photographer, photographer_url, credit_url, alt_text)
VALUES (
  (SELECT destination_sk FROM dim_destination WHERE name='Agrigento'),
  'own', '/photos/agrigento-sicily-2022.jpg', 'Jaco van der Laan', NULL, NULL,
  'The Temple of Concordia, Valley of the Temples, Agrigento — Jaco van der Laan, April 2022'
)
ON CONFLICT (destination_sk) DO UPDATE SET provider=excluded.provider, url_full=excluded.url_full,
  photographer=excluded.photographer, photographer_url=excluded.photographer_url,
  credit_url=excluded.credit_url, alt_text=excluded.alt_text;

INSERT INTO dim_destination_image (destination_sk, provider, url_full, photographer, photographer_url, credit_url, alt_text)
VALUES (
  (SELECT destination_sk FROM dim_destination WHERE name='Cefalù'),
  'own', '/photos/cefalu-sicily-2022.jpg', 'Jaco van der Laan', NULL, NULL,
  'Cefalù old town and beach, fishing boats below the medieval houses — Jaco van der Laan, April 2022'
)
ON CONFLICT (destination_sk) DO UPDATE SET provider=excluded.provider, url_full=excluded.url_full,
  photographer=excluded.photographer, photographer_url=excluded.photographer_url,
  credit_url=excluded.credit_url, alt_text=excluded.alt_text;

INSERT INTO dim_destination_image (destination_sk, provider, url_full, photographer, photographer_url, credit_url, alt_text)
VALUES (
  (SELECT destination_sk FROM dim_destination WHERE name='Ortigia'),
  'own',
  '/photos/ortigia-sicily-2022.jpg',
  'Jaco van der Laan',
  NULL,
  NULL,
  'A quiet Baroque piazza in Ortigia, Siracusa — Jaco van der Laan, April 2022'
)
ON CONFLICT (destination_sk) DO UPDATE SET provider=excluded.provider, url_full=excluded.url_full,
  photographer=excluded.photographer, photographer_url=excluded.photographer_url,
  credit_url=excluded.credit_url, alt_text=excluded.alt_text;
