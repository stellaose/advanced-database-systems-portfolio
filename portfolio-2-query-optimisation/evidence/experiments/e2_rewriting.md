# E2: query rewriting, flattening and sargable predicates

## E2a. Nested query vs join (flattening)

| Formulation | Join strategy in plan | Median ms | Rows |
|---|---|---|---|
| E2a IN (subquery) | Hash Join | 5.105 | 2566 |
| E2a EXISTS (correlated) | Hash Join | 5.21 | 2566 |
| E2a JOIN + DISTINCT | Hash Join | 6.525 | 2566 |

## E2b. Correlated subquery vs join with aggregation

| Formulation | Strategy | Median ms | Buffers hit |
|---|---|---|---|
| E2b correlated subquery per row | SubPlan | 424.424 | 88032 |
| E2b join + GROUP BY (rewritten) | Hash Right Join | 145.036 | 10976 |

## E2c. Sargable predicate

| Predicate form | Access path | Median ms | Buffers hit |
|---|---|---|---|
| E2c function on column: date_trunc('day', placed_at) = DATE | Index Only Scan | 18.985 | 415 |
| E2c range on the bare column (rewritten) | Index Only Scan | 0.052 | 5 |
