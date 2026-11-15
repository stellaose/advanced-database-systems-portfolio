# E7: file organisation (heap, indexed, hash, clustered, BRIN)

Table: copy of `order_items` (450,000 rows). Physical-order correlation of `order_id` (1.0 = perfectly sorted on disk): random heap 0.004, sorted copy 1.000; after CLUSTER the heap table has 1.000. Buffers = pages read from cache (logical I/O).

| File organisation | Index size | Exact-match access path | Exact ms | Exact buffers | Range access path | Range ms | Range buffers |
|---|---|---|---|---|---|---|---|
| Heap (unordered), no index | - | Parallel Seq Scan | 28.336 | 7552 | Parallel Seq Scan | 30.651 | 15104 |
| Heap + B-tree index (indexed organisation, scattered rows) | 6464 kB | Bitmap Heap Scan, Index Scan | 0.009 | 9 | Bitmap Heap Scan, Index Scan | 2.776 | 5249 |
| Heap + hash index | 15 MB | Bitmap Heap Scan, Index Scan | 0.015 | 5 | Parallel Seq Scan | 27.893 | 15104 |
| Clustered on order_id + B-tree | 6464 kB | Index Scan | 0.007 | 4 | Index Scan | 0.667 | 100 |
| Sorted table + BRIN index (block-range) | 24 kB | Bitmap Heap Scan, Index Scan | 0.86 | 132 | Bitmap Heap Scan, Index Scan | 1.276 | 262 |

