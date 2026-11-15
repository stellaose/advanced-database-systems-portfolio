# Characteristics of a good database, checked against this design

*Study Session 1 lists ten characteristics of a good database. This page checks the Konga design against each one and points to the evidence.*

Portfolio 1 covers six of the ten directly. Performance and concurrency control belong to Portfolios 2 and 3, and scalability and data consistency also depend on later portfolios, so those rows point ahead.

| Characteristic (study session) | How this design meets it | Evidence |
|---|---|---|
| Data integrity | The rules are enforced in the database with primary keys, foreign keys, UNIQUE and CHECK constraints. I wrote 12 negative tests (T1-T12) that each try to break a rule, and all 12 were rejected by the intended constraint. | [`01_schema.sql`](../sql/01_schema.sql), `../evidence/constraint-tests-output.txt` |
| Scalability | Not shown in this portfolio. Indexing is covered in Portfolio 2, partitioning by region/date and replication in Portfolio 5, and a document model for product attributes in Portfolio 4. | Portfolios 2, 4 and 5 |
| Redundancy management | Customer, seller, brand and category details are stored once and referenced by key. The schema is in BCNF, apart from a few columns that are denormalised on purpose. | [normalisation.md](normalisation.md), [section 5](normalisation.md#5-deliberate-exceptions-controlled-denormalisation) for the exceptions |
| Backup and recovery | I took a `pg_dump` backup, dropped the schema, restored it with `pg_restore` and compared row counts. The counts matched. A replica with promotion is covered in Portfolio 5. | `../evidence/backup-restore-test.txt` |
| Flexibility | The views `v_order_summary`, `v_seller_sales` and `v_low_stock` hide the joins and give stable access paths. Schema changes would go through versioned migration scripts. Product attributes that differ per category move to a document model in Portfolio 4. | `../sql/04_physical_design.sql`, [Stage 7](design-report.md#stage-7-deployment-and-maintenance), Portfolio 4 |
| Data security | Three least-privilege roles (`konga_app`, `konga_support`, `konga_analyst`). A column-level grant stops support staff from reading `password_hash`, and analysts read aggregated views only. 4 of 4 role tests passed. | `../sql/04_physical_design.sql`, `../evidence/functional-security-tests-output.txt` |
| Performance | Not measured in this portfolio. Portfolio 2 compares execution plans before and after indexing at 1.5 M rows. | Portfolio 2 |
| Data consistency | Constraints keep each row valid here. Operations such as checkout and stock reservation need transactions, because several changes must succeed together; commit, rollback and isolation are in Portfolio 3, and consistency models for distributed data are in Portfolio 5. | Portfolios 3 and 5 |
| Concurrency control | Locking and isolation levels are demonstrated with concurrent sessions in Portfolio 3, for example two customers buying the last unit. | Portfolio 3 |
| Normalisation | A flat order sheet is taken step by step through 1NF, 2NF, 3NF and BCNF, with the reason for each split. | [normalisation.md](normalisation.md) |
