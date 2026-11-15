# E2: query rewriting, flattening and sargable predicates

## E2a. Nested query vs join (flattening)

| Formulation | Join strategy in plan | Median ms | Rows |
|---|---|---|---|
| E2a IN (subquery) | Hash Join | 5.353 | 2366 |
| E2a EXISTS (correlated) | Hash Join | 4.703 | 2366 |
| E2a JOIN + DISTINCT | Hash Join | 6.452 | 2366 |

## E2b. Correlated subquery vs join with aggregation

| Formulation | Strategy | Median ms | Buffers hit |
|---|---|---|---|
| E2b correlated subquery per row | SubPlan | 88.85 | 269516 |
| E2b join + GROUP BY (rewritten) | Hash Right Join | 113.939 | 17882 |

## E2c. Sargable predicate

| Predicate form | Access path | Median ms | Buffers hit |
|---|---|---|---|
| E2c function on column: date_trunc('day', placed_at) = DATE | Index Only Scan | 32.83 | 1660 |
| E2c range on the bare column (rewritten) | Index Only Scan | 0.073 | 10 |
