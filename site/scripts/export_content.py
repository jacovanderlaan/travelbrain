#!/usr/bin/env python3
"""
Build-time export: curation.duckdb -> site/src/content.json

Astro reads the JSON at build time (DuckDB stays out of the Node toolchain; the
brain remains the single source of truth). Exports ready/published pages for the
active site, plus each page's venues with resolved affiliate links and provenance.

Affiliate links: resolved from map_venue_provider + dim_provider.tracking_template.
Where a venue has NO provider mapping, link is null — the page shows an honest
"no booking link yet" state rather than a fabricated URL.

Usage:
    python export_content.py            # writes ../src/content.json
    CURATION_DB=... python export_content.py
"""
from __future__ import annotations

import os
import json
from pathlib import Path

import duckdb

HERE = Path(__file__).parent
DB_PATH = Path(os.environ.get("CURATION_DB", str(HERE.parent.parent / "brain" / "curation.duckdb")))
OUT = HERE.parent / "src" / "content.json"
SITE_SLUG = os.environ.get("SITE_SLUG", "adults-design-led")


def _rows(con, sql, params=None):
    cur = con.execute(sql, params or [])
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def resolve_link(con, venue_sk: int, website: str | None, site_slug: str) -> dict | None:
    """Prefer a real affiliate deeplink; else fall back to the venue's own website.

    Returns {kind, url, label, provider?} or None when there's no link at all.
      kind='affiliate' -> a provider mapping exists (rel=sponsored nofollow, "Book")
      kind='site'      -> the venue's own website     (rel=nofollow,           "Visit site")
    No affiliate ref is ever fabricated — affiliate only when map_venue_provider says so.
    """
    maps = _rows(con, """
        SELECT p.name AS provider, p.tracking_template, mvp.provider_ref
        FROM map_venue_provider mvp JOIN dim_provider p USING (provider_sk)
        WHERE mvp.venue_sk = ? AND p.is_active
    """, [venue_sk])
    if maps:
        m = maps[0]
        url = (m["tracking_template"] or "")
        url = url.replace("{provider_ref}", m["provider_ref"] or "")
        url = url.replace("{site}", site_slug)
        return {"kind": "affiliate", "provider": m["provider"],
                "url": url, "label": f"Book · {m['provider']}"}
    if website:
        return {"kind": "site", "url": website, "label": "Visit site"}
    return None


def main() -> None:
    if not DB_PATH.exists():
        raise SystemExit(f"DB not found: {DB_PATH}. Run brain/build_db.py first.")
    con = duckdb.connect(str(DB_PATH), read_only=True)
    try:
        pages = _rows(con, """
            SELECT c.content_sk, c.title, c.slug, c.body_md, c.frontmatter,
                   c.status, c.source_brief_hash, c.version, c.generated_at
            FROM dim_content c JOIN dim_site s USING (site_sk)
            WHERE s.slug = ? AND c.status IN ('ready','published')
            ORDER BY c.generated_at DESC
        """, [SITE_SLUG])

        for pg in pages:
            pg["frontmatter"] = json.loads(pg["frontmatter"]) if pg.get("frontmatter") else {}
            # one atmospheric destination header image (place shot, not a venue photo)
            dest = (pg["frontmatter"] or {}).get("destination")
            pg["header_image"] = None
            if dest:
                try:
                    hdr = _rows(con, """
                        SELECT di.url_full, di.alt_text, di.provider,
                               di.photographer, di.photographer_url, di.credit_url
                        FROM dim_destination_image di
                        JOIN dim_destination d USING (destination_sk)
                        WHERE d.name = ?
                    """, [dest])
                    pg["header_image"] = hdr[0] if hdr else None
                except duckdb.CatalogException:
                    pass
            # POIs photographed on the trip, for this destination
            pg["pois"] = []
            if dest:
                try:
                    pg["pois"] = _rows(con, """
                        SELECT p.name, p.poi_type, p.rep_photo, p.photo_credit,
                               p.photo_date, p.photo_count, p.blurb, p.info_source
                        FROM dim_poi p JOIN dim_destination d USING (destination_sk)
                        WHERE d.name = ? ORDER BY p.photo_count DESC
                    """, [dest])
                except duckdb.CatalogException:
                    pass
            # venues bridged to this page, with evidence + affiliate link
            venues = _rows(con, """
                SELECT v.venue_sk, v.name, v.venue_type, v.website, v.design_notes,
                       v.ownership, v.adults_only, v.child_policy,
                       cd.style_fit
                FROM bridge_content_subject bcs
                JOIN dim_venue v ON v.venue_sk = bcs.subject_sk
                LEFT JOIN curation_decision cd ON cd.venue_sk = v.venue_sk
                LEFT JOIN dim_taste_profile tp ON tp.taste_sk = cd.taste_sk AND tp.is_active
                WHERE bcs.content_sk = ? AND bcs.subject_type = 'venue'
                ORDER BY cd.style_fit DESC NULLS LAST
            """, [pg["content_sk"]])
            # Fallback for pages built without a pipeline bridge (POI-only pages that
            # later gained venues): show the destination's shortlisted venues.
            if not venues and dest:
                venues = _rows(con, """
                    SELECT v.venue_sk, v.name, v.venue_type, v.website, v.design_notes,
                           v.ownership, v.adults_only, v.child_policy, cd.style_fit
                    FROM curation_decision cd
                    JOIN dim_venue v USING (venue_sk)
                    JOIN dim_taste_profile tp USING (taste_sk)
                    JOIN dim_destination d ON d.destination_sk = v.destination_sk
                    WHERE tp.is_active AND cd.shortlisted AND d.name = ?
                    ORDER BY cd.style_fit DESC
                """, [dest])
            for v in venues:
                v["link"] = resolve_link(con, v["venue_sk"], v.get("website"), SITE_SLUG)
                v["sources"] = sorted({m["source"] for m in _rows(con,
                    "SELECT DISTINCT s.name AS source FROM fact_mention m "
                    "JOIN dim_source s USING(source_sk) WHERE m.venue_sk = ?",
                    [v["venue_sk"]])})
                # the one approved royalty-free image, with mandatory attribution
                try:
                    img = _rows(con, """
                        SELECT url_full, url_thumb, alt_text, provider,
                               photographer, photographer_url, credit_url
                        FROM dim_image WHERE venue_sk = ? AND approved LIMIT 1
                    """, [v["venue_sk"]])
                    v["image"] = img[0] if img else None
                except duckdb.CatalogException:
                    v["image"] = None  # images layer not yet in this DB
            pg["venues"] = venues

        site = _rows(con, "SELECT slug, theme, domain FROM dim_site WHERE slug = ?", [SITE_SLUG])
    finally:
        con.close()

    payload = {"site": site[0] if site else {"slug": SITE_SLUG}, "pages": pages}
    OUT.write_text(json.dumps(payload, indent=2, default=str), encoding="utf-8")
    print(f"exported {len(pages)} page(s) -> {OUT.relative_to(HERE.parent.parent)}")
    for pg in pages:
        aff = sum(1 for v in pg["venues"] if v["link"] and v["link"]["kind"] == "affiliate")
        site = sum(1 for v in pg["venues"] if v["link"] and v["link"]["kind"] == "site")
        print(f"  {pg['slug']}: {len(pg['venues'])} venues, "
              f"{aff} affiliate, {site} site-fallback links")


if __name__ == "__main__":
    main()
