# Security (Study Session 3, 3.2.2) and cloud design (Study Session 3, 3.1.2)

## 1. Security: the CIA triad applied to Konga (3.2.2.1)
| Objective | Mechanism in Konga | Evidence |
|---|---|---|
| Confidentiality | Roles with least privilege: `konga_support` cannot read `password_hash`; `konga_analyst` sees only reporting views; parameterised queries stop injection | `evidence/03-security-tests-output.txt` T1 to T4; Portfolio 1 `05_functional_and_security_tests.sql` |
| Integrity | CHECK, foreign-key and unique constraints; transactions | T5; Portfolio 3 |
| Availability | Streaming replica, backups and restore, failover | `evidence/01-replication-lab-output.txt`; Portfolio 1 `backup-restore-test.txt` |

### Security test results
- **SQL injection (T1):** a search box that pastes user text into SQL let an attacker's `UNION SELECT` return customer emails and password hashes, even though the connection used the application's own role. The parameterised version (T2) returned 0 rows for the same input.
- **Defence in depth (T3):** the same vulnerable code running as the support role was refused by the database. In that run the refusal came from the support role having no rights on `products` at all, so I state that T3 shows privilege limiting, not that every injection would be blocked.
- **Over-privilege found and fixed (T4):** my own Portfolio 1 grants let the application role `DELETE` customers. The test caught it; `sql/hardening.sql` revokes `DELETE` on the business tables, and the re-run passes all 6 checks. To reproduce the failing first run, re-grant first: `GRANT DELETE ON konga.customers TO konga_app;`.
- **Passwords (T6):** the sample data holds placeholder values, not real hashes. A real system must store a salted slow hash (bcrypt or argon2).

### Mechanisms from 3.2.2.3 that I did not test
Encrypted connections (TLS), encryption at rest, multi-factor authentication, auditing and monitoring, and database firewalls. They are requirements for a real Konga deployment, not results.

## 2. Cloud database features (3.1.2.2) mapped to Konga
| Feature in the study material | What it means for Konga | Built here? |
|---|---|---|
| Scalability (vertical and horizontal) | Bigger primary for stock and payments; more regional shards for orders | Horizontal sharding tested on one machine (Portfolio 5, S1 to S5) |
| High availability (redundancy, automatic failover) | Replica in a second zone, automatic promotion | Manual promote tested (R6); automatic failover not built |
| Managed services (patching, backups, monitoring) | A provider-run PostgreSQL service would take over backups and upgrades | Not used; backup and restore were done by hand (Portfolio 1) |
| Elasticity (pay-as-you-go) | Scale up for sales events such as a big annual shopping day, scale down afterwards | Not tested |
| Global access | Shoppers and sellers in several Nigerian cities and abroad | Not tested; no real network |

**Deployment model (3.1.2.4).** For Konga I would start with a public-cloud managed PostgreSQL, because the team is small and the study material lists reduced administration as the main benefit. A hybrid model would only be justified if a regulator required some data to stay on private infrastructure. I have not checked Nigerian data-protection requirements; that would need to be done before choosing a region.

**Cloud database type (3.1.2.3).** The tested design already maps to the types in the material: relational (PostgreSQL), NoSQL (Redis, document, graph, wide-column), and a distributed SQL option (the material names Spanner and CockroachDB) as the NewSQL alternative discussed in Portfolio 4.

**Files (design only, NOT executed):** `design/docker-compose.yml` sketches the stack; the replica bootstrap there is a TODO. No cloud account was used, so I have no cloud measurements, costs or availability figures, and I do not claim any.
