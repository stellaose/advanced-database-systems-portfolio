# E3: join algorithms

Same query, same data; only the allowed join algorithm changes (`SET enable_...`). 'Optimiser's choice' is the plan PostgreSQL picked on its own from its cost estimates.

| Selectivity | Setting | Join used | Estimated total cost | Median ms | Buffers hit |
|---|---|---|---|---|---|
| selective | optimiser's choice | Hash Join | 10573.94 | 48.43 | 25829 |
| selective | force hash join | Hash Join | 10573.94 | 44.073 | 25829 |
| selective | force merge join | Merge Join | 24895.67 | 67.604 | 54754 |
| selective | force nested loop | Nested Loop | 14038.70 | 15.091 | 49521 |
| broad | optimiser's choice | Merge Join | 46469.55 | 258.77 | 28245 |
| broad | force hash join | Hash Join | 46939.39 | 345.939 | 23046 |
| broad | force merge join | Merge Join | 46469.55 | 258.77 | 28245 |
| broad | force nested loop | Nested Loop | 82464.74 | 328.859 | 2995860 |

