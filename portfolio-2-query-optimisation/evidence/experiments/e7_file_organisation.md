# E7: file organisation (heap, indexed, hash, clustered, BRIN)

Table: copy of `order_items` (450,000 rows). Physical-order correlation of `order_id` (1.0 = perfectly sorted on disk): random heap 0.000, sorted copy 1.000; after CLUSTER the heap table has 1.000. Buffers = pages read from cache (logical I/O).

| File organisation | Index size | Exact-match access path | Exact ms | Exact buffers | Range access path | Range ms | Range buffers |
|---|---|---|---|---|---|---|---|
| Heap (unordered), no index | - | Parallel Seq Scan | 19.979 | 2400 | Parallel Seq Scan | 180.57 | 2784 |
| Heap + B-tree index (indexed organisation, scattered rows) | 12 MB | Bitmap Heap Scan, Index Scan | 0.022 | 6 | Bitmap Heap Scan, Index Scan | 4.075 | 3513 |
| Heap + hash index | 15 MB | Bitmap Heap Scan, Index Scan | 0.007 | 5 | Parallel Seq Scan | 177.287 | 5586 |
| Clustered on order_id + B-tree | 12 MB | Index Scan | 0.019 | 4 | Index Scan | 2.746 | 105 |
| Sorted table + BRIN index (block-range) | 24 kB | Bitmap Heap Scan, Index Scan | 0.608 | 130 | Bitmap Heap Scan, Index Scan | 17.43 | 258 |

