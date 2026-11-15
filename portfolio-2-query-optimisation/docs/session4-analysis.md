# Query processing and optimisation: analysis against Study Session 4

> Historical analysis: these measurements and diagrams come from the earlier integer-ID schema. The current SQL uses UUID-as-text IDs and `quantity_in_store`. Rerun the updated scripts before using these timings as evidence for the current design. Buffer totals from the earlier experiment harness may include double-counted child-node buffers; the updated harness reads the root counter.

All numbers come from runs on the Konga database (PostgreSQL 16, 1.5 million rows in total, 2 CPU cores, shared sandbox). Each timing is the median of 3 to 5 timed runs after one warm-up, from `EXPLAIN (ANALYZE, BUFFERS)`. Timings on this machine vary by roughly 20 to 30 per cent between runs, so only large differences are treated as findings. Raw tables are in `evidence/experiments/`, and every SQL statement the harness ran is logged in `evidence/experiments/executed-sql.sql`.

## 1. How a query is processed (4.1.1)

PostgreSQL follows the same stages as the study material: it parses the SQL text, rewrites it, plans it (choosing the cheapest plan), then executes the plan.

| Study Session 4 stage | What PostgreSQL does | Evidence |
|---|---|---|
| Scanning, parsing, validating | Parser checks syntax; analyser checks tables, columns and types against the catalogue | A misspelt column gives an error before any plan exists |
| Query tree / query graph (internal representation) | Query tree; views and rules are rewritten into it | `docs/diagrams/q4_trees.png`, `q4_query_graph.png` |
| Optimisation: choose an execution strategy | Planner enumerates paths and picks the lowest estimated cost | "Planning Time" and the `cost=` figures in every plan |
| Code generation and execution | Executor runs the plan tree, pulling rows upward | "Execution Time", `actual time`, `rows`, `Buffers` |

### Relational algebra for Q4 (low-stock products in a category)

```
π p.product_id, p.name, v.sku, i.quantity_on_hand (
  σ p.category_id=25 ∧ p.status='live' ∧ i.quantity_on_hand<10 (
    (products p ⋈ product_variants v) ⋈ inventory i))
```

Rewriting the selections down next to their tables gives the equivalent, cheaper expression:

```
π ... ( (σ category_id=25 ∧ status='live'(products) ⋈ product_variants) ⋈ σ quantity_on_hand<10(inventory) )
```

The picture is in `docs/diagrams/q4_trees.png` (initial tree on the left, optimised tree on the right). The query graph, with relations as nodes and join conditions as edges, is `docs/diagrams/q4_query_graph.png`. PostgreSQL did exactly this rewrite on its own. Its plan (`evidence/experiments/q4_plan_for_tree.txt`) filters `products` to 456 rows and `inventory` to 2,289 rows before joining, then joins with two hash joins and sorts only 54 result rows (7.1 ms).

## 2. Optimisation techniques (4.1.2)

### 2.1 Heuristic (rule-based) optimisation: push selections down
The Q4 plan above is the rule "apply selections and projections early" in action. The study material calls this heuristic optimisation (RBO) because it needs no statistics, only rules.

### 2.2 Rewriting the query: nested queries, joins and sargable predicates (experiment E2)

| Experiment | Formulation | ms | Buffers hit | Finding |
|---|---|---|---|---|
| E2a | `IN (subquery)` | 5.4 | n/a | All three forms were planned as the same Hash Join, so the optimiser flattens nested queries and the form made no real difference (4.7 to 6.5 ms) |
| E2a | `EXISTS (correlated)` | 4.7 | n/a | |
| E2a | `JOIN` + `DISTINCT` | 6.5 | n/a | |
| E2b | Correlated subquery per row | 88.9 | 269,516 | The SubPlan runs once per outer row |
| E2b | Join + `GROUP BY` | 113.9 | 17,882 | Reads 15 times fewer pages but was **not faster** in time (see note) |
| E2c | `date_trunc('day', placed_at) = DATE` | 32.8 | 1,660 | The function on the column stops a range search |
| E2c | `placed_at >= DATE AND placed_at < DATE+1` | 0.07 | 10 | About 450 times faster, 166 times fewer pages |

Note on E2b: I expected the join to win, and it did not in milliseconds. The rewrite clearly does far less I/O, but on this machine all data was already in memory, so the saving in page reads did not show up as time. On a cold cache or a larger table, where pages come from disk, I would expect the buffer saving to matter. I have not tested that, so it is a hypothesis.

### 2.3 Statistics and the cost-based optimiser (experiment E1)
The study material says a cost-based optimiser (CBO) chooses a plan from estimated costs, and that the estimates depend on statistics in the catalogue.

| Step | Estimated rows | Actual rows | Plan | ms |
|---|---|---|---|---|
| Fresh statistics | 7,650 | 7,611 | Bitmap/Index scan | 3.1 |
| Stale statistics (data changed) | 12,975 | 107,282 | Same index plan | 21.0 |
| After `ANALYZE` | 107,475 | 107,282 | Seq Scan | 24.7 |

With stale statistics the optimiser underestimated the matching rows by 8 times. After `ANALYZE` it correctly switched to a sequential scan. That scan was not faster than the stale index plan in this case (25 ms against 21 ms), which is a useful honest result: the optimiser's estimate became accurate, but accuracy does not guarantee the fastest plan.

### 2.4 Join algorithms (experiment E3)
Same query and data, with `enable_hashjoin`, `enable_mergejoin` and `enable_nestloop` switched to force each algorithm.

| Selectivity | Optimiser's choice | Forced alternatives (ms) |
|---|---|---|
| Selective query | Hash Join, 48.4 ms | Merge 67.6, **Nested Loop 15.1** |
| Broad query | Merge Join, 258.8 ms | Hash 345.9, Nested Loop 328.9 (about 3.0 million buffers) |

For the broad query the optimiser's choice was also the fastest, as the theory predicts. For the selective query it was not: the optimiser estimated nested loop at cost 14,039 against 10,574 for hash, yet nested loop ran about 3 times faster. The cost model and reality disagreed. One possible cause is that `random_page_cost` (default 4) overstates the price of random reads when everything is cached. I did not test that, so it stays a hypothesis. The lesson for the report is that the CBO is an estimate, and `EXPLAIN ANALYZE` is how to check it.

### 2.5 Pre-computation: materialised views (experiment E5)

| Query | Base tables (ms) | Materialised view (ms) |
|---|---|---|
| Q8 top customers by lifetime value | 107.6 | 0.014 |
| Seller by month revenue | 6.0 | 0.013 |

Cost of the technique: refreshing the Q8 view took about 114 ms, and the data is only as fresh as the last refresh. This is the right tool for the queries where indexes did not help (Q2, Q8, see section 3).

### 2.6 Parallelism and memory (experiment E6)

| `max_parallel_workers_per_gather` | Parallel plan? | ms |
|---|---|---|
| 0 | no | 143.8 |
| 1 | yes | 90.2 |
| 2 | yes | 101.3 |
| 4 | yes | 101.7 |

One worker gave a speed-up of about 1.6 times. More workers did not help, which is expected because the machine has 2 cores (the leader process also works). My first attempt at this experiment used a query whose best plan was an index scan, which cannot be parallelised cheaply, and the optimiser never chose a parallel plan. I replaced it with a scan-and-aggregate query and recorded the change here instead of hiding it.

Sorting is sensitive to `work_mem`: a 64 kB limit forced an external merge sort spilling 3,992 kB to disk (210.3 ms), 4 MB still spilled (115.7 ms), and 64 MB sorted in memory (103.6 ms). The in-memory gain over 4 MB is small (about 10%) and within the run-to-run noise, so the clear finding is only that very small `work_mem` is slow.

## 3. Cost factors and access paths (4.1.3)

### 3.1 Index availability and type (experiment E4)
Query: latest 20 successful card payments. 150,000 rows.

| Access structure | Path | Buffers | ms |
|---|---|---|---|
| None | Parallel Seq Scan + Sort | 6,827 | 13.8 |
| Single-column B-tree (`method`) | Bitmap Heap Scan + Sort | 5,046 | 9.5 |
| Hash index (`method`) | Bitmap Heap Scan + Sort | 5,286 | 10.6 |
| Multi-column B-tree (`method, status, created_at DESC`) | Index Scan, no sort | 46 | 0.024 |
| Covering (same keys + `INCLUDE`) | Index Only Scan, no sort | 8 | 0.015 |

The single-column index barely helped because about 28,000 rows match the filter and they still have to be sorted. The multi-column index matches the filter and the sort order together, and the covering index also avoids visiting the table. Cost: the multi-column index is 7.8 MB and the covering one 12 MB, against 1 MB for the single-column one.

### 3.2 Which indexes helped and which did not (Q1 to Q8 with the 10 indexes in `sql/03_indexes.sql`)
Full table: `evidence/comparison.md` and `evidence/before-after-chart.png`.

| Query | Before (ms) | After (ms) | Speed-up | Reason |
|---|---|---|---|---|
| Q1 customer order history | 7.61 | 0.12 | 65x | Composite index matches filter and order |
| Q3 seller monthly revenue | 54.42 | 7.94 | 6.9x | Joins now probe indexes |
| Q5 product name search | 8.64 | 0.27 | 32.6x | Trigram GIN index for `ILIKE '%...%'` |
| Q6 abandoned pending orders | 13.56 | 0.25 | 53.6x | Partial index on pending orders only |
| Q7 recent reviews | 4.87 | 0.13 | 38.0x | Composite index returns rows pre-sorted |
| Q2 top sellers (90 days) | 172.61 | 197.54 | 0.9x | Reads a large share of the table, so a scan is right |
| Q4 low stock in category | 10.39 | 12.02 | 0.9x | Already cheap; change is within noise |
| Q8 lifetime value | 132.30 | 125.86 | 1.1x | Aggregates the whole table; fixed by the materialised view |

Those timings are from the original run before the experiments harness existed. Q1, Q5, Q6, Q7 are re-measured under load in section 4.

### 3.3 File organisation (experiment E7)
Copy of `order_items` with 450,000 rows. Study Session 4 lists heap, sorted/indexed and hashed file organisations.

| Organisation | Index size | Exact match (ms / buffers) | Range (ms / buffers) |
|---|---|---|---|
| Heap, no index | none | 28.3 / 7,552 | 30.7 / 15,104 |
| Heap + B-tree | 6.5 MB | 0.009 / 9 | 2.78 / 5,249 |
| Heap + hash index | 15 MB | 0.015 / 5 | 27.9 / 15,104 (falls back to a scan) |
| Clustered on the key + B-tree | 6.5 MB | 0.007 / 4 | 0.67 / 100 |
| Sorted table + BRIN | 24 kB | 0.87 / 132 | 1.30 / 262 |

The hash index wins an exact match but cannot answer a range at all, so the optimiser scans the whole table, and it is the largest index. Clustering the table on the key makes range queries about 4 times faster than the unordered heap with a B-tree (2.78 ms to 0.67 ms) and reads 50 times fewer pages. BRIN is 270 times smaller than the B-tree and still answers ranges quickly, but only because the table is physically sorted. Note that `CLUSTER` is a one-off reorganisation: new rows are not kept in order.

### 3.4 Estimate accuracy across all eight queries (experiment E9)
Worst scan, join or aggregate estimate error: Q1 1.1x, Q2 2.4x, Q3 36x (aggregate), Q4 1.1x, Q5 2.0x, Q6 1.0x, Q7 1.0x, Q8 1.0x. Only Q3 is badly off, at a grouping step, which matches the textbook point that the number of groups is the hardest thing to estimate. Plans were still good because the join order and access paths were not affected.

## 4. Evaluating performance under load (4.2)

Study Session 4 asks for evaluation methods and metrics (response time, throughput) rather than a single query timing. Experiment E8 runs a mixed workload with `pgbench`: 4 clients for 20 seconds, 50 per cent Q1, 30 per cent Q7, 10 per cent Q5, 10 per cent Q6 (`sql/experiments/pgbench/workload.sql`).

| | Throughput (transactions/s) | Average latency (ms) |
|---|---|---|
| Without the four secondary indexes | 392 | 10.2 |
| With the four indexes | 1,909 | 2.1 |

That is about 4.9 times the throughput. After the run, `pg_stat_statements` showed where the remaining time went (`evidence/experiments/pgbench/e8_pg_stat_statements.txt`): the name search still takes 17.5 ms per call on average and about 33 of the 34 seconds of total execution time, even with the trigram index in place. I checked its plan: for `'%shirt 1234%'` on a 20,000-row table, the planner chose a sequential scan (cost 586) over the GIN index, because on a small table a scan is estimated cheaper. So the single-query win for Q5 in section 3.2 does not carry over to this table size, and I would not call it a general result. A larger product catalogue would change the choice.

Cost of the indexes: each index adds work to every INSERT and UPDATE and takes space (see `evidence/new-index-sizes.txt`). This workload is read-only, so it does not measure that cost. A write-heavy workload would.

## 5. Centralised versus distributed query cost
In a centralised database, cost is mostly disk I/O and CPU. In a distributed one, Study Session 4 adds communication cost. Portfolio 5 measures this with `postgres_fdw`, where a remote table scan transfers rows across the network layer and the optimiser can push filters down to the remote side.

## 6. Limitations
- Single machine, 2 cores, shared sandbox: absolute timings are not representative of a production server and vary run to run.
- Synthetic data with simple distributions, so estimates are easier than on real skewed marketplace data.
- Everything was served from memory after warm-up, so disk-bound behaviour was not measured.
- No write-heavy workload was run, so the maintenance cost of indexes is described, not measured.
- PostgreSQL has no optimiser hints; I steered plans only with `enable_*` settings and index changes, which is a blunter tool than a hint.
