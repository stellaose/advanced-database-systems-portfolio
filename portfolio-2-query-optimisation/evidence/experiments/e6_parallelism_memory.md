# E6: parallelism and memory

Worker availability depends on the server configuration and available CPU resources.

## Parallel workers (scan-and-aggregate over the 450,000-row `order_items`)

| Setting | Parallel plan? | Median ms |
|---|---|---|
| max_parallel_workers_per_gather = 0 | no | 140.861 |
| max_parallel_workers_per_gather = 1 | yes | 117.068 |
| max_parallel_workers_per_gather = 2 | yes | 56.728 |
| max_parallel_workers_per_gather = 4 | yes | 51.378 |

## Memory: sort spilling to disk

| work_mem | Sort method | Median ms |
|---|---|---|
| 64kB | external merge  Disk: 8288kB | 190.657 |
| 1MB | external merge  Disk: 8232kB | 164.956 |
| 4MB | external merge  Disk: 8232kB | 106.472 |
| 64MB | quicksort  Memory: 19035kB | 70.866 |
