# E5: materialised views (pre-computing results)

The two queries that indexes could not speed up (Q8, and an all-seller revenue report) are pre-computed. Cost of the technique: REFRESH of the Q8 view took about 98 ms in this run; view sizes 2752 kB and 1048 kB; the data is only as fresh as the last refresh.

| Query | Median ms | Buffers hit |
|---|---|---|
| Q8 on base tables (join + aggregate every time) | 83.765 | 481 |
| Q8 from the materialised view | 0.007 | 12 |
| Seller x month revenue report on base tables | 27.888 | 8951 |
| Seller x month revenue from the materialised view | 0.009 | 21 |

