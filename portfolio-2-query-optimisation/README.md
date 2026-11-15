# Portfolio 2: Query Processing and Optimisation

**Case study:** Konga, a simulated multi-seller e-commerce marketplace (see the root README). All data is synthetic.

## Evidence checklist

The checked-in timing files, charts and analysis describe the earlier integer-ID schema. The runnable scripts now match Portfolio 1’s UUID-as-text IDs and current columns. Those historical timings are not measurements of the updated scripts; rerun the workflow below to obtain current results.
- [x] SQL queries: [`sql/queries/`](sql/queries/) (8 queries, Q1-Q8)
- [x] Query results: `evidence/before/q*.result.txt` (first rows of each result)
- [x] Execution plans: `evidence/before/` and `evidence/after/` (`EXPLAIN (ANALYZE, BUFFERS)`)
- [x] Indexing: [`sql/03_indexes.sql`](sql/03_indexes.sql) (10 indexes: composite, partial, trigram GIN)
- [x] Experiments E1-E9 (statistics, rewriting, join algorithms, index types, materialised views, parallelism and memory, file organisation, estimate accuracy): [`sql/experiments/`](sql/experiments/) and [`evidence/experiments/`](evidence/experiments/)
- [x] Load test (pgbench) and `pg_stat_statements`: [`sql/experiments/pgbench/`](sql/experiments/pgbench/), [`evidence/experiments/pgbench/`](evidence/experiments/pgbench/)
- [x] Query tree, query graph, relational algebra: [`docs/session4-analysis.md`](docs/session4-analysis.md), [`docs/diagrams/`](docs/diagrams/)
- [x] Analysis organised by Study Session 4 (4.1.1 processing, 4.1.2 techniques, 4.1.3 cost factors, 4.2 evaluation): [`docs/session4-analysis.md`](docs/session4-analysis.md)
- [x] Earlier index-focused analysis: [`docs/performance-analysis.md`](docs/performance-analysis.md), [`evidence/comparison.md`](evidence/comparison.md), [`evidence/before-after-chart.png`](evidence/before-after-chart.png)

Current compatibility checks are recorded in [current-schema-validation.md](evidence/current-schema-validation.md).

## Historical results at a glance
| Query | Before (ms) | After (ms) | Change |
|---|---|---|---|
| Q1 customer order history | 7.61 | 0.12 | 65x faster |
| Q2 top-selling product variations, last 90 days | 172.61 | 197.54 | no real change |
| Q3 seller monthly revenue | 54.42 | 7.94 | 6.9x faster |
| Q4 low stock in category | 10.39 | 12.02 | no real change |
| Q5 product name search | 8.64 | 0.27 | 32.6x faster |
| Q6 abandoned pending orders | 13.56 | 0.25 | 53.6x faster |
| Q7 product reviews | 4.87 | 0.13 | 38x faster |
| Q8 top customers by spend | 132.30 | 125.86 | no real change |

### Study Session 4 experiments in one table
| Technique | Result on Konga data |
|---|---|
| Sargable predicate (E2c) | 32.8 ms to 0.07 ms by removing a function from the column |
| Multi-column / covering index (E4) | 13.8 ms to 0.024 / 0.015 ms, no sort step |
| Materialised view (E5) | Q8 108 ms to 0.014 ms (cost: stale data, 114 ms refresh) |
| Clustered table + B-tree (E7) | Range read 2.78 ms to 0.67 ms, 50x fewer pages |
| Parallel scan (E6) | 144 ms to 90 ms with 1 worker; no gain beyond that on 2 cores |
| Indexes under load, pgbench (E8) | 392 to 1,909 transactions/s |
| Did **not** match the textbook | Join rewrite E2b (fewer pages, not faster); optimiser's join choice E3 (nested loop 3x faster than its pick); ANALYZE flipped to a scan that was not faster (E1) |

Five queries improved a lot. Q2, Q4 and Q8 did not, because they read a large share of the data or are already fast; the analysis explains why using the plans.

## What I did
1. Generated roughly 2 million rows of synthetic data (`sql/01_seed_large.sql`, stable UUIDs and seeded random values; runtime depends on the machine).
2. Wrote 8 queries that reflect real Konga operations (customer history, best sellers, seller reports, stock alerts, catalogue search, order follow-up, reviews, analytics).
3. Measured each with `EXPLAIN (ANALYZE, BUFFERS)` on the schema with only primary-key and unique indexes (BEFORE).
4. Chose indexes from the plans (sequential scans on large tables with selective filters), created them, and measured again (AFTER).
5. Ran nine controlled experiments (E1-E9) for the techniques in Study Session 4, one variable at a time, with all SQL logged.
6. Compared plans and timings and explained both the wins and the cases where indexing did not help.

## How to run

Run these commands from `portfolio-2-query-optimisation`. Use a dedicated database: the schema script replaces the `konga` schema, and the seed script clears its tables. Keep Portfolio 1’s `konga_p1` database separate.

```bash
export PGDATABASE=konga_p2
export PGHOST=/tmp
export PGPORT=5432
# Set PGUSER if your database user differs from your macOS account.
createdb "$PGDATABASE"
psql -X -v ON_ERROR_STOP=1 -f ../portfolio-1-database-design/sql/01_schema.sql
psql -X -v ON_ERROR_STOP=1 -f sql/01_seed_large.sql
bash sql/run_plans.sh before
psql -X -v ON_ERROR_STOP=1 -f sql/03_indexes.sql
bash sql/run_plans.sh after
```

For a new baseline on an existing test database, rerun the schema and seed scripts first. Reloading data alone leaves secondary indexes in place. `run_plans.sh` accepts only `before` or `after` and reports the median of three runs after one warm-up. Set `PLAN_OUT_DIR` to save a run outside the standard evidence folders.

The seed creates stable UUID-shaped text IDs. The example queries select customer 1234, seller 42, category 25 and product 777 within that dataset. These are fixture IDs, not IDs from Portfolio 1’s small sample.

Install the Node.js dependencies with `npm install` at the repository root, then run the experiments from this portfolio directory:

```bash
node sql/experiments/run_experiments.mjs
bash sql/experiments/pgbench/run_e8.sh
```

The experiment harness uses `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE` and `PGPASSWORD`; `KONGA_PG_*` variables override them. Its default database is `konga_p2` on local port 5432. Set `EXPERIMENT_OUT_DIR` for separate experimental output. E1–E7 and E9 recreate the scratch schema `exp`; E8 temporarily removes and restores four secondary indexes. Run these only in the dedicated portfolio database. `pgbench` must be on your PATH.

Q2 measures units ordered, excluding cancelled orders. Q3 reports delivered-order item value before order-level discounts. Q8 totals delivered-order value rather than net cash after refunds. These definitions keep the scope of each report explicit.

## Design choices and lessons learned
- Indexes were created only for queries I measured, not for every foreign key.
- Partial and composite indexes were used where they match the query shape; a trigram GIN index handles `ILIKE '%...%'`.
- The earlier results suggest that selective lookups benefit more from indexes than broad aggregations. This needs to be measured again on the current schema before drawing the same conclusion.

## Limitations
Synthetic evenly-distributed data, small single-node setup, median of 3 runs. See the end of `docs/performance-analysis.md`.
