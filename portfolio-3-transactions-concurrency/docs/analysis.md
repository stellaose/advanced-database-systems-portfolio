# Analysis: transactions and concurrency in Konga

> The recorded examples below use the earlier numeric fixture IDs. Current runnable scripts use the UUIDs in Portfolio 1’s sample data and target a separate `konga_p3` database.

The lab uses the orders, payments and inventory model from [Portfolio 1](../../portfolio-1-database-design/docs/design-report.md). That design defines valid records; this portfolio examines whether transactions preserve the intended behaviour when two sessions work at once.

## 1. Choosing an isolation level

| Level (PostgreSQL)                  | Dirty read | Non-repeatable read  | Phantom                  | Write skew                          | Seen in |
| ----------------------------------- | ---------- | -------------------- | ------------------------ | ----------------------------------- | ------- |
| READ UNCOMMITTED (= READ COMMITTED) | no         | n/a                  | n/a                      | n/a                                 | S1      |
| READ COMMITTED (default)            | no         | **yes** (25 then 20) | **yes** (count 0 then 1) | possible                            | S2      |
| REPEATABLE READ                     | no         | no (25 then 25)      | no (0 then 0)            | **yes** (0 active sellers left)     | S2, S4  |
| SERIALIZABLE                        | no         | no                   | no                       | no (one transaction aborted, 40001) | S4      |

For this simulation, READ COMMITTED is a reasonable starting point for browsing and order history, where a later read can legitimately show new information. Stock reservation needs a check that remains valid while the update happens. The atomic `UPDATE ... WHERE quantity_in_store - quantity_reserved >= 1` keeps that check and the change in one statement. A rule spanning several rows, such as keeping at least one seller active, may need stronger isolation or another explicit coordination mechanism. Applications using SERIALIZABLE must be prepared to retry transactions rejected with error 40001.

## 2. Comparing the three fixes for overselling (S3)

| Fix                         | How it works                                                                 | Cost                                                             |
| --------------------------- | ---------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `SELECT ... FOR UPDATE`     | Second buyer waits for the first to finish, then sees the new stock          | Waiting; locks held while the application thinks                 |
| Atomic conditional `UPDATE` | Check and write in one statement; waiter re-evaluates `WHERE` on the new row | One statement; suitable when the rule can be checked within that update   |
| REPEATABLE READ + retry     | A conflicting update can wait, then fail with error 40001; the application retries                           | Application must catch the error and retry the whole transaction |

All three controls ended with one reserved unit and one accepted purchase. The naive version also left `reserved = 1`, but both customers had been told their purchase succeeded. Looking only at the final stock row would miss the problem; the test needs to follow what each session read and reported.

## 3. Deadlock (S5)

Opposite lock order produced a cycle. PostgreSQL detected it after `deadlock_timeout` (set to 300 ms for the demo; default 1 s), aborted one session with 40P01, and the other committed. S5b avoids that cycle by having both sessions lock rows in the same key order. One session waits for the other, but they do not hold locks that each needs from the other.

## 4. Durability (WAL)

After `kill -9` the server replayed its write-ahead log on restart (`redo starts ... redo done` in the log) and the committed value (111) was present, while the uncommitted 222 was gone. This is the "D" of ACID. It depends on `fsync` and `synchronous_commit` being on, which they were. Turning them off would be faster but could lose a committed order in a power cut.

## 5. Two-phase commit (2PC)

Orders and payments are in two databases, as they would be in a split architecture.

1. Case 1: both prepared, locks stayed held (a competing update timed out), then both committed.
2. Case 2: the payment side could not prepare, so the coordinator rolled back the prepared order. Neither side kept anything.
3. Case 3: the server crashed with both prepared. After restart both were still prepared (in `pg_prepared_xacts`) and could be committed, so no order was lost and none was half-done.

Weakness shown by case 1: while prepared, rows stay locked, so a coordinator that fails and never returns blocks other work. This blocking is the known cost of 2PC and one reason large distributed systems prefer eventually consistent designs (BASE) with compensation, see Portfolio 4 and 5.

## 6. ACID versus BASE for Konga

The orders, payments and stock records introduced in Portfolio 1 need transaction guarantees because a failed or conflicting change could affect a payment or a purchase. A product-view counter or a "recently viewed" list can be eventually consistent (BASE) and live in a key-value store (Portfolio 4).
