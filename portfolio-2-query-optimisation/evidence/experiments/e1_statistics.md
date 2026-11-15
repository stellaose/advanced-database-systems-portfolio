# E1: statistics and the cost-based optimiser

Query: `SELECT count(*), sum(total_amount) FROM exp.ostat WHERE status = 'pending'`. The optimiser chooses a plan from its *estimate* of how many rows match.

| Step | Scan chosen | Estimated rows at scan | Actual rows at scan | Median ms | Buffers hit |
|---|---|---|---|---|---|
| A. fresh statistics ('pending' is a small share of rows) | Bitmap Heap Scan, Index Scan | 14880 | 14904 | 4.121 | 2472 |
| B. STALE statistics after the data changed | Bitmap Heap Scan, Index Scan | 25290 | 109527 | 19.57 | 4276 |
| C. after ANALYZE (statistics refreshed) | Parallel Seq Scan | 45946 | 36509 | 13.05 | 4181 |

