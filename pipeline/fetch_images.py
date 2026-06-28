#!/usr/bin/env python3
"""
Image candidate fetcher (royalty-free, attribution-first).

Queries Unsplash and/or Pexels for venue images, stores candidates in dim_image,
and lets you approve one per venue. Same "shortlist -> approve" model as venues.

Both providers are free + royalty-free but REQUIRE attribution (photographer +
link back). We always store the credit; the renderer always shows it.

Usage:
    python fetch_images.py --venue "Gagini"                 # fetch candidates for one venue
    python fetch_images.py --all                            # fetch for every shortlisted venue
    python fetch_images.py --list "Gagini"                  # show candidates for a venue
    python fetch_images.py --approve <image_sk>             # approve one candidate (clears others)

Environment (set whichever you have; the fetcher uses what's available):
    UNSPLASH_ACCESS_KEY    free at https://unsplash.com/developers
    PEXELS_API_KEY         free at https://www.pexels.com/api/
    CURATION_DB            path to curation.duckdb
"""
from __future__ import annotations

import os
import json
import argparse
from pathlib import Path

import duckdb

try:
    import httpx
except ImportError:
    httpx = None

DEFAULT_DB = Path(__file__).parent.parent / "brain" / "curation.duckdb"
DB_PATH = Path(os.environ.get("CURATION_DB", str(DEFAULT_DB)))
PER_VENUE = 4  # candidates to fetch per venue per provider


def _connect(read_only: bool = False) -> duckdb.DuckDBPyConnection:
    return duckdb.connect(str(DB_PATH), read_only=read_only)


def _query_for(name: str, vtype: str, destination: str | None) -> str:
    """Build a design-leaning image query anchored to the venue's own destination.
    Stock rarely matches a specific venue, so we anchor on place + type + 'Sicily'
    for a coherent, on-brand look across the site."""
    base = {"hotel": "boutique hotel", "restaurant": "restaurant interior",
            "bar": "cafe", "other": "interior"}.get(vtype, "interior")
    place = destination or "Sicily"
    return f"{place} Sicily {base}"


# --------------------------------------------------------------------------
# Providers
# --------------------------------------------------------------------------

def fetch_unsplash(query: str, n: int) -> list[dict]:
    key = os.environ.get("UNSPLASH_ACCESS_KEY")
    if not key or not httpx:
        return []
    r = httpx.get("https://api.unsplash.com/search/photos",
                  params={"query": query, "per_page": n, "orientation": "landscape"},
                  headers={"Authorization": f"Client-ID {key}"}, timeout=20)
    r.raise_for_status()
    out = []
    for p in r.json().get("results", []):
        out.append({
            "provider": "unsplash", "provider_id": p["id"],
            "url_full": p["urls"]["regular"], "url_thumb": p["urls"]["thumb"],
            "width": p.get("width"), "height": p.get("height"),
            "photographer": p["user"]["name"],
            "photographer_url": p["user"]["links"]["html"] + "?utm_source=travel_curation&utm_medium=referral",
            "credit_url": p["links"]["html"] + "?utm_source=travel_curation&utm_medium=referral",
            "alt_text": p.get("alt_description") or query, "query": query,
        })
    return out


def fetch_pexels(query: str, n: int) -> list[dict]:
    key = os.environ.get("PEXELS_API_KEY")
    if not key or not httpx:
        return []
    r = httpx.get("https://api.pexels.com/v1/search",
                  params={"query": query, "per_page": n, "orientation": "landscape"},
                  headers={"Authorization": key}, timeout=20)
    r.raise_for_status()
    out = []
    for p in r.json().get("photos", []):
        out.append({
            "provider": "pexels", "provider_id": str(p["id"]),
            "url_full": p["src"]["large"], "url_thumb": p["src"]["tiny"],
            "width": p.get("width"), "height": p.get("height"),
            "photographer": p["photographer"], "photographer_url": p["photographer_url"],
            "credit_url": p["url"], "alt_text": p.get("alt") or query, "query": query,
        })
    return out


# --------------------------------------------------------------------------
# Store / approve
# --------------------------------------------------------------------------

def _venues(con, name_like: str | None, all_shortlisted: bool):
    if name_like:
        return con.execute("""
            SELECT v.venue_sk, v.name, v.venue_type, d.name AS destination
            FROM dim_venue v LEFT JOIN dim_destination d ON d.destination_sk = v.destination_sk
            WHERE v.name ILIKE ?""", [f"%{name_like}%"]).fetchall()
    if all_shortlisted:
        return con.execute("""
            SELECT v.venue_sk, v.name, v.venue_type, d.name AS destination
            FROM curation_decision cd JOIN dim_venue v USING(venue_sk)
            JOIN dim_taste_profile tp USING(taste_sk)
            LEFT JOIN dim_destination d ON d.destination_sk = v.destination_sk
            WHERE tp.is_active AND cd.shortlisted ORDER BY cd.style_fit DESC
        """).fetchall()
    return []


def fetch(name_like: str | None, all_shortlisted: bool) -> None:
    have_key = bool(os.environ.get("UNSPLASH_ACCESS_KEY") or os.environ.get("PEXELS_API_KEY"))
    if not have_key:
        print("No UNSPLASH_ACCESS_KEY or PEXELS_API_KEY set — nothing to fetch.")
        print("Get a free key: https://unsplash.com/developers or https://www.pexels.com/api/")
        return
    if not httpx:
        print("pip install httpx")
        return

    with _connect() as con:
        venues = _venues(con, name_like, all_shortlisted)
        if not venues:
            print("No matching venues.")
            return
        for venue_sk, name, vtype, destination in venues:
            q = _query_for(name, vtype, destination)
            cands = fetch_unsplash(q, PER_VENUE) + fetch_pexels(q, PER_VENUE)
            stored = 0
            for c in cands:
                con.execute("""
                    INSERT INTO dim_image (venue_sk, provider, provider_id, url_full, url_thumb,
                        width, height, photographer, photographer_url, credit_url, alt_text, query)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT (venue_sk, provider, provider_id) DO NOTHING
                """, [venue_sk, c["provider"], c["provider_id"], c["url_full"], c["url_thumb"],
                      c["width"], c["height"], c["photographer"], c["photographer_url"],
                      c["credit_url"], c["alt_text"], c["query"]])
                stored += 1
            print(f"  {name}: fetched {len(cands)} candidate(s) (query '{q}')")


def list_candidates(name_like: str) -> None:
    with _connect(read_only=True) as con:
        rows = con.execute("""
            SELECT i.image_sk, v.name, i.provider, i.photographer, i.approved, i.alt_text, i.url_full
            FROM dim_image i JOIN dim_venue v USING(venue_sk)
            WHERE v.name ILIKE ? ORDER BY v.name, i.approved DESC, i.image_sk
        """, [f"%{name_like}%"]).fetchall()
    if not rows:
        print("No candidates. Fetch first (needs an API key).")
        return
    for sk, name, prov, photog, appr, alt, url in rows:
        flag = "APPROVED" if appr else "        "
        print(f"  [{sk}] {flag} {name} | {prov} · {photog} | {alt[:50]}")


def approve(image_sk: int) -> None:
    with _connect() as con:
        row = con.execute("SELECT venue_sk FROM dim_image WHERE image_sk = ?", [image_sk]).fetchone()
        if not row:
            print(f"No image with image_sk={image_sk}")
            return
        venue_sk = row[0]
        con.execute("UPDATE dim_image SET approved = FALSE, decided_at = now() WHERE venue_sk = ?", [venue_sk])
        con.execute("UPDATE dim_image SET approved = TRUE, decided_at = now() WHERE image_sk = ?", [image_sk])
        nm = con.execute("""SELECT v.name, i.photographer FROM dim_image i
            JOIN dim_venue v USING(venue_sk) WHERE i.image_sk = ?""", [image_sk]).fetchone()
    print(f"Approved image {image_sk} for {nm[0]} (photo by {nm[1]}).")


def main() -> None:
    ap = argparse.ArgumentParser(description="Fetch + approve royalty-free venue images.")
    ap.add_argument("--venue", help="fetch candidates for venues matching this name")
    ap.add_argument("--all", action="store_true", help="fetch for all shortlisted venues")
    ap.add_argument("--list", dest="list_name", help="list candidates for a venue")
    ap.add_argument("--approve", type=int, help="approve a candidate by image_sk")
    args = ap.parse_args()

    if args.approve is not None:
        approve(args.approve)
    elif args.list_name:
        list_candidates(args.list_name)
    elif args.venue or args.all:
        fetch(args.venue, args.all)
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
