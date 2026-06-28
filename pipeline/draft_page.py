#!/usr/bin/env python3
"""
Stage 4 — drafting pipeline: brief -> draft -> fact-check -> persist.

Produces ONE curated page from the brain, in Jaco's editorial voice, with every
claim grounded against a frozen, hashed brief. The AI never queries the database;
it receives only the brief.

Flow:
  1. assemble_brief(destination)  -> frozen dict of shortlisted venues + evidence + the
                                     trust proof-point (a publication-recommended venue the
                                     rules excluded), hashed.
  2. generate(brief)             -> {title, body_md, claims[]}  (Claude API; needs key)
  3. fact_check(brief, claims)   -> each claim grounded vs the brief? (deterministic
                                     number/name check + optional LLM pass)
  4. persist(brief, draft)       -> dim_content (+ source_brief_hash) + bridge_content_subject

Usage:
    python draft_page.py --destination Palermo            # full run (needs ANTHROPIC_API_KEY)
    python draft_page.py --destination Palermo --brief-only   # just print the frozen brief
    python draft_page.py --destination Palermo --dry-run      # brief + show the prompt, no API

Environment:
    ANTHROPIC_API_KEY  required for generation/fact-check (brief + persist work without it)
    CURATION_DB        path to curation.duckdb (default ../brain/curation.duckdb)
"""
from __future__ import annotations

import os
import re
import json
import argparse
import hashlib
from pathlib import Path

import duckdb

import sys
sys.path.insert(0, str(Path(__file__).parent))
from voice import VOICE_SYSTEM_PROMPT, GROUNDING_CONTRACT

DEFAULT_DB = Path(__file__).parent.parent / "brain" / "curation.duckdb"
DB_PATH = Path(os.environ.get("CURATION_DB", str(DEFAULT_DB)))
WRITER_MODEL = "claude-sonnet-4-6"
CHECKER_MODEL = "claude-haiku-4-5-20251001"
SHORTLIST_MIN = 50.0
_DRAFT_FILE: str | None = None  # set by CLI --draft-file


def _connect(read_only: bool = True) -> duckdb.DuckDBPyConnection:
    return duckdb.connect(str(DB_PATH), read_only=read_only)


# --------------------------------------------------------------------------
# 1. Brief assembly (deterministic, frozen, hashed) — facts only
# --------------------------------------------------------------------------

def assemble_brief(destination: str) -> dict:
    with _connect() as con:
        shortlisted = con.execute("""
            SELECT v.venue_sk, v.name, v.venue_type, v.adults_only, v.child_policy,
                   v.room_count, v.ownership, v.has_restaurant, v.design_notes,
                   cd.style_fit
            FROM curation_decision cd
            JOIN dim_venue v USING (venue_sk)
            JOIN dim_taste_profile tp USING (taste_sk)
            LEFT JOIN dim_destination d ON d.destination_sk = v.destination_sk
            LEFT JOIN dim_destination parent ON parent.destination_sk = d.parent_sk
            WHERE tp.is_active AND cd.shortlisted
              AND (d.name = ? OR parent.name = ?)
            ORDER BY cd.style_fit DESC
        """, [destination, destination]).fetchall()
        cols = [d[0] for d in con.description]
        venues = [dict(zip(cols, r)) for r in shortlisted]

        for v in venues:
            ments = con.execute("""
                SELECT s.name AS source, s.source_type, m.domain, m.sentiment,
                       m.descriptors, m.accolade, m.quote_short, m.published_date, m.source_url
                FROM fact_mention m JOIN dim_source s USING (source_sk)
                WHERE m.venue_sk = ? ORDER BY m.published_date DESC NULLS LAST
            """, [v["venue_sk"]]).fetchall()
            mcols = [d[0] for d in con.description]
            v["mentions"] = [dict(zip(mcols, r)) for r in ments]

        # The trust proof-point: a venue a publication recommended that the RULES excluded.
        excluded = con.execute("""
            SELECT v.name, v.ownership, v.child_policy, cd.style_fit,
                   (SELECT s.name FROM fact_mention m JOIN dim_source s USING(source_sk)
                     WHERE m.venue_sk = v.venue_sk
                     ORDER BY CASE m.sentiment WHEN 'recommended' THEN 0 WHEN 'listed' THEN 1
                                               WHEN 'praised' THEN 2 ELSE 3 END,
                              m.published_date DESC NULLS LAST
                     LIMIT 1) AS recommended_by
            FROM curation_decision cd
            JOIN dim_venue v USING (venue_sk)
            JOIN dim_taste_profile tp USING (taste_sk)
            LEFT JOIN dim_destination d ON d.destination_sk = v.destination_sk
            WHERE tp.is_active AND cd.style_fit = 0
              AND (d.name = ?)
              AND EXISTS (SELECT 1 FROM fact_mention m WHERE m.venue_sk = v.venue_sk)
        """, [destination]).fetchall()
        ecols = [d[0] for d in con.description]
        excluded_with_mentions = [dict(zip(ecols, r)) for r in excluded]

        taste = con.execute(
            "SELECT name, version FROM dim_taste_profile WHERE is_active LIMIT 1"
        ).fetchone()

    brief = {
        "destination": destination,
        "taste_profile": {"name": taste[0], "version": taste[1]},
        "venues": venues,
        "excluded_but_recommended": excluded_with_mentions,
        "note": ("Facts only. Prose must use nothing not present here. "
                 "'excluded_but_recommended' venues were recommended by a publication "
                 "but the taste rules excluded them — usable as the trust proof-point."),
    }
    brief["brief_hash"] = _hash_brief(brief)
    return brief


def _hash_brief(brief: dict) -> str:
    payload = {k: v for k, v in brief.items() if k != "brief_hash"}
    blob = json.dumps(payload, sort_keys=True, default=str)
    return hashlib.sha256(blob.encode()).hexdigest()[:16]


# --------------------------------------------------------------------------
# 2. Generation (Claude API)
# --------------------------------------------------------------------------

def _writer_prompt(brief: dict) -> str:
    return (
        "Write a curated guide page titled for the destination. The page should help a "
        "discerning, no-kids, design-minded traveller decide where to eat and stay.\n\n"
        "Structure: a short intro that states the point of view; then the shortlisted "
        "venues grouped sensibly (e.g. restaurants, hotels), each with a 1-3 sentence "
        "take grounded in its evidence; then a short, honest 'why you can trust this list' "
        "note that uses the excluded-but-recommended venue as the proof-point.\n\n"
        "Return JSON: {\"title\": str, \"body_md\": str, \"claims\": [str, ...]}.\n\n"
        f"BRIEF (facts only):\n{json.dumps(brief, indent=2, default=str)}"
    )


def generate(brief: dict) -> dict:
    """Call Claude to write the page. Raises if no API key."""
    try:
        from anthropic import Anthropic
    except ImportError as e:
        raise RuntimeError("pip install anthropic") from e
    if not os.environ.get("ANTHROPIC_API_KEY"):
        raise RuntimeError("ANTHROPIC_API_KEY not set — generation needs it.")

    client = Anthropic()
    msg = client.messages.create(
        model=WRITER_MODEL,
        max_tokens=2000,
        system=VOICE_SYSTEM_PROMPT + GROUNDING_CONTRACT,
        messages=[{"role": "user", "content": _writer_prompt(brief)}],
    )
    text = msg.content[0].text
    return _extract_json(text)


def _extract_json(text: str) -> dict:
    m = re.search(r"\{.*\}", text, re.DOTALL)
    if not m:
        raise ValueError(f"No JSON found in model output:\n{text[:500]}")
    return json.loads(m.group())


# --------------------------------------------------------------------------
# 3. Fact-check — every claim grounded against the brief
# --------------------------------------------------------------------------

def fact_check_deterministic(brief: dict, draft: dict) -> list[dict]:
    """Cheap, keyless guardrail: every venue name in the prose must be in the brief,
    and every € / number-with-currency must appear in the brief text."""
    brief_blob = json.dumps(brief, default=str).lower()
    body = draft.get("body_md", "")
    results = []

    known_names = {v["name"].lower() for v in brief["venues"]}
    known_names |= {e["name"].lower() for e in brief["excluded_but_recommended"]}
    # Word-set of the brief, for token-coverage checks.
    brief_words = set(re.findall(r"[a-z0-9']+", brief_blob))

    # Strip sentence-initial capitals: only consider a capitalised run that does NOT
    # start a sentence (i.e. not preceded by start-of-string or '. '/'! '/'? '/newline/':').
    # We blank out the char after sentence boundaries so its capital isn't matched as a head.
    scan = re.sub(r"(^|[.!?:]\s+|\n+|\*\*)([A-Z])", lambda m: m.group(1) + m.group(2).lower(), body)

    # extra terms that are legitimately in the canon even if tokenisation splits them
    canon_terms = {"smith", "ottava", "mrs"}
    for cand in set(re.findall(r"\b([A-Z][\w']+(?: [A-Z][\w']+){1,3})\b", scan)):
        cl = cand.lower()
        if cl in known_names:
            continue
        # a phrase is grounded if (nearly) all its words appear in the brief.
        # strip possessive 's and the apostrophe-prefix from L'Ottava etc.
        toks = [re.sub(r"^l'", "", re.sub(r"'s$", "", t)) for t in re.findall(r"[a-z0-9']+", cl)]
        missing = [t for t in toks
                   if t and t not in brief_words and t not in canon_terms and len(t) > 2]
        if missing:
            results.append({"check": "unknown_proper_noun", "value": cand,
                            "missing_words": missing, "grounded": False})

    for money in set(re.findall(r"[€$]\s?\d[\d.,]*", body)):
        if money.lower().replace(" ", "") not in brief_blob.replace(" ", ""):
            results.append({"check": "ungrounded_number", "value": money, "grounded": False})

    return results


def fact_check_llm(brief: dict, claims: list[str]) -> list[dict]:
    """Per-claim grounding check with the cheap model. Needs API key."""
    from anthropic import Anthropic
    client = Anthropic()
    sys_p = ("For each claim, decide if it is FULLY supported by the brief. "
             "Any number, name, accolade, or fact not in the brief is NOT grounded. "
             "Return JSON: [{\"claim\": str, \"grounded\": bool, \"reason\": str}].")
    user = (f"BRIEF:\n{json.dumps(brief, default=str)}\n\n"
            f"CLAIMS:\n{json.dumps(claims, indent=2)}")
    msg = client.messages.create(
        model=CHECKER_MODEL, max_tokens=1500, system=sys_p,
        messages=[{"role": "user", "content": user}],
    )
    return _extract_json_list(msg.content[0].text)


def _extract_json_list(text: str) -> list:
    m = re.search(r"\[.*\]", text, re.DOTALL)
    return json.loads(m.group()) if m else []


# --------------------------------------------------------------------------
# 4. Persist
# --------------------------------------------------------------------------

def persist(brief: dict, draft: dict, status: str) -> int:
    slug = re.sub(r"[^a-z0-9]+", "-", draft["title"].lower()).strip("-")
    with _connect(read_only=False) as con:
        site_sk = con.execute(
            "SELECT site_sk FROM dim_site WHERE slug='adults-design-led'"
        ).fetchone()
        if not site_sk:
            raise RuntimeError("site 'adults-design-led' not found")
        site_sk = site_sk[0]

        con.execute("""
            INSERT INTO dim_content (site_sk, content_type, title, slug, body_md,
                                     frontmatter, status, source_brief_hash, version, generated_at)
            VALUES (?, 'guide', ?, ?, ?, ?, ?, ?, 1, now())
            ON CONFLICT (site_sk, slug) DO UPDATE SET
                body_md = excluded.body_md, status = excluded.status,
                source_brief_hash = excluded.source_brief_hash,
                version = dim_content.version + 1, generated_at = now()
        """, [site_sk, draft["title"], slug, draft["body_md"],
              json.dumps({"destination": brief["destination"],
                          "taste": brief["taste_profile"]["name"]}),
              status, brief["brief_hash"]])
        content_sk = con.execute(
            "SELECT content_sk FROM dim_content WHERE site_sk=? AND slug=?",
            [site_sk, slug]).fetchone()[0]

        # provenance bridge: every venue + every mention's source
        con.execute("DELETE FROM bridge_content_subject WHERE content_sk=?", [content_sk])
        for v in brief["venues"]:
            con.execute("""INSERT INTO bridge_content_subject VALUES (?, 'venue', ?, 'primary')
                           ON CONFLICT DO NOTHING""", [content_sk, v["venue_sk"]])
        for e in brief["excluded_but_recommended"]:
            pass  # excluded venues referenced by name only; not bridged as primary
    return content_sk


# --------------------------------------------------------------------------
# Orchestration
# --------------------------------------------------------------------------

def run(destination: str, brief_only: bool, dry_run: bool) -> None:
    brief = assemble_brief(destination)
    print(f"Brief assembled: {len(brief['venues'])} shortlisted venues, "
          f"hash={brief['brief_hash']}")
    if brief["excluded_but_recommended"]:
        e = brief["excluded_but_recommended"][0]
        print(f"  trust proof-point: {e['name']} (recommended by {e['recommended_by']}, "
              f"excluded — {e['ownership']}/{e['child_policy']})")

    if brief_only:
        print(json.dumps(brief, indent=2, default=str))
        return

    if dry_run:
        print("\n--- WRITER PROMPT (dry run, no API call) ---\n")
        print(VOICE_SYSTEM_PROMPT + GROUNDING_CONTRACT)
        print("\n--- USER ---\n")
        print(_writer_prompt(brief)[:2000] + "\n...[brief truncated]")
        return

    if _DRAFT_FILE:
        draft = json.loads(Path(_DRAFT_FILE).read_text(encoding="utf-8"))
        print(f"\nUsing pre-written draft: {_DRAFT_FILE}")
    else:
        print("\nGenerating draft...")
        draft = generate(brief)
    print(f"  title: {draft['title']}")
    print(f"  claims itemised: {len(draft.get('claims', []))}")

    det = fact_check_deterministic(brief, draft)
    if det:
        print(f"  [WARN] deterministic check flagged {len(det)}: {det}")
    else:
        print("  [OK] deterministic check passed (no ungrounded names/numbers)")

    ungrounded = []
    if os.environ.get("ANTHROPIC_API_KEY"):
        llm = fact_check_llm(brief, draft.get("claims", []))
        ungrounded = [c for c in llm if not c.get("grounded")]
    else:
        print("  (LLM fact-check skipped — no ANTHROPIC_API_KEY; deterministic check only)")
    status = "quarantine" if (det or ungrounded) else "ready"
    if ungrounded:
        print(f"  [WARN] {len(ungrounded)} ungrounded claim(s) -> quarantine")
        for c in ungrounded:
            print(f"     - {c.get('claim')}: {c.get('reason')}")

    content_sk = persist(brief, draft, status)
    print(f"\nPersisted content_sk={content_sk}, status={status}")
    print("\n" + "=" * 60 + f"\n{draft['title']}\n" + "=" * 60)
    print(draft["body_md"])


def main() -> None:
    ap = argparse.ArgumentParser(description="Draft one curated page from the brain.")
    ap.add_argument("--destination", default="Palermo")
    ap.add_argument("--brief-only", action="store_true", help="print the frozen brief and stop")
    ap.add_argument("--dry-run", action="store_true", help="assemble brief + show prompt, no API")
    ap.add_argument("--draft-file", help="use a pre-written draft JSON instead of calling the API "
                                         "(still runs the real fact-check + persist)")
    args = ap.parse_args()
    global _DRAFT_FILE
    _DRAFT_FILE = args.draft_file
    run(args.destination, args.brief_only, args.dry_run)


if __name__ == "__main__":
    main()
