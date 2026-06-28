-- ============================================================
-- POI layer — places of interest extracted from Jaco's OWN trip photos.
-- Method: GPS-cluster located photos (timeline-point match) -> vision-confirm what
-- the cluster shows -> add as a POI with a representative own-photo + researched info.
-- This is the "places I actually photographed" layer, distinct from eat/stay venues.
-- ============================================================

CREATE SEQUENCE IF NOT EXISTS seq_poi START 1;
CREATE TABLE IF NOT EXISTS dim_poi (
    poi_sk          BIGINT PRIMARY KEY DEFAULT nextval('seq_poi'),
    destination_sk  BIGINT REFERENCES dim_destination(destination_sk),
    name            VARCHAR NOT NULL,
    poi_type        VARCHAR,            -- landmark | square | fountain | church | monument | view
    latitude        DOUBLE,
    longitude       DOUBLE,
    -- derived from own photos:
    photo_count     INTEGER,            -- how many of my photos cluster here
    rep_photo       VARCHAR,            -- representative own-photo (served from /photos/poi/)
    photo_credit    VARCHAR DEFAULT 'Jaco van der Laan',
    photo_date      DATE,
    -- gathered info (researched; keep factual + attributable):
    blurb           VARCHAR,            -- 1-3 sentence interesting summary (original prose)
    info_source     VARCHAR,            -- where the facts came from
    canonical_hash  VARCHAR,
    UNIQUE (canonical_hash)
);

-- POIs link to the destination page via the content bridge (subject_type='poi').
