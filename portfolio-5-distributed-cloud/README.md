# Portfolio 5: Distributed Databases, Cloud and Security

**Case study:** Konga, a simulated multi-seller marketplace (see the root README). Synthetic data only. Everything runs on one machine, so there is no real network delay, and the analysis says so wherever it matters.

## Evidence checklist
Tick each box only after you have run the script and saved its output.
- [x] Architecture and cloud mapping: [`docs/architecture.png`](docs/architecture.png), [`docs/security-and-cloud-design.md`](docs/security-and-cloud-design.md)
- [ ] Replication, lag, sync vs async, stale read, CAP trade-off, failover with data loss: [`sql/replication_lab.mjs`](sql/replication_lab.mjs) -> `evidence/01-replication-lab-output.txt`
- [ ] Horizontal fragmentation (sharding by region), transparency, pruning, pushdown, cost, partial availability: [`sql/sharding_fdw_lab.mjs`](sql/sharding_fdw_lab.mjs) -> `evidence/02-sharding-fdw-output.txt`
- [ ] Security tests (SQL injection, least privilege, one finding fixed): [`sql/security_tests.mjs`](sql/security_tests.mjs), [`sql/hardening.sql`](sql/hardening.sql) -> `evidence/03-security-tests-output.txt`
- [ ] Analysis tied to Study Session 2: [`docs/analysis.md`](docs/analysis.md) (fill the `<...>` slots from your evidence)
- [ ] Cloud deployment: **design only, not run** ([`design/docker-compose.yml`](design/docker-compose.yml))

## How to run (macOS, Homebrew PostgreSQL)
Needs the PostgreSQL server binaries (`initdb`, `pg_ctl`, `pg_basebackup`; Homebrew installs them), Node.js 20+, and `npm install` once at the repository root. Run from the repository root and create the folder first: `mkdir -p portfolio-5-distributed-cloud/evidence`.
```bash
# 1. Replication lab: builds its OWN throwaway primary (port 5440) and replica (5441) under /tmp/replab, loads Portfolio 1's 01 and 02 SQL, and kills servers on purpose.
#    If it cannot find initdb, set PGBIN to your PostgreSQL bin folder, for example PGBIN="$(brew --prefix postgresql@15)/bin"
npm run p5:replication 2>&1 | tee portfolio-5-distributed-cloud/evidence/01-replication-lab-output.txt

# 2. Sharding lab: creates and DROPS the databases shard_lagos, shard_abuja, konga_coord, konga_central on your server (needs a superuser).
npm run p5:sharding 2>&1 | tee portfolio-5-distributed-cloud/evidence/02-sharding-fdw-output.txt

# 3. Security tests: needs konga_p1 loaded with Portfolio 1's 01, 02 and 04 SQL (04 creates the roles).
PG_DB=konga_p1 npm run p5:security 2>&1 | tee portfolio-5-distributed-cloud/evidence/03-security-tests-output.txt
```
Connection variables for 2 and 3: `PG_HOST` (default `localhost`), `PG_PORT` (default 5432), `PG_USER` (default your Mac user). Do not run the sharding lab on a server holding data you care about.

## What each result should show
| Topic | What to look for in your output |
|---|---|
| Async replication lag | Replica catches up within milliseconds on one machine (R2) |
| Stale read with injected 3 s delay | Replica returns the old value, primary the new one, replica catches up later (R3) |
| Cost of synchronous commit | Higher commit latency than async (R4) |
| Replica down, synchronous commit | Writes blocked (CP); switching to async restores writes (AP) (R5) |
| Failover after async replication | The acknowledged write is lost on the promoted replica (R6) |
| Sharding transparency and pruning | One query across both shards; a region filter contacts only one (S1, S2) |
| Aggregate pushdown | Much faster than pulling all rows to the coordinator (S3) |
| One shard down | Single-region queries keep working; the all-region query fails (S5) |
| Security | Injection leaks data in vulnerable code and returns 0 rows when parameterised; the over-privilege finding is fixed by `hardening.sql` (T1 to T4) |

## Design choices and lessons learned
- The replication lab uses its own throwaway clusters so that crashing and promoting servers cannot damage your real databases.
- The sharding lab generates its own synthetic orders (400,000 rows) rather than using the Portfolio 1 sample data, because sharding needs volume.
- _TODO: add your own reflection (for example, which consistency choice you would make for stock and why)._

## Limitations
One machine, no network latency, no automatic failover tool, no cloud, no TLS or encryption tests, and `postgres_fdw` gives no atomic commit across shards. See the last section of `docs/analysis.md`.
