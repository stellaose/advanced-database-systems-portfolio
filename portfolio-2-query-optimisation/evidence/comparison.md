# Query timings before and after indexing

Recorded on 15 November 2026 using the current UUID-based schema. Each timing is the median of three measured runs after one warm-up. The runner saves the final measured plan separately, so its execution time may differ from the median.

| Query | Before (ms) | After (ms) | Change |
|---|---|---|---|
| Q1: Customer order history | 12.118 | 0.036 | 336.6× faster |
| Q2: Top-selling product variations over 90 days | 550.763 | 591.408 | 7.4% slower |
| Q3: Seller monthly revenue | 50.044 | 22.520 | 2.2× faster |
| Q4: Low stock in a category | 25.655 | 8.885 | 2.9× faster |
| Q5: Product name search | 9.747 | 0.100 | 97.5× faster |
| Q6: Older pending orders | 11.900 | 0.035 | 340.0× faster |
| Q7: Recent product reviews | 4.132 | 0.068 | 60.8× faster |
| Q8: Top customers by delivered-order value | 101.866 | 106.558 | 4.6% slower |

All eight saved result samples match between the before and after runs. These files contain up to the first 15 result rows, so this check is not a comparison of every row in larger result sets.

Six queries improved. Q2 and Q8 were slower by about 7.4% and 4.6% respectively. These small differences do not establish a consistent regression; repeated measurements would be needed. The results show that the added indexes did not improve these two broad aggregations in this run.

Sources: `before/summary.tsv`, `after/summary.tsv` and the corresponding saved plans and result samples.
