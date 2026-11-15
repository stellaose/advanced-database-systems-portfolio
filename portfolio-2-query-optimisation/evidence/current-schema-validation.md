# Current schema validation

Verified on 15 November 2026 using PostgreSQL 15.14 (Homebrew, macOS arm64), in a separate temporary database. Portfolio 1's database was not modified.

| Check | Result |
|---|---|
| Portfolio 1 schema followed by the large seed | Passed |
| Customers / products / product variations | 20,000 / 20,000 / 50,000 |
| Orders / order items / payments | 150,000 / 450,000 / 150,000 |
| Shipments / reviews | 313,595 / 60,000 |
| Order totals disagreeing with their item totals | 0 |
| Product variations missing inventory | 0 |
| Q1–Q8 using `run_plans.sh` | All executed successfully |
| Optimisation indexes | All 10 created successfully |
| Q1–Q8 after indexing | All executed successfully |
| Experiment runner E1–E7 and E9 | Completed successfully |
| E8 pgbench smoke check, without and with four indexes | Both completed; 0 failed transactions |
| Bash and Node.js syntax checks | Passed |

The E8 smoke check ran for two seconds per configuration. It verifies that the workload executes; it is not a full performance benchmark. Fresh verification plans and experiment outputs were saved under `/private/tmp/konga-p2-*` rather than overwriting the historical evidence.

The existing before/after timing tables, chart and experimental reports remain historical measurements of the earlier schema. Use the README workflow for a fresh benchmark on the current schema and your own machine.
