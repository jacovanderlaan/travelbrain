-- ============================================================
-- Travel Curation Brain — DuckDB schema (editorial curation model)
-- Source of truth: data-ai-affiliate-platform-reference.md (Part II, sec 12-18)
--
-- Design: heterogeneous source canon (magazines, books, blogs, critics) emits
-- conformed `fact_mention` evidence about venues; an explicit, versioned taste
-- rubric scores venues into a `style_fit` shortlist; a human approves; approved
-- venues feed the drafting pipeline. The AI never queries this DB directly — it
-- receives frozen, hashed briefs assembled from these tables.
--
-- Idempotent: safe to re-run (CREATE ... IF NOT EXISTS, sequences guarded).
-- ============================================================

-- ------------------------------------------------------------
-- CONFORMED DIMENSIONS (shared with the price-data model, Part I)
-- ------------------------------------------------------------

CREATE SEQUENCE IF NOT EXISTS seq_destination START 1;
CREATE TABLE IF NOT EXISTS dim_destination (
    destination_sk BIGINT PRIMARY KEY DEFAULT nextval('seq_destination'),
    geonames_id    BIGINT,                  -- natural key
    name           VARCHAR NOT NULL,
    dest_type      VARCHAR NOT NULL,        -- city | region | country
    parent_sk      BIGINT,                  -- self-ref hierarchy: Palermo -> Sicily -> Italy
    country_code   VARCHAR(2),
    latitude       DOUBLE,
    longitude      DOUBLE,
    timezone       VARCHAR,
    UNIQUE (geonames_id)
);

CREATE SEQUENCE IF NOT EXISTS seq_provider START 1;
CREATE TABLE IF NOT EXISTS dim_provider (
    provider_sk       BIGINT PRIMARY KEY DEFAULT nextval('seq_provider'),
    name              VARCHAR NOT NULL,
    affiliate_network VARCHAR,              -- tradetracker | awin | booking_direct
    commission_model  VARCHAR,              -- cpa | cpc | revshare
    commission_rate   DECIMAL(6,4),
    tracking_template VARCHAR,              -- url template w/ {site}/{subject} slots
    is_active         BOOLEAN DEFAULT TRUE,
    UNIQUE (name)
);

CREATE SEQUENCE IF NOT EXISTS seq_site START 1;
CREATE TABLE IF NOT EXISTS dim_site (
    site_sk           BIGINT PRIMARY KEY DEFAULT nextval('seq_site'),
    slug              VARCHAR NOT NULL,     -- 'adults-design-led'
    domain            VARCHAR,
    niche_filter      JSON,                 -- declarative subject filter
    theme             VARCHAR,
    default_providers BIGINT[],
    UNIQUE (slug)
);

-- ------------------------------------------------------------
-- SOURCE CANON (heterogeneous, actively curated)
-- ------------------------------------------------------------

CREATE SEQUENCE IF NOT EXISTS seq_source START 1;
CREATE TABLE IF NOT EXISTS dim_source (
    source_sk        BIGINT PRIMARY KEY DEFAULT nextval('seq_source'),
    name             VARCHAR NOT NULL,        -- 'Monocle', 'Cereal Guides', 'Marina O''Loughlin'
    source_type      VARCHAR NOT NULL,        -- magazine | book | blog | newsletter |
                                              -- podcast | guide | critic | hotel_collection | list
    medium           VARCHAR,                 -- print | web | rss | audio | mixed
    authority_weight DECIMAL(3,2),            -- your trust weighting 0-1
    editorial_lean   VARCHAR[],               -- ['design','culinary','independent','slow-travel']
    cadence          VARCHAR,                 -- evergreen | annual | monthly | rolling
    ingest_method    VARCHAR,                 -- rss | manual | api | scrape | transcript
    url_root         VARCHAR,
    -- book-specific (NULL otherwise):
    author           VARCHAR,
    isbn             VARCHAR,
    publisher        VARCHAR,
    publication_year INTEGER,
    -- person-specific (critic / blogger):
    person_name      VARCHAR,
    notes            VARCHAR,                 -- why you trust it
    is_active        BOOLEAN DEFAULT TRUE,
    added_at         TIMESTAMP DEFAULT now(),
    UNIQUE (name)
);

-- Authority is per-source AND per-domain: a food critic should not lend weight
-- to a hotel's *design* credibility. Keeps each source in its lane.
CREATE TABLE IF NOT EXISTS source_competence (
    source_sk BIGINT NOT NULL REFERENCES dim_source(source_sk),
    domain    VARCHAR NOT NULL,        -- design | food | hospitality | location
    weight    DECIMAL(3,2),
    PRIMARY KEY (source_sk, domain)
);

-- Self-tuning log: why a source was added/dropped; authority_weight bumps/decays
-- as a source's picks survive (or fail) your shortlist approval over time.
CREATE TABLE IF NOT EXISTS source_review (
    source_sk   BIGINT NOT NULL REFERENCES dim_source(source_sk),
    reviewed_at TIMESTAMP DEFAULT now(),
    action      VARCHAR,                 -- added | bumped | decayed | dropped
    reason      VARCHAR
);

-- ------------------------------------------------------------
-- VENUES + PROVIDER MAP
-- ------------------------------------------------------------

CREATE SEQUENCE IF NOT EXISTS seq_venue START 1;
CREATE TABLE IF NOT EXISTS dim_venue (
    venue_sk       BIGINT PRIMARY KEY DEFAULT nextval('seq_venue'),
    venue_type     VARCHAR NOT NULL,         -- hotel | restaurant | bar | other
    name           VARCHAR NOT NULL,
    destination_sk BIGINT REFERENCES dim_destination(destination_sk),
    latitude       DOUBLE,
    longitude      DOUBLE,
    adults_only    BOOLEAN,                  -- NULL = unknown (research flag, not a penalty)
    child_policy   VARCHAR,                  -- adults_only | adults_preferred | family | unknown
    room_count     INTEGER,                  -- small = intimate signal
    ownership      VARCHAR,                  -- independent | small_group | chain
    has_restaurant BOOLEAN,
    design_notes   VARCHAR,                  -- short factual descriptor (your words)
    website        VARCHAR,
    canonical_hash VARCHAR,                  -- dedup key (name+geo normalised)
    UNIQUE (canonical_hash)
);

CREATE TABLE IF NOT EXISTS map_venue_provider (
    venue_sk     BIGINT NOT NULL REFERENCES dim_venue(venue_sk),
    provider_sk  BIGINT NOT NULL REFERENCES dim_provider(provider_sk),
    provider_ref VARCHAR NOT NULL,           -- affiliate deeplink slug / their id
    PRIMARY KEY (venue_sk, provider_sk)
);

-- ------------------------------------------------------------
-- EVIDENCE: grain = one source talking about one venue once
-- Copyright discipline is in the schema: store structured signals + provenance,
-- never the publication's paragraphs. quote_short is rare, <15-word, attributed.
-- ------------------------------------------------------------

CREATE SEQUENCE IF NOT EXISTS seq_mention START 1;
CREATE TABLE IF NOT EXISTS fact_mention (
    mention_sk     BIGINT PRIMARY KEY DEFAULT nextval('seq_mention'),
    venue_sk       BIGINT NOT NULL REFERENCES dim_venue(venue_sk),
    source_sk      BIGINT NOT NULL REFERENCES dim_source(source_sk),
    domain         VARCHAR,                  -- design | food | hospitality | location
                                             -- (which lane this mention speaks to)
    published_date DATE,
    source_url     VARCHAR,                  -- provenance link (optional; NULL for books)
    locator        VARCHAR,                  -- 'p.142' | 'ch.3' | '12:40 (podcast)'
    sentiment      VARCHAR,                  -- recommended | praised | mixed | listed
    descriptors    VARCHAR[],                -- ['restrained interiors','adults-only','quiet']
    quote_short    VARCHAR,                  -- rare, <15-word, attributed; sparingly
    accolade       VARCHAR,                  -- 'Michelin 1*', 'Gold List 2024', NULL
    extracted_at   TIMESTAMP NOT NULL DEFAULT now(),
    UNIQUE (venue_sk, source_sk, published_date)
);

-- ------------------------------------------------------------
-- TASTE PROFILE (versioned rubric: hard excludes + weighted boosts)
-- ------------------------------------------------------------

CREATE SEQUENCE IF NOT EXISTS seq_taste START 1;
CREATE TABLE IF NOT EXISTS dim_taste_profile (
    taste_sk  BIGINT PRIMARY KEY DEFAULT nextval('seq_taste'),
    name      VARCHAR NOT NULL,              -- 'adults / design-led / quiet'
    version   INTEGER NOT NULL,
    rubric    JSON NOT NULL,                 -- exclude{} + boost{}
    is_active BOOLEAN DEFAULT TRUE,
    UNIQUE (name, version)
);

-- ------------------------------------------------------------
-- CURATION DECISION (human-in-the-loop: "approve shortlists, trust the rest")
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS curation_decision (
    venue_sk    BIGINT NOT NULL REFERENCES dim_venue(venue_sk),
    taste_sk    BIGINT NOT NULL REFERENCES dim_taste_profile(taste_sk),
    style_fit   DECIMAL(5,2),
    shortlisted BOOLEAN,
    decision    VARCHAR,                  -- approved | rejected | hold | research
    decided_by  VARCHAR DEFAULT 'editor',
    rationale   VARCHAR,                  -- your note; also trains source weights
    decided_at  TIMESTAMP,
    PRIMARY KEY (venue_sk, taste_sk)
);

-- ------------------------------------------------------------
-- CONTENT + PROVENANCE BRIDGE
-- (brief = hashed snapshot; bridge = full provenance from sentence to source)
-- ------------------------------------------------------------

CREATE SEQUENCE IF NOT EXISTS seq_content START 1;
CREATE TABLE IF NOT EXISTS dim_content (
    content_sk        BIGINT PRIMARY KEY DEFAULT nextval('seq_content'),
    site_sk           BIGINT NOT NULL REFERENCES dim_site(site_sk),
    content_type      VARCHAR,               -- guide | venue_profile | shortlist | itinerary
    title             VARCHAR,
    slug              VARCHAR,
    body_md           TEXT,
    frontmatter       JSON,
    status            VARCHAR DEFAULT 'draft',  -- draft | quarantine | ready | published
    source_brief_hash VARCHAR NOT NULL,      -- the freeze key for regeneration
    version           INTEGER DEFAULT 1,
    generated_at      TIMESTAMP,
    UNIQUE (site_sk, slug)
);

-- Links published content to the venues AND the mentions that justified them:
-- full provenance from a published sentence back to its source.
CREATE TABLE IF NOT EXISTS bridge_content_subject (
    content_sk   BIGINT NOT NULL REFERENCES dim_content(content_sk),
    subject_type VARCHAR NOT NULL,          -- venue | mention | destination | source
    subject_sk   BIGINT NOT NULL,
    role         VARCHAR,                   -- primary | comparison | context | evidence
    PRIMARY KEY (content_sk, subject_type, subject_sk, role)
);
