-- ============================================================
-- Direct venue websites (the "Visit site" fallback when no affiliate link)
-- Official sites, verified 2026-06-28 via web search. Used by the export's
-- resolve_link() as the direct-link fallback. No affiliate refs here — just the
-- venue's own site, so every coverable venue has a working direct link.
-- ============================================================

UPDATE dim_venue SET website = 'https://www.mecrestaurant.it/en/home/'
  WHERE canonical_hash = 'mec-restaurant-palermo' AND website IS NULL;

UPDATE dim_venue SET website = 'https://ristoranteottavanota.it/'
  WHERE canonical_hash = 'lottava-nota-palermo' AND website IS NULL;

UPDATE dim_venue SET website = 'https://www.ristorantepalazzobranciforte.it/en/'
  WHERE canonical_hash = 'palazzo-branciforte-palermo' AND website IS NULL;

-- Maison Opera: intentionally left without a website — it is a self-catering
-- apartment found via booking aggregators, with no canonical official site. An
-- honest "no link yet" is better than linking to an aggregator we can't vouch for.
