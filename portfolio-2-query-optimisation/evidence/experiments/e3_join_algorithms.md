# E3: join algorithms

Same query, same data; only the allowed join algorithm changes (`SET enable_...`). 'Optimiser's choice' is the plan PostgreSQL picked on its own from its cost estimates.

| Selectivity | Setting | Join used | Estimated total cost | Median ms | Buffers hit |
|---|---|---|---|---|---|
| selective | optimiser's choice | Hash Join | 18083.85 | 36.238 | 9433 |
| selective | force hash join | Hash Join | 18083.85 | 32.225 | 9717 |
| selective | force merge join | Merge Join | 41671.84 | 424.789 | 13217 |
| selective | force nested loop | Nested Loop | 24071.34 | 37.291 | 10424 |
| broad | optimiser's choice | Hash Join | 68703.29 | 550.9 | 12141 |
| broad | force hash join | Hash Join | 68703.29 | 541.432 | 12429 |
| broad | force merge join | Merge Join | 80327.24 | 1940.019 | 16157 |
| broad | force nested loop | Nested Loop | 106095.43 | 1974.329 | 454719 |

