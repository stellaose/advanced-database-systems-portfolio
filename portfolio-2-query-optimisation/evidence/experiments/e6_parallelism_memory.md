# E6: parallelism and memory

The test machine has 2 CPU cores, so more than 2 workers cannot help.

## Parallel workers (scan-and-aggregate over the 450,000-row `order_items`)

| Setting | Parallel plan? | Median ms |
|---|---|---|
| max_parallel_workers_per_gather = 0 | no | 143.751 |
| max_parallel_workers_per_gather = 1 | yes | 90.193 |
| max_parallel_workers_per_gather = 2 | yes | 101.266 |
| max_parallel_workers_per_gather = 4 | yes | 101.712 |

## Memory: sort spilling to disk

| work_mem | Sort method | Median ms |
|---|---|---|
| 64kB | external merge  Disk: 3992kB | 210.285 |
| 1MB | external merge  Disk: 3976kB | 160.09 |
| 4MB | external merge  Disk: 3976kB | 115.734 |
| 64MB | quicksort  Memory: 13160kB | 103.634 |
