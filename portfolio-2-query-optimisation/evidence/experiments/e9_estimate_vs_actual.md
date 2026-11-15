# E9: estimated vs actual row counts (cost-estimate accuracy)

Large gaps between estimated and actual rows point to outdated statistics or a poor model (Study Session 4, 4.1.3.2). 'Worst node' is the largest estimate error among scan, join and aggregate nodes that ran once and were not cut short by a LIMIT (a LIMIT stops a scan early, which makes actual rows smaller than estimated without the estimate being wrong).

| Query | Median ms (1 run) | Worst node estimate error |
|---|---|---|
| Q1 | 0.023 | 1.6x (Bitmap Heap Scan on orders) |
| Q2 | 543.964 | 2.4x (Finalize GroupAggregate) |
| Q3 | 23.351 | 39.0x (GroupAggregate) |
| Q4 | 8.3 | 1.1x (Hash Join) |
| Q5 | 0.102 | 2.0x (Bitmap Heap Scan on products) |
| Q6 | 0.028 | 1.0x () |
| Q7 | 0.023 | 1.0x () |
| Q8 | 78.936 | 1.0x (HashAggregate) |

