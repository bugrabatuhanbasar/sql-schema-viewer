# Example schemas

Test fixtures used to exercise Mac SQL Schema Viewer against schemas of
different sizes, dialects, and shapes. All files are safe to open with
`File → Open…` in the app, or via the CLI:

```bash
schema-viewer inspect Examples/03-large-erp-crm.postgres.sql
schema-viewer render  Examples/03-large-erp-crm.postgres.sql -o /tmp/large.svg
```

## Fixtures at a glance

| # | File | Tier | Tables | Dialect | Domain |
|---|------|------|-------:|---------|--------|
| 01 | [`01-small-blog-forum.postgres.sql`](01-small-blog-forum.postgres.sql) | Small  | ~18  | PostgreSQL | Blog + forum sharing a user table |
| 02 | [`02-medium-ecommerce.postgres.sql`](02-medium-ecommerce.postgres.sql) | Medium | ~42  | PostgreSQL | Full e-commerce: catalog, orders, payments, promos, reviews |
| 03 | [`03-large-erp-crm.postgres.sql`](03-large-erp-crm.postgres.sql)       | Large  | ~120 | PostgreSQL | ERP + CRM (generated, deterministic seed) |
| 04 | [`04-xlarge-hospital-erp.postgres.sql`](04-xlarge-hospital-erp.postgres.sql) | X-Large | ~300 | PostgreSQL | Hospital + ERP (generated, deterministic seed) |
| 05 | [`05-social.mysql.sql`](05-social.mysql.sql)                           | Medium | ~28  | MySQL 8    | Social network: backticks / `ENGINE=` / `AUTO_INCREMENT` / `ALTER TABLE` |
| 06 | [`06-workspace.dbml`](06-workspace.dbml)                               | Small  | ~15  | DBML       | Team-collab workspace: `Ref: > glyph`, `[pk, unique, note: '...']` |

The V1 acceptance criterion is "usable performance for at least 200
tables". Fixture 04 (300 tables, ~350 indexes, ~600 FKs) is a
stress-fixture for that target — on Apple Silicon the CLI's
`inspect`/`render` roundtrip completes in well under a second.

## Regenerating the synthetic fixtures

Fixtures **03** and **04** are produced by a deterministic Swift script
so the shape can be adjusted without hand-editing thousands of lines:

```bash
swift Examples/tools/generate_synthetic.swift 120 2 Examples/03-large-erp-crm.postgres.sql
swift Examples/tools/generate_synthetic.swift 300 3 Examples/04-xlarge-hospital-erp.postgres.sql
```

Arguments are `<table count> <max FK fan-out per table> <output path>`.
The generator uses a seeded LCG, so the same arguments always produce
the same file (safe to commit).

## Why these six?

- **01 · Small blog+forum** — the "first-time user" schema. Small enough
  to fit on one screen at the default layout, but with two loosely
  connected domains and a self-referencing `post_comments.parent_id` so
  the diagram shows something interesting.
- **02 · Medium e-commerce** — the "real product" schema. Every relationship
  pattern shows up here: composite PKs, junction tables, self-referencing
  categories, optional FKs, polymorphic references (audit_events).
- **03 · Large ERP+CRM (~120)** — designed to stress vertex ordering. The
  detour routing for long-span FKs really shows up on this one.
- **04 · X-large hospital+ERP (~300)** — the V1 performance target and
  then some. Confirms parser + layout + renderer stay smooth well past
  the 200-table mark.
- **05 · MySQL social** — same "medium" size as 02, but written entirely
  in the MySQL dialect (backticks, `AUTO_INCREMENT`, `ENGINE=`, `ALTER
  TABLE ADD CONSTRAINT`) so the alternative parser gets exercised too.
- **06 · DBML workspace** — small, but proves the DBML in/out path from
  end to end: attribute lists, inline `ref:` glyphs, `Note:` blocks.
