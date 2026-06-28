#!/usr/bin/env python3
"""
Travel Curation MCP Server

Conversational curation surface for the travel-curation brain (DuckDB). Lets you
inspect the source canon, see ranked shortlists with provenance, drill into a
venue's evidence dossier, and record approval decisions — the interface for
"approve shortlists, trust the rest."

Usage:
    python server.py

Environment:
    CURATION_DB: path to curation.duckdb
                 (default: ../brain/curation.duckdb next to this file)

The AI never writes prose from this server — it reads structured curation data and
records your decisions. Drafting happens in the separate pipeline (PLAN.md stage 4).
"""

import os
import json
import asyncio
from pathlib import Path
from typing import Optional

import duckdb
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

DEFAULT_DB = Path(__file__).parent.parent / "brain" / "curation.duckdb"
DB_PATH = Path(os.environ.get("CURATION_DB", str(DEFAULT_DB)))


def _connect() -> duckdb.DuckDBPyConnection:
    if not DB_PATH.exists():
        raise FileNotFoundError(
            f"Curation DB not found at {DB_PATH}. Build it: "
            f"python travel-curation/brain/build_db.py --reset"
        )
    return duckdb.connect(str(DB_PATH))


def _rows(con, sql: str, params: Optional[list] = None) -> list[dict]:
    cur = con.execute(sql, params or [])
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


# --------------------------------------------------------------------------
# Query helpers (the "read" side of curation)
# --------------------------------------------------------------------------

def get_shortlist(destination: Optional[str], taste: Optional[str], min_fit: float) -> dict:
    """Ranked candidates for a destination under the active (or named) taste profile."""
    with _connect() as con:
        taste_clause = "tp.is_active" if not taste else "tp.name = ?"
        taste_params = [] if not taste else [taste]
        dest_clause = "" if not destination else (
            " AND (d.name = ? OR parent.name = ?)"
        )
        dest_params = [] if not destination else [destination, destination]

        sql = f"""
            SELECT
                v.venue_sk, v.name, v.venue_type, d.name AS destination,
                cd.style_fit, cd.shortlisted, cd.decision,
                v.child_policy, v.ownership, v.room_count,
                (v.adults_only IS NULL) AS adults_policy_unknown,
                (SELECT count(*) FROM fact_mention m WHERE m.venue_sk = v.venue_sk) AS mention_count
            FROM curation_decision cd
            JOIN dim_venue v USING (venue_sk)
            JOIN dim_taste_profile tp USING (taste_sk)
            LEFT JOIN dim_destination d ON d.destination_sk = v.destination_sk
            LEFT JOIN dim_destination parent ON parent.destination_sk = d.parent_sk
            WHERE {taste_clause}{dest_clause}
              AND cd.style_fit >= ?
            ORDER BY cd.style_fit DESC
        """
        rows = _rows(con, sql, taste_params + dest_params + [min_fit])
    # surface open questions per venue
    for r in rows:
        flags = []
        if r.pop("adults_policy_unknown"):
            flags.append("adults policy unconfirmed")
        if r["mention_count"] == 0:
            flags.append("no evidence on file")
        r["flags"] = flags
    return {"destination": destination, "taste": taste or "(active)", "candidates": rows}


def get_venue(venue_sk: int) -> dict:
    """Full evidence dossier for one venue: attributes + every mention with provenance."""
    with _connect() as con:
        venue = _rows(con, """
            SELECT v.*, d.name AS destination
            FROM dim_venue v
            LEFT JOIN dim_destination d ON d.destination_sk = v.destination_sk
            WHERE v.venue_sk = ?
        """, [venue_sk])
        if not venue:
            return {"error": f"no venue with venue_sk={venue_sk}"}
        mentions = _rows(con, """
            SELECT m.mention_sk, s.name AS source, s.source_type, m.domain,
                   m.sentiment, m.descriptors, m.accolade, m.quote_short,
                   m.published_date, m.source_url, m.locator,
                   s.authority_weight,
                   (SELECT weight FROM source_competence sc
                     WHERE sc.source_sk = s.source_sk AND sc.domain = m.domain) AS competence
            FROM fact_mention m
            JOIN dim_source s USING (source_sk)
            WHERE m.venue_sk = ?
            ORDER BY m.published_date DESC NULLS LAST
        """, [venue_sk])
        decision = _rows(con, """
            SELECT cd.style_fit, cd.shortlisted, cd.decision, cd.rationale, cd.decided_at,
                   tp.name AS taste_profile
            FROM curation_decision cd
            JOIN dim_taste_profile tp USING (taste_sk)
            WHERE cd.venue_sk = ?
        """, [venue_sk])
    v = venue[0]
    return {
        "venue": v,
        "mentions": mentions,
        "mention_count": len(mentions),
        "distinct_sources": len({m["source"] for m in mentions}),
        "decisions": decision,
    }


def list_sources() -> dict:
    """The source canon with per-domain competence — inspect + sanity-check trust."""
    with _connect() as con:
        sources = _rows(con, """
            SELECT s.source_sk, s.name, s.source_type, s.medium, s.authority_weight,
                   s.editorial_lean, s.cadence, s.ingest_method, s.is_active,
                   (SELECT count(*) FROM fact_mention m WHERE m.source_sk = s.source_sk) AS mentions
            FROM dim_source s
            ORDER BY s.authority_weight DESC NULLS LAST, s.name
        """)
        comp = _rows(con, "SELECT source_sk, domain, weight FROM source_competence")
    by_src = {}
    for c in comp:
        by_src.setdefault(c["source_sk"], {})[c["domain"]] = c["weight"]
    for s in sources:
        s["competence"] = by_src.get(s["source_sk"], {})
    return {"sources": sources, "count": len(sources)}


def approve_venue(venue_sk: int, decision: str, rationale: Optional[str], taste: Optional[str]) -> dict:
    """Record your curation decision (approved | rejected | hold | research)."""
    valid = {"approved", "rejected", "hold", "research"}
    if decision not in valid:
        return {"error": f"decision must be one of {sorted(valid)}"}
    with _connect() as con:
        taste_row = _rows(con,
            "SELECT taste_sk FROM dim_taste_profile WHERE " +
            ("is_active" if not taste else "name = ?"),
            [] if not taste else [taste])
        if not taste_row:
            return {"error": "no matching taste profile"}
        taste_sk = taste_row[0]["taste_sk"]
        # decided_at uses the DB clock, not Python (script-clock rules don't apply to MCP runtime)
        con.execute("""
            INSERT INTO curation_decision (venue_sk, taste_sk, decision, rationale, decided_by, decided_at)
            VALUES (?, ?, ?, ?, 'editor', now())
            ON CONFLICT (venue_sk, taste_sk) DO UPDATE SET
                decision = excluded.decision,
                rationale = excluded.rationale,
                decided_by = 'editor',
                decided_at = now()
        """, [venue_sk, taste_sk, decision, rationale])
        result = _rows(con, """
            SELECT v.name, cd.decision, cd.rationale, cd.style_fit
            FROM curation_decision cd JOIN dim_venue v USING (venue_sk)
            WHERE cd.venue_sk = ? AND cd.taste_sk = ?
        """, [venue_sk, taste_sk])
    return {"recorded": result[0] if result else None}


# --------------------------------------------------------------------------
# MCP wiring
# --------------------------------------------------------------------------

server = Server("travel-curation")


@server.list_tools()
async def list_tools() -> list[Tool]:
    return [
        Tool(
            name="get_shortlist",
            description=(
                "Ranked venue candidates for a destination under a taste profile, "
                "with style_fit scores and open-question flags. Use this to review "
                "what the rules surfaced before you approve."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "destination": {"type": "string", "description": "City or region name (e.g. 'Palermo' or 'Sicily'). Omit for all."},
                    "taste": {"type": "string", "description": "Taste profile name. Omit for the active profile."},
                    "min_fit": {"type": "number", "description": "Minimum style_fit (0-100). Default 0.", "default": 0},
                },
            },
        ),
        Tool(
            name="get_venue",
            description="Full evidence dossier for one venue: attributes, every mention with source + provenance, and current decisions.",
            inputSchema={
                "type": "object",
                "properties": {"venue_sk": {"type": "integer"}},
                "required": ["venue_sk"],
            },
        ),
        Tool(
            name="list_sources",
            description="The source canon (magazines, books, blogs, critics) with authority weights and per-domain competence. Sanity-check what you trust and why.",
            inputSchema={"type": "object", "properties": {}},
        ),
        Tool(
            name="approve_venue",
            description="Record a curation decision for a venue: approved | rejected | hold | research. Your rationale also informs source-weight tuning over time.",
            inputSchema={
                "type": "object",
                "properties": {
                    "venue_sk": {"type": "integer"},
                    "decision": {"type": "string", "enum": ["approved", "rejected", "hold", "research"]},
                    "rationale": {"type": "string", "description": "Why — a short editorial note."},
                    "taste": {"type": "string", "description": "Taste profile name. Omit for the active profile."},
                },
                "required": ["venue_sk", "decision"],
            },
        ),
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[TextContent]:
    try:
        if name == "get_shortlist":
            result = get_shortlist(
                arguments.get("destination"),
                arguments.get("taste"),
                float(arguments.get("min_fit", 0)),
            )
        elif name == "get_venue":
            result = get_venue(int(arguments["venue_sk"]))
        elif name == "list_sources":
            result = list_sources()
        elif name == "approve_venue":
            result = approve_venue(
                int(arguments["venue_sk"]),
                arguments["decision"],
                arguments.get("rationale"),
                arguments.get("taste"),
            )
        else:
            result = {"error": f"unknown tool: {name}"}
    except Exception as exc:
        result = {"error": str(exc)}
    return [TextContent(type="text", text=json.dumps(result, indent=2, default=str))]


async def main():
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, server.create_initialization_options())


if __name__ == "__main__":
    asyncio.run(main())
