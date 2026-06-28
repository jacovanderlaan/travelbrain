-- ============================================================
-- POI-only destination pages (Agrigento, Cefalù) — "places I visited".
-- These carry POIs but no eat/stay venue research, so we insert a short content
-- page directly (the POI blurbs are the substance, already sourced). Distinct from
-- the pipeline-drafted venue guides.
-- ============================================================

INSERT INTO dim_content (site_sk, content_type, title, slug, body_md, frontmatter, status, source_brief_hash, version, generated_at)
VALUES (
  (SELECT site_sk FROM dim_site WHERE slug='adults-design-led'),
  'guide', 'Agrigento — the Valley of the Temples', 'agrigento-valley-of-the-temples', E'A day among the best-preserved Greek temples in Sicily, and a couple of places worth knowing if you stay near them.\n\nThe shortlist below is publication-backed; the photos are mine, from the April 2022 trip.',
  '{"destination":"Agrigento","taste":"adults / design-led / quiet"}',
  'ready', 'poi-only-agrigento', 1, now()
)
ON CONFLICT (site_sk, slug) DO UPDATE SET body_md=excluded.body_md, status=excluded.status;

INSERT INTO dim_content (site_sk, content_type, title, slug, body_md, frontmatter, status, source_brief_hash, version, generated_at)
VALUES (
  (SELECT site_sk FROM dim_site WHERE slug='adults-design-led'),
  'guide', 'Cefalù — a medieval town on the sea', 'cefalu-medieval-town-on-the-sea', E'A medieval fishing town where the houses meet the sand and a Norman cathedral holds one of Sicily''s great mosaics. Quiet out of season, and one of the prettiest stretches of the north coast. A few old-town stays and tables worth booking are below.\n\nThe shortlist is publication-backed; the photos are mine, from the April 2022 trip.',
  '{"destination":"Cefalù","taste":"adults / design-led / quiet"}',
  'ready', 'poi-only-cefalu', 1, now()
)
ON CONFLICT (site_sk, slug) DO UPDATE SET body_md=excluded.body_md, status=excluded.status;
