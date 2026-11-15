# E5: materialised views (pre-computing results)

The two queries that indexes could not speed up (Q8, and an all-seller revenue report) are pre-computed. Cost of the technique: REFRESH of the Q8 view took about 114 ms in this run; view sizes 2184 kB and 736 kB; the data is only as fresh as the last refresh.

| Query | Median ms | Buffers hit |
|---|---|---|
| Q8 on base tables (join + aggregate every time) | 107.588 | 16707 |
| Q8 from the materialised view | 0.014 | 24 |
| Seller x month revenue report on base tables | 6.028 | 53673 |
| Seller x month revenue from the materialised view | 0.013 | 42 |

