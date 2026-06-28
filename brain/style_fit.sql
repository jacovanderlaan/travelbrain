-- ============================================================
-- style_fit scoring -> shortlist (curation_decision)
-- Reference doc sec 16. Combines:
--   (a) hard-exclude gate from the active rubric,
--   (b) weighted positive signals from venue attributes,
--   (c) corroboration: mentions weighted by source authority x per-domain competence,
--       with diminishing returns and a per-source cap (independent corroboration
--       beats volume), and a recency taper that respects evergreen sources.
--
-- Parameterised on a single active taste profile. Run as a full refresh:
-- it (re)computes style_fit + shortlisted for every venue under the active rubric,
-- WITHOUT clobbering an existing human `decision` (we only upsert the scored cols).
--
-- DuckDB dialect. Reads rubric JSON fields via json_extract.
-- ============================================================

-- The active rubric, flattened to scalars we can use in SQL.
WITH rubric AS (
    SELECT
        taste_sk,
        rubric AS r,
        json_extract_string(rubric, '$.exclude.child_policy')        AS excl_child_policy,   -- json array
        json_extract_string(rubric, '$.exclude.ownership')           AS excl_ownership,      -- json array
        json_extract_string(rubric, '$.exclude.descriptors_any')     AS excl_descriptors,    -- json array
        CAST(json_extract(rubric, '$.boost.adults_only_or_preferred')        AS DOUBLE) AS w_adults,
        CAST(json_extract(rubric, '$.boost.design_or_architecture_coverage') AS DOUBLE) AS w_design,
        CAST(json_extract(rubric, '$.boost.independent_or_small_group')      AS DOUBLE) AS w_indep,
        CAST(json_extract(rubric, '$.boost.small_room_count')               AS DOUBLE) AS w_rooms,
        CAST(json_extract(rubric, '$.boost.has_real_restaurant')           AS DOUBLE) AS w_resto,
        CAST(json_extract(rubric, '$.boost.descriptors_any.weight')        AS DOUBLE) AS w_descr,
        json_extract_string(rubric, '$.boost.descriptors_any.terms')        AS boost_terms  -- json array
    FROM dim_taste_profile
    WHERE is_active
    LIMIT 1
),

-- Hard-exclude gate: a venue that trips any exclusion scores 0 and is not shortlisted.
excluded AS (
    SELECT v.venue_sk
    FROM dim_venue v, rubric rb
    WHERE
        -- child policy in exclusion list
        list_contains(CAST(rb.excl_child_policy AS VARCHAR[]), v.child_policy)
        -- ownership in exclusion list
        OR list_contains(CAST(rb.excl_ownership AS VARCHAR[]), v.ownership)
        -- any venue design_note matches an excluded descriptor (substring, case-insensitive)
        OR EXISTS (
            SELECT 1
            FROM unnest(CAST(rb.excl_descriptors AS VARCHAR[])) AS x(term)
            WHERE v.design_notes IS NOT NULL
              AND lower(v.design_notes) LIKE '%' || lower(x.term) || '%'
        )
),

-- Positive signals from the venue's own attributes.
attr_score AS (
    SELECT
        v.venue_sk,
        rb.taste_sk,
        (CASE WHEN v.adults_only = TRUE OR v.child_policy IN ('adults_only','adults_preferred')
              THEN rb.w_adults ELSE 0 END)
      + (CASE WHEN v.ownership IN ('independent','small_group') THEN rb.w_indep ELSE 0 END)
      + (CASE WHEN v.room_count IS NOT NULL AND v.room_count <= 60 THEN rb.w_rooms ELSE 0 END)
      + (CASE WHEN v.has_restaurant = TRUE THEN rb.w_resto ELSE 0 END)
        AS attr_points
    FROM dim_venue v, rubric rb
),

-- Corroboration: per mention, authority x per-domain competence, recency-tapered
-- (evergreen sources are not penalised for age). Then capped per source and summed
-- with diminishing returns across distinct in-domain sources.
mention_weight AS (
    SELECT
        m.venue_sk,
        m.source_sk,
        s.cadence,
        -- source authority x competence in the mention's lane
        COALESCE(s.authority_weight, 0.5) * COALESCE(sc.weight, 0.3)
        -- recency taper: rolling sources decay ~ per 2 years; evergreen flat
        * CASE
            WHEN s.cadence = 'evergreen' THEN 1.0
            WHEN m.published_date IS NULL THEN 0.7
            ELSE greatest(0.4, 1.0 - (date_diff('year', m.published_date, current_date) * 0.10))
          END AS w
    FROM fact_mention m
    JOIN dim_source s ON s.source_sk = m.source_sk
    LEFT JOIN source_competence sc
           ON sc.source_sk = m.source_sk AND sc.domain = m.domain
),

-- Cap each source's contribution (independent corroboration > volume).
per_source AS (
    SELECT venue_sk, source_sk, least(0.5, sum(w)) AS source_contrib
    FROM mention_weight
    GROUP BY venue_sk, source_sk
),

-- Diminishing returns across distinct sources: sqrt of the summed contributions.
corroboration AS (
    SELECT venue_sk, sqrt(sum(source_contrib)) * 0.30 AS corrob_points
    FROM per_source
    GROUP BY venue_sk
),

-- Design-coverage boost: any in-domain ('design') mention triggers w_design once.
design_cov AS (
    SELECT m.venue_sk, max(rb.w_design) AS design_points
    FROM fact_mention m, rubric rb
    WHERE m.domain = 'design'
    GROUP BY m.venue_sk
),

scored AS (
    SELECT
        v.venue_sk,
        rb.taste_sk,
        CASE WHEN e.venue_sk IS NOT NULL THEN 0.0
        ELSE round(100.0 * least(1.0,
                 COALESCE(a.attr_points, 0)
               + COALESCE(c.corrob_points, 0)
               + COALESCE(d.design_points, 0)
             ), 2)
        END AS style_fit,
        (e.venue_sk IS NULL) AS not_excluded
    FROM dim_venue v
    CROSS JOIN rubric rb
    LEFT JOIN excluded     e ON e.venue_sk = v.venue_sk
    LEFT JOIN attr_score   a ON a.venue_sk = v.venue_sk
    LEFT JOIN corroboration c ON c.venue_sk = v.venue_sk
    LEFT JOIN design_cov   d ON d.venue_sk = v.venue_sk
)

-- Upsert ONLY the scored columns; preserve any existing human decision/rationale.
INSERT INTO curation_decision (venue_sk, taste_sk, style_fit, shortlisted, decision, decided_by, decided_at)
SELECT
    venue_sk, taste_sk, style_fit,
    (not_excluded AND style_fit >= 50.0) AS shortlisted,
    NULL, NULL, NULL
FROM scored
ON CONFLICT (venue_sk, taste_sk) DO UPDATE SET
    style_fit   = excluded.style_fit,
    shortlisted = excluded.shortlisted;
