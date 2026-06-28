# Travel Curation MCP Server

Conversational curation surface for the [brain](../brain/) — curate by talking to
Claude instead of writing SQL. This is **Stage 2** of the [vertical slice plan](../PLAN.md):
the interface for "approve shortlists, trust the rest."

## Tools

| Tool | Reads/Writes | What it does |
|------|--------------|--------------|
| `get_shortlist` | read | Ranked candidates for a destination under a taste profile, with `style_fit` + open-question flags ("adults policy unconfirmed", "no evidence on file") |
| `get_venue` | read | Full evidence dossier: attributes + every mention with source, descriptors, accolade, provenance (URL or page locator) |
| `list_sources` | read | The source canon with authority weights + per-domain competence — sanity-check what you trust |
| `approve_venue` | write | Record a decision (`approved`/`rejected`/`hold`/`research`) + rationale into `curation_decision` |

The server **only reads curation data and records decisions** — it never writes
prose. Drafting is a separate pipeline ([PLAN.md](../PLAN.md) stage 4).

Key property (verified): `approve_venue` decisions survive a re-run of
`style_fit.sql` — the scorer's `ON CONFLICT` only updates the scored columns, never
your human `decision`/`rationale`. So you can re-score as evidence accrues without
losing approvals.

## Run

```bash
cd travel-curation/brain && python build_db.py --reset   # ensure the DB exists
cd ../mcp-server
pip install -r requirements.txt
python server.py
```

## Configure in Claude Code (`~/.claude/mcp.json`)

```json
{
  "mcpServers": {
    "travel-curation": {
      "command": "python",
      "args": ["C:/Repos/ai/travel-curation/mcp-server/server.py"],
      "env": { "CURATION_DB": "C:/Repos/ai/travel-curation/brain/curation.duckdb" }
    }
  }
}
```

## Example conversation

> **You:** Show me the Palermo shortlist.
> **Claude** (`get_shortlist`): Villa Igiea (100, shortlisted), Gagini (46 — adults
> policy unconfirmed), Grand Resort Family Bay (0 — excluded: family + chain).
>
> **You:** Why is Villa Igiea a 100?
> **Claude** (`get_venue 1`): Two independent in-domain mentions — Mr & Mrs Smith
> (hospitality: design-led, adults-preferred) and Cereal Guides (design: considered,
> intimate) — plus adults-preferred policy, small-group ownership, has a restaurant.
>
> **You:** Approve it — restrained, exactly on profile.
> **Claude** (`approve_venue 1 approved "..."`): Recorded.
