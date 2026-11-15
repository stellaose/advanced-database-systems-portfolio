# E4: index types and structure

Query: `SELECT payment_id, amount, created_at FROM exp.p4 WHERE method = 'card' AND status = 'successful' ORDER BY created_at DESC LIMIT 20` (the latest 20 successful card payments; about 28,000 rows match the filter, 150,000-row table). Buffers hit = pages read from cache (logical I/O).

| Index | Access path | Sort step needed | Index size | Buffers hit | Median ms |
|---|---|---|---|---|---|
| 1. no index (heap scan) | Parallel Seq Scan | yes | - | 6827 | 13.781 |
| 2. single-column B-tree (method) | Bitmap Heap Scan, Index Scan | yes | 1040 kB | 5046 | 9.515 |
| 3. hash index (method) | Bitmap Heap Scan, Index Scan | yes | 7056 kB | 5286 | 10.602 |
| 4. multi-column B-tree (method, status, created_at DESC) | Index Scan | no | 7848 kB | 46 | 0.024 |
| 5. covering (same keys + INCLUDE payment_id, amount) | Index Only Scan | no | 12 MB | 8 | 0.015 |

