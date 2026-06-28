-- ============================================================
-- Image candidates layer (royalty-free, attribution-first)
-- Same "candidates -> you approve one" model as venue curation.
--
-- Sources: Unsplash / Pexels APIs (free, royalty-free). BOTH require photographer
-- attribution + a link back — so credit fields are mandatory, not optional. We
-- store the candidate URL + credit; rendering MUST show the attribution.
--
-- Idempotent; safe to re-run.
-- ============================================================

CREATE SEQUENCE IF NOT EXISTS seq_image START 1;
CREATE TABLE IF NOT EXISTS dim_image (
    image_sk        BIGINT PRIMARY KEY DEFAULT nextval('seq_image'),
    venue_sk        BIGINT NOT NULL REFERENCES dim_venue(venue_sk),
    provider        VARCHAR NOT NULL,        -- unsplash | pexels
    provider_id     VARCHAR NOT NULL,        -- the photo id on that provider
    url_full        VARCHAR NOT NULL,        -- display URL (hot-link per provider ToS)
    url_thumb       VARCHAR,
    width           INTEGER,
    height          INTEGER,
    -- ATTRIBUTION (mandatory for both providers' free tiers):
    photographer    VARCHAR NOT NULL,
    photographer_url VARCHAR,                -- link back to photographer profile
    credit_url      VARCHAR,                 -- link back to the photo page (+utm per ToS)
    alt_text        VARCHAR,                 -- accessibility + what the photo shows
    query           VARCHAR,                 -- the search term that surfaced it
    -- CURATION STATE (you approve one per venue):
    approved        BOOLEAN DEFAULT FALSE,
    decided_at      TIMESTAMP,
    fetched_at      TIMESTAMP NOT NULL DEFAULT now(),
    UNIQUE (venue_sk, provider, provider_id)
);

-- At most one approved image per venue (enforced in the approve path; this index
-- documents the intent).
CREATE INDEX IF NOT EXISTS ix_image_approved ON dim_image (venue_sk, approved);

-- ------------------------------------------------------------
-- Page header image per destination (atmospheric mood shot, NOT a venue photo).
-- Decision (2026-06-28): free stock has no real venue interiors, so per-venue
-- stock would mislead. Instead one honest place-header per destination page.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dim_destination_image (
    destination_sk   BIGINT PRIMARY KEY REFERENCES dim_destination(destination_sk),
    provider         VARCHAR NOT NULL,
    url_full         VARCHAR NOT NULL,
    photographer     VARCHAR NOT NULL,
    photographer_url VARCHAR,
    credit_url       VARCHAR,
    alt_text         VARCHAR,
    fetched_at       TIMESTAMP NOT NULL DEFAULT now()
);
