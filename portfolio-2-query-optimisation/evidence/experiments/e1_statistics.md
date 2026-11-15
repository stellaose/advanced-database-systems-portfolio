# E1: statistics and the cost-based optimiser

Query: `SELECT count(*), sum(total_amount) FROM exp.ostat WHERE status = 'returned'`. The optimiser chooses a plan from its *estimate* of how many rows match.

| Step | Scan chosen | Estimated rows at scan | Actual rows at scan | Median ms | Buffers hit |
|---|---|---|---|---|---|
| A. fresh statistics ('returned' is about 5% of rows) | Bitmap Heap Scan, Index Scan | 7650 | 7611 | 3.076 | 2819 |
| B. STALE statistics after the data changed | Bitmap Heap Scan, Index Scan | 12975 | 107282 | 20.977 | 5027 |
| C. after ANALYZE (statistics refreshed) | Seq Scan | 107475 | 107282 | 24.686 | 4776 |

