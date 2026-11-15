# Portfolio 3: Transactions and Concurrency

This portfolio tests what happens when several operations use the marketplace database at the same time. It builds on [Portfolio 1’s design](../portfolio-1-database-design/docs/design-report.md), particularly the order, payment and inventory relationships. The lab uses its small synthetic sample in a separate `konga_p3` database so each transaction is easy to follow.

The SQL and Node.js lab now use the UUIDs explicitly assigned in `portfolio-1-database-design/sql/02_sample_data.sql`. Load that file into `konga_p3`; Portfolio 2’s large seed has different IDs and is not suitable for these demonstrations. `PGDATABASE` or `KONGA_P3_DB` selects the lab database, and `LAB_DSN` overrides all connection settings. The default is `konga_p3` on local port 5432.

The checked-in evidence transcripts describe earlier runs with numeric IDs. They have been preserved as historical output; rerun the updated scripts for current UUID output.

## Evidence checklist

- [x] COMMIT, ROLLBACK, SAVEPOINT: [`sql/01_acid_single_session.sql`](sql/01_acid_single_session.sql), output [`evidence/01-acid-single-session-output.txt`](evidence/01-acid-single-session-output.txt)
- [x] Isolation levels (dirty read, non-repeatable read, phantom, write skew): [`sql/concurrency_lab.mjs`](sql/concurrency_lab.mjs) S1, S2, S4
- [x] Concurrency problem and controls (lost update on the last unit; `FOR UPDATE`, atomic `UPDATE ... WHERE`, REPEATABLE READ with retry; deadlock and ordered locking; `NOWAIT`/`SKIP LOCKED`): S3, S5, S6
- [x] Real two-session output: [`evidence/02-concurrency-lab-output.txt`](evidence/02-concurrency-lab-output.txt)
- [x] Durability after a crash (`kill -9`): [`evidence/03-durability-test.txt`](evidence/03-durability-test.txt)
- [x] Two-phase commit across two databases, including a crash while prepared: [`evidence/04-two-phase-commit.txt`](evidence/04-two-phase-commit.txt)
- [x] Analysis: [`docs/analysis.md`](docs/analysis.md)

## What I did

The examples use checkout and stock reservation from Portfolio 1 to make the ACID properties concrete. Creating an order, reserving stock and recording payment gives each transaction several related changes to manage.

| Property | Test | Result |
|---|---|---|
| Atomicity | Checkout creates an order and reserves stock, then the payment insert fails | Everything rolled back; savepoint keeps the good part |
| Consistency | Reserve more stock than exists | Refused by `chk_inventory_reserved`, state unchanged |
| Isolation | Two real sessions, fixed interleaving, 6 scenarios | See analysis; one real anomaly found at each weak level |
| Durability | `kill -9` the server after a commit | Committed change survived, uncommitted change gone |

Main findings from the lab (`evidence/02-concurrency-lab-output.txt`):
- Dirty reads are not possible in PostgreSQL even at READ UNCOMMITTED.
- Non-repeatable and phantom reads happen at READ COMMITTED and not at REPEATABLE READ.
- With only 1 unit in stock, naive read-then-write logic told two customers "success" (lost update). Three fixes worked: `SELECT ... FOR UPDATE`, one atomic conditional `UPDATE`, and REPEATABLE READ with retry.
- Write skew (two admins each suspend a different seller, leaving 0 active) happens at REPEATABLE READ and is stopped by SERIALIZABLE.
- A deadlock was created on purpose and detected (SQLSTATE 40P01); locking rows in a fixed order prevented it.
- Two-phase commit kept an order database and a payment database in step in all three cases, including a server crash while both were prepared.

## How to run

Needs PostgreSQL 16 and Node.js 20+ (run `npm install` once at the repository root).
```bash
createdb konga_p3
psql -d konga_p3 -f ../portfolio-1-database-design/sql/01_schema.sql
psql -d konga_p3 -f ../portfolio-1-database-design/sql/02_sample_data.sql
psql -d konga_p3 -f sql/01_acid_single_session.sql
PGDATABASE=konga_p3 node sql/concurrency_lab.mjs      # or: ... S3 S5
```
`sql/03_durability_and_2pc.sh` kills the server on purpose and is written for my throwaway sandbox instance (port 5433, data dir `/tmp/pgdata`). Edit the variables at its top for your own throwaway instance, and enable `max_prepared_transactions` before the two-phase part. Never run it on a database you care about.

## Design choices and lessons learned

- The lab runs statements in a fixed order from one script, and waits until a session is really blocked on a lock before continuing, so the outcome is repeatable and not a lucky race.
- I used one table row (the last unit of stock) for most demos because overselling is the most realistic Konga failure.
- For a stock rule that fits in one statement, the atomic conditional update is a straightforward starting point. More complex rules may need explicit locks or stronger isolation, with retries handled by the application.

## Limitations

PostgreSQL implements isolation with snapshots (MVCC), so its READ UNCOMMITTED behaves as READ COMMITTED and its REPEATABLE READ also blocks phantoms. A lock-based DBMS would behave differently. Two databases on one server are used for two-phase commit; this shows the protocol but not network failure between machines. No heavy load test was run.
