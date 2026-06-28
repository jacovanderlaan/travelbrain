#!/usr/bin/env python3
"""
Match a photo (or a folder of photos) to a GPS location via Google Timeline history.

Most photos in photos.duckdb lack GPS, but the `timeline_points` table has 176k
GPS points (2013-2026, from Google Takeout). We match each photo's capture time to
the nearest-in-time timeline point, yielding a real lat/lon — then optionally
reverse-geocode to the nearest GeoNames city.

This is the "match photos with missing location on Google location history" capability.

Usage:
    python match_photo_location.py --date 2022-04-05            # all timeline pts that day
    python match_photo_location.py --ts "2022-04-05T10:32:43"   # nearest point to a timestamp
    python match_photo_location.py --folder "D:/media/photos/private/2022/2022-04" \
        --filter-eagle "Sicily"   # match every Sicily photo's yaml capture_date -> lat/lon

Environment:
    PHOTOS_DB   path to photos.duckdb (default D:/data/databases/photos.duckdb)
"""
from __future__ import annotations

import os
import re
import sys
import glob
import argparse
from pathlib import Path

import duckdb

PHOTOS_DB = os.environ.get("PHOTOS_DB", r"D:\data\databases\photos.duckdb")
MAX_GAP_MIN = 90  # don't trust a match if nearest timeline point is >90 min away


def _con():
    return duckdb.connect(PHOTOS_DB, read_only=True)


def nearest_point(con, ts: str):
    """Nearest timeline point to a timestamp, with the time gap in minutes."""
    row = con.execute("""
        SELECT lat, lon, ts,
               abs(epoch(ts) - epoch(CAST(? AS TIMESTAMP))) / 60.0 AS gap_min
        FROM timeline_points
        ORDER BY gap_min ASC
        LIMIT 1
    """, [ts]).fetchone()
    if not row:
        return None
    return {"lat": row[0], "lon": row[1], "point_ts": str(row[2]), "gap_min": round(row[3], 1)}


def reverse_geocode(con, lat: float, lon: float):
    """Nearest GeoNames city to a lat/lon (cheap squared-distance, fine at city scale)."""
    try:
        row = con.execute("""
            SELECT name, country_code,
                   (lat - ?)*(lat - ?) + (lon - ?)*(lon - ?) AS d2
            FROM geonames_cities
            ORDER BY d2 ASC LIMIT 1
        """, [lat, lat, lon, lon]).fetchone()
        return {"city": row[0], "country": row[1]} if row else None
    except duckdb.Error:
        return None


def _capture_date_from_yaml(yaml_path: Path) -> str | None:
    txt = yaml_path.read_text(encoding="utf-8", errors="ignore")
    m = re.search(r"capture_date:\s*([0-9T:\-+.]+)", txt)
    return m.group(1) if m else None


def match_folder(folder: str, filter_eagle: str | None) -> None:
    con = _con()
    yamls = glob.glob(str(Path(folder) / "*.yaml"))
    matched = 0
    by_city: dict[str, int] = {}
    for y in yamls:
        yp = Path(y)
        txt = yp.read_text(encoding="utf-8", errors="ignore")
        if filter_eagle and filter_eagle.lower() not in txt.lower():
            continue
        cd = _capture_date_from_yaml(yp)
        if not cd:
            continue
        pt = nearest_point(con, cd.replace("Z", ""))
        if not pt or pt["gap_min"] > MAX_GAP_MIN:
            continue
        geo = reverse_geocode(con, pt["lat"], pt["lon"])
        city = geo["city"] if geo else "?"
        by_city[city] = by_city.get(city, 0) + 1
        matched += 1
    con.close()
    print(f"matched {matched} photos to a location (filter='{filter_eagle or 'none'}')")
    print("by nearest city:")
    for city, n in sorted(by_city.items(), key=lambda kv: -kv[1]):
        print(f"  {n:>4}  {city}")


def main() -> None:
    ap = argparse.ArgumentParser(description="Match photos to GPS via Google Timeline history.")
    ap.add_argument("--ts", help="match nearest timeline point to this timestamp")
    ap.add_argument("--date", help="show timeline points for a date (YYYY-MM-DD)")
    ap.add_argument("--folder", help="folder of photos (uses .yaml capture_date)")
    ap.add_argument("--filter-eagle", help="only photos whose .yaml mentions this (e.g. 'Sicily')")
    args = ap.parse_args()

    if args.folder:
        match_folder(args.folder, args.filter_eagle)
    elif args.ts:
        con = _con()
        pt = nearest_point(con, args.ts)
        if pt:
            geo = reverse_geocode(con, pt["lat"], pt["lon"])
            print(pt, "->", geo)
        else:
            print("no timeline points found")
        con.close()
    elif args.date:
        con = _con()
        rows = con.execute("""
            SELECT round(lat,3), round(lon,3), count(*) FROM timeline_points
            WHERE ts::DATE = ? GROUP BY 1,2 ORDER BY 3 DESC
        """, [args.date]).fetchall()
        for r in rows:
            print(f"  {r[0]},{r[1]}: {r[2]} pts")
        con.close()
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
