# Performance analysis (Portfolio 2)

This comparison uses the marketplace schema from [Portfolio 1](../../portfolio-1-database-design/docs/design-report.md), with UUIDs stored as text and the larger synthetic dataset from `sql/01_seed_large.sql`. The before and after evidence was collected on 15 November 2026.

Each query has one warm-up followed by three measured executions. The table reports the median execution time. The saved plan is the final measured execution, which may have a different time from the median. Database version and machine settings should be recorded alongside the final submission; they cannot be established from the plan files alone.

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

## Why some queries benefited from indexes

- **Q1: Customer history.** The plan changed from a parallel sequential scan to a bitmap lookup using `idx_orders_customer_placed`. It retrieved five orders directly. A sort is still present in the saved after plan.
- **Q3: Seller revenue.** Indexes support the path from the seller’s products to their product variations and order items. The after plan uses those indexes instead of scanning the full catalogue and order-item tables at each join stage.
- **Q4: Low stock.** The after plan uses the partial category index for live products and an index-only scan of low-stock inventory. It still scans product variations, but the overall median fell from 25.655 ms to 8.885 ms.
- **Q5: Name search.** The trigram index supports the substring search. The before plan scans products; the after plan uses a bitmap index scan to locate the matching product.
- **Q6: Older pending orders.** The partial index contains pending orders in date order. The after plan can stop after the first 50 matches, avoiding the earlier parallel scan and sort.
- **Q7: Recent reviews.** The review index locates the three matching reviews through a bitmap lookup. The saved after plan still sorts these rows by date.

## Why Q2 and Q8 changed little

Q2 still joins a large number of recent orders and order items, groups the results and selects the ten largest totals. The date index changes the order lookup to a bitmap scan, but scanning order items and aggregating their quantities remain substantial work. The median increased from 550.763 ms to 591.408 ms.

Q8 aggregates delivered orders across customers. Both plans use sequential scans and a hash join. Its median increased from 101.866 ms to 106.558 ms. The indexes added for selective queries do not remove the work required by this report.

These increases are about 7.4% and 4.6%. Three timings per query do not establish whether those small changes are repeatable. The supported conclusion is that the indexes provided no measured improvement for Q2 and Q8 in this run.

## Correctness and trade-offs

All eight saved result samples match before and after indexing. The runner retains up to 15 rows per query, so this checks the saved samples rather than every row in the larger reports.

Indexes take storage and add maintenance work when rows change. This comparison measures reads, so it does not establish their effect on write throughput. The existing index-size evidence comes from an earlier run and needs to be refreshed before quoting a current storage total.

For broad reports, a summary table or materialised view is another option to investigate. That introduces a separate decision about refresh cost and how old the reported data may be.

## Limitations

The data is synthetic, the runs use a warmed cache, and the results come from one local database. Absolute times should not be treated as production estimates. More repetitions and a write workload would help assess variability and index maintenance costs.

The newly collected Study Session 4 experiments are discussed in [session4-analysis.md](session4-analysis.md). This page covers the Q1–Q8 before/after comparison.
