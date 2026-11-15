| Query | Before (ms) | After (ms) | Speed-up |

> Historical analysis: these measurements and diagrams come from the earlier integer-ID schema. The current SQL uses UUID-as-text IDs and `quantity_in_store`. Rerun the updated scripts before using these timings as evidence for the current design. Buffer totals from the earlier experiment harness may include double-counted child-node buffers; the updated harness reads the root counter.
|---|---|---|---|
| q1_customer_order_history | 7.61 | 0.12 | 65.0x |
| q2_top_selling_90_days | 172.61 | 197.54 | 0.9x |
| q3_seller_monthly_revenue | 54.42 | 7.94 | 6.9x |
| q4_low_stock_in_category | 10.39 | 12.02 | 0.9x |
| q5_product_name_search | 8.64 | 0.27 | 32.6x |
| q6_abandoned_pending_orders | 13.56 | 0.25 | 53.6x |
| q7_product_recent_reviews | 4.87 | 0.13 | 38.0x |
| q8_top_customers_lifetime_value | 132.30 | 125.86 | 1.1x |
