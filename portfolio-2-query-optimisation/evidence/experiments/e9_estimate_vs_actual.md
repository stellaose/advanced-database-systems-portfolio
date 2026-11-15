# E9: estimated vs actual row counts (cost-estimate accuracy)

Large gaps between estimated and actual rows point to outdated statistics or a poor model (Study Session 4, 4.1.3.2). 'Worst node' is the largest estimate error among scan, join and aggregate nodes that ran once and were not cut short by a LIMIT (a LIMIT stops a scan early, which makes actual rows smaller than estimated without the estimate being wrong).

| Query | Median ms (1 run) | Worst node estimate error |
|---|---|---|
| Q1 | 0.048 | 1.1x (Bitmap Heap Scan on orders) |
| Q2 | 160.377 | 2.4x (HashAggregate) |
| Q3 | 3.766 | 35.9x (GroupAggregate) |
| Q4 | 9.584 | 1.1x (Hash Join) |
| Q5 | 8.212 | 2.0x (Seq Scan on products) |
| Q6 | 0.077 | 1.0x () |
| Q7 | 0.041 | 1.0x () |
| Q8 | 139.125 | 1.0x (Hash Join) |

