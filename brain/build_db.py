#!/usr/bin/env python3
"""Build the travel-curation DuckDB brain from SQL files.

Creates (or rebuilds) curation.duckdb, applies schema.sql, optionally seeds it,
and runs style_fit.sql so curation_decision is populated. Idempotent schema; the
seed is intended for a fresh DB (use --reset to start clean).

Usage:
    python build_db.py                 # create/upgrade schema, seed if empty, score
    python build_db.py --reset         # delete the DB file first, then build+seed+score
    python build_db.py --no-seed       # schema only, no seed
    python build_db.py --db path.duckdb
"""
from __future__ import annotations

import argparse
from pathlib import Path

import duckdb

HERE = Path(__file__).parent
DEFAULT_DB = HERE / "curation.duckdb"


def _run_sql_file(con: duckdb.DuckDBPyConnection, path: Path) -> None:
    con.execute(path.read_text(encoding="utf-8"))


def _is_seeded(con: duckdb.DuckDBPyConnection) -> bool:
    tables = {r[0] for r in con.execute("SHOW TABLES").fetchall()}
    if "dim_venue" not in tables:
        return False
    return con.execute("SELECT count(*) FROM dim_venue").fetchone()[0] > 0


def build(db_path: Path, reset: bool, seed: bool) -> None:
    if reset and db_path.exists():
        db_path.unlink()
        print(f"removed {db_path.name}")

    con = duckdb.connect(str(db_path))
    try:
        _run_sql_file(con, HERE / "schema.sql")
        print("schema applied")

        images_schema = HERE / "images_schema.sql"
        if images_schema.exists():
            _run_sql_file(con, images_schema)
            print("images schema applied")

        poi_schema = HERE / "poi_schema.sql"
        if poi_schema.exists():
            _run_sql_file(con, poi_schema)
            print("poi schema applied")

        if seed and not _is_seeded(con):
            _run_sql_file(con, HERE / "seed.sql")
            print("seed applied")
        elif seed:
            print("already seeded — skipping seed")

        # Real research ingestion (corrects seed, adds verified venues/mentions).
        # Applied in order; each builds on the prior.
        for fname in ("palermo_research.sql", "palermo_canon_designpress.sql",
                      "venue_websites.sql", "ortigia_research.sql",
                      "poi_data.sql", "poi_expansion.sql",
                      "destination_images.sql",
                      "poi_only_pages.sql", "agrigento_cefalu_venues.sql"):
            f = HERE / fname
            if seed and f.exists():
                _run_sql_file(con, f)
                print(f"{fname} applied")

        _run_sql_file(con, HERE / "style_fit.sql")
        print("style_fit scored")

        rows = con.execute(
            """
            SELECT v.name, v.venue_type, cd.style_fit, cd.shortlisted
            FROM curation_decision cd
            JOIN dim_venue v USING (venue_sk)
            ORDER BY cd.style_fit DESC
            """
        ).fetchall()
        print("\nshortlist (active taste profile):")
        for name, vtype, fit, short in rows:
            flag = "* shortlisted" if short else "  -"
            print(f"  {fit:>6}  {flag:<14} {name} ({vtype})")
    finally:
        con.close()


def main() -> None:
    ap = argparse.ArgumentParser(description="Build the travel-curation DuckDB brain.")
    ap.add_argument("--db", type=Path, default=DEFAULT_DB)
    ap.add_argument("--reset", action="store_true", help="delete the DB file before building")
    ap.add_argument("--no-seed", dest="seed", action="store_false", help="skip seeding")
    args = ap.parse_args()
    build(args.db, reset=args.reset, seed=args.seed)


if __name__ == "__main__":
    main()
