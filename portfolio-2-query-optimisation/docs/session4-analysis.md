# Query processing and optimisation: Study Session 4

These results were collected on 15 November 2026 using the UUID-based marketplace schema from [Portfolio 1](../../portfolio-1-database-design/docs/design-report.md). The experiment runner completed E1–E7 and E9, and pgbench completed E8 on PostgreSQL 15.14. The reports in `evidence/experiments/` contain the detailed tables and saved plans. The main Q1–Q8 before/after comparison is discussed separately in [performance-analysis.md](performance-analysis.md).

## 1. Processing a query

PostgreSQL parses the query, checks its tables and columns, applies rewrites, compares estimated plan costs and executes the chosen plan. `EXPLAIN (ANALYZE, BUFFERS)` shows both the estimated work and what happened during execution.

The Q4 query tree and graph illustrate the relationships between products, product variations and inventory. They are teaching diagrams rather than a record of the optimiser’s internal representation. The saved plans show the actual access paths chosen for the measured query.

## 2. Statistics and estimates: E1 and E9

E1 changes the distribution of pending orders in a scratch table. Before the change, the scan estimated 14,880 matching rows and found 14,904. With stale statistics, it estimated 25,290 and found 109,527. Refreshing statistics changed the plan to a parallel sequential scan and reduced the median from 19.570 ms to 13.050 ms. Parallel-plan row figures are per participating process, so they should not be compared directly with a serial scan’s total without accounting for loops and workers.

E9 checks estimate accuracy across the marketplace queries. Q3 had the largest reported difference, about 39 times at the grouping step. This identifies a place to investigate, rather than proving that the whole query has a poor plan. E9 uses one measured execution per query, so its times are not the three-run medians from the main comparison.

## 3. Query rewriting: E2

The IN, EXISTS and JOIN-with-DISTINCT versions returned 2,566 rows each and used hash joins. Their medians were 5.105, 5.210 and 6.525 ms respectively. These results give little reason to expect a large benefit from changing syntax alone for this query.

The aggregation rewrite made a clearer difference: the correlated subquery took 424.424 ms, while the join with GROUP BY took 145.036 ms. The rewritten query also used fewer shared-buffer hits.

Rewriting the date predicate as a range reduced the median from 18.985 ms to 0.052 ms. Both plans used index-only scans, but the range let PostgreSQL restrict the index search instead of evaluating a function across many entries.

## 4. Join algorithms: E3

For the selective query, the optimiser chose a hash join at 36.238 ms. Forced nested loops took 37.291 ms, while the forced merge join took 424.789 ms. For the broader query, the chosen hash join took 550.900 ms; forced merge and nested-loop plans took 1,940.019 and 1,974.329 ms.

The chosen join strategy was therefore reasonable for both workloads in this run. Changing planner settings is useful for comparison, but these results do not justify forcing the same join algorithm for every query.

## 5. Index structure: E4

The latest-payment query took 11.808 ms without an index. A single-column B-tree reduced it to 9.289 ms, and a hash index took 10.877 ms. Both still required sorting.

The composite B-tree matched the filter and date order, reducing the median to 0.015 ms. Adding the selected columns with INCLUDE produced an index-only scan at 0.014 ms. The difference between those last two times is too small to support a general performance claim. The covering index also used more space: 15 MB compared with 7,456 kB for the composite index.

## 6. Precomputed results: E5

Q8 took 83.765 ms on the base tables and 0.007 ms on the materialised view. The all-seller revenue report took 27.888 ms on the base tables and 0.009 ms on its materialised view.

These read times exclude the work of keeping the views current. Refreshing the customer-value view took about 98 ms in this run, and a view can show old data between refreshes. That trade-off needs to match the reporting requirement.

## 7. Parallelism and memory: E6

The scan-and-aggregate query took 140.861 ms with parallel workers disabled. The settings allowing one, two and four workers produced medians of 117.068, 56.728 and 51.378 ms. These are configured limits; they do not establish that every requested worker was launched.

At 4 MB of work_mem, the sort still used an external merge and took 106.472 ms. At 64 MB, it used an in-memory quicksort and took 70.866 ms. Raising memory for one query can help, but the setting also needs to account for concurrent queries and multiple sort operations.

## 8. Physical organisation: E7

The unordered heap with a B-tree answered the range query in 4.075 ms. After clustering by order ID, the range took 2.746 ms and shared-buffer hits fell from 3,513 to 105. Clustering placed related rows together, but it is a one-time operation; later writes do not automatically maintain that order.

The hash index supported the equality query at 0.007 ms but could not serve the range query, which fell back to a scan. The sorted table’s BRIN index used only 24 kB, but its range query took 17.430 ms. Index size and execution time therefore need to be considered together.

## 9. Performance under load: E8

The mixed read workload ran for 20 seconds per configuration, with four clients and two threads.

| Configuration | Transactions/s | Average latency (ms) | Failed transactions |
|---|---|---|---|
| Without four secondary indexes | 430.959 | 9.282 | 0 |
| With those indexes | 40193.911 | 0.100 | 0 |

The recorded throughput was about 93.3 times higher with the indexes. This is one short local workload, and the result should be repeated before being treated as a stable capacity estimate. It measures reads and does not include the cost of maintaining indexes during writes.

The existing pg_stat_statements file has not been refreshed as part of this workflow, so it is not evidence for where time went in this new load test.

## 10. What these results support

The marketplace queries benefit most when an index matches a selective filter or an ordered lookup. Broader aggregation still needs to process many rows, while materialised views move that work to refresh time. Statistics, query structure, memory and physical row placement all affected the measured behaviour.

The data is synthetic and the experiments run on one local server. Warm caches, concurrent activity and the number of repetitions affect timings. These results explain the tested workloads; they do not establish production capacity or distributed-system behaviour.
