# Portfolio 2: Query Processing and Optimisation

This portfolio builds on the marketplace database designed in [Portfolio 1](../portfolio-1-database-design/docs/design-report.md). The tables and relationships stay the same; the focus shifts to how PostgreSQL runs queries and how indexes affect the work involved. All data is synthetic.

## Evidence checklist

The before/after query evidence and Study Session 4 experiment reports now use the current UUID-based schema. The older standalone index-size and pg_stat_statements files have not been refreshed by this workflow.
- [x] SQL queries: [`sql/queries/`](sql/queries/) (8 queries, Q1-Q8)
- [x] Query results: `evidence/before/q*.result.txt` (first rows of each result)
- [x] Execution plans: `evidence/before/` and `evidence/after/` (`EXPLAIN (ANALYZE, BUFFERS)`)
- [x] Indexing: [`sql/03_indexes.sql`](sql/03_indexes.sql) (10 indexes: composite, partial, trigram GIN)
- [x] Experiments E1-E9 (statistics, rewriting, join algorithms, index types, materialised views, parallelism and memory, file organisation, estimate accuracy): [`sql/experiments/`](sql/experiments/) and [`evidence/experiments/`](evidence/experiments/)
- [x] Load test (pgbench) and `pg_stat_statements`: [`sql/experiments/pgbench/`](sql/experiments/pgbench/), [`evidence/experiments/pgbench/`](evidence/experiments/pgbench/)
- [x] Query tree, query graph, relational algebra: [`docs/session4-analysis.md`](docs/session4-analysis.md), [`docs/diagrams/`](docs/diagrams/)
- [x] Analysis organised by Study Session 4 (4.1.1 processing, 4.1.2 techniques, 4.1.3 cost factors, 4.2 evaluation): [`docs/session4-analysis.md`](docs/session4-analysis.md)
- [x] Earlier index-focused analysis: [`docs/performance-analysis.md`](docs/performance-analysis.md), [`evidence/comparison.md`](evidence/comparison.md)

Current compatibility checks are recorded in [current-schema-validation.md](evidence/current-schema-validation.md).

## Current query results

Collected on 15 November 2026. Times are medians of three runs after one warm-up.

| Query | Before (ms) | After (ms) | Change |
|---|---|---|---|
| Q1: Customer order history | 12.118 | 0.036 | 336.6× faster |
| Q2: Top-selling product variations over 90 days | 550.763 | 591.408 | 7.4% slower |
| Q3: Seller monthly revenue | 50.044 | 22.520 | 2.2× faster |
| Q4: Low stock in a category | 25.655 | 8.885 | 2.9× faster |
| Q5: Product name search | 9.747 | 0.100 | 97.5× faster |
| Q6: Older pending orders | 11.900 | 0.035 | 340.0× faster |
| Q7: Recent product reviews | 4.132 | 0.068 | 60.8× faster |
| Q8: Top customers by delivered-order value | 101.866 | 106.558 | 4.6% slower |

All eight saved result samples match. Six queries improved; Q2 and Q8 showed small increases. See the [current analysis](docs/performance-analysis.md).

### Current Study Session 4 experiments

The experiment suite and 20-second-per-configuration load test completed on 15 November 2026. The [Study Session 4 analysis](docs/session4-analysis.md) explains the results and their limits.

| Technique | Observed result |
|---|---|
| Statistics (E1) | Refreshing statistics after the distribution changed reduced the median from 19.570 to 13.050 ms |
| Aggregation rewrite (E2b) | Correlated subquery: 424.424 ms; join and GROUP BY: 145.036 ms |
| Date predicate rewrite (E2c) | Function on column: 18.985 ms; range predicate: 0.052 ms |
| Composite / covering indexes (E4) | 11.808 ms without an index; 0.015 / 0.014 ms with these indexes |
| Materialised view (E5) | Q8: 83.765 to 0.007 ms; customer-value view refresh: about 98 ms |
| Parallelism (E6) | 140.861 ms with workers disabled; 51.378 ms at a configured limit of four |
| Clustering with B-tree (E7) | Range query: 4.075 to 2.746 ms; shared-buffer hits: 3,513 to 105 |
| Mixed read load (E8) | 430.959 to 40,193.911 transactions/s; no failed transactions |

## How the investigation is organised

1. Generated roughly 2 million rows of synthetic data (`sql/01_seed_large.sql`, stable UUIDs and seeded random values; runtime depends on the machine).
2. Wrote 8 queries for operations in the simulated marketplace (customer history, best sellers, seller reports, stock alerts, catalogue search, order follow-up, reviews, analytics).
3. Measured each with `EXPLAIN (ANALYZE, BUFFERS)` on the schema with only primary-key and unique indexes (BEFORE).
4. Chose indexes from the plans (sequential scans on large tables with selective filters), created them, and measured again (AFTER).
5. Ran nine controlled experiments (E1-E9) for the techniques in Study Session 4, one variable at a time, with all SQL logged.
6. Compared the plans and timings, including cases where indexes provided little benefit.

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

The seed creates stable UUID-shaped text IDs. The example queries select customer 1234, seller 42, category 25 and product 777 within that dataset. These are fixture IDs, not IDs from Portfolio 1’s small sample. The full IDs are:

| Fixture | UUID stored as `VARCHAR(36)` |
|---|---|
| Customer 1234 (Q1) | `00000001-0000-4000-8000-000000001234` |
| Seller 42 (Q3) | `00000003-0000-4000-8000-000000000042` |
| Category 25 (Q4) | `00000004-0000-4000-8000-000000000025` |
| Product 777 (Q7) | `00000006-0000-4000-8000-000000000777` |

The experiment bounds and pgbench workload use the same UUID format. Keep these large-dataset IDs separate from Portfolio 3’s small-sample UUIDs.

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

The experiments use synthetic data on one machine, with one warm-up followed by three measured runs for the main query comparison. The results help explain query behaviour, but they do not predict production performance. The [performance analysis](docs/performance-analysis.md#limitations) discusses these limits.
