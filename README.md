# Advanced Database Systems Portfolio

This repository contains my work for MIT 8103: Advanced Database Systems. I use a simulated marketplace based on Konga to explore database design, query optimisation, transactions, NoSQL models and distributed databases.

The portfolios follow the same business scenario. Sellers list products, customers add items to a cart and place orders, payments are recorded, stock is managed, and shipments are tracked. Working with one scenario makes it easier to see how a design decision affects the queries and transactions that use it.

All customer, seller, product and transaction data is synthetic. This is strictly for academic purposes, not a description of Konga’s actual database.

## How the portfolios fit together

Portfolio 1 is the starting point. It defines the entities, relationships and business rules used throughout the project. The later portfolios examine how that design behaves under different workloads and where another approach might help.

| Portfolio | Main question | What it contains |
|---|---|---|
| [1: Database design](portfolio-1-database-design/docs/design-report.md) | How should the marketplace data be organised? | Requirements, diagrams, normalisation, a PostgreSQL schema, sample data, constraints, access roles and tests |
| [2: Query optimisation](portfolio-2-query-optimisation/README.md) | How can queries over that design run more efficiently? | A larger dataset, eight marketplace queries, execution plans, indexes and optimisation experiments |
| [3: Transactions and concurrency](portfolio-3-transactions-concurrency/README.md) | What happens when several sessions change related data at once? | Checkout examples, rollback and savepoints, stock conflicts, isolation levels, locks and deadlocks, plus durability and two-phase commit demonstrations |
| [4: NoSQL models](portfolio-4-nosql/README.md) | Which parts of the marketplace could benefit from a different data model? | Document, key-value and graph experiments, a wide-column design, and a comparison with the relational model |
| [5: Distributed and cloud databases](portfolio-5-distributed-cloud/README.md) | How could the database support data spread across services or locations? | Replication, sharding, security and cloud deployment exercises |

For example, Portfolio 1 separates products from variants (product variations) and gives each product variation a stock record. Portfolio 2 queries those relationships to report sales and low stock. Portfolio 3 uses the stock record to show what happens when two customers try to buy the last unit. Portfolio 4 then explores how related catalogue and application data could be represented in other models.

## Finding your way around

Each portfolio keeps its scripts, explanations and evidence close together:

- `sql/` or `src/` contains the runnable work.
- `docs/` explains the design choices and results.
- `evidence/` contains saved output where results have been collected.
- `design/` contains supporting designs, including models that have not been run.

Start with the [case study](portfolio-1-database-design/docs/case-study.md), then read the [design report](portfolio-1-database-design/docs/design-report.md) and [normalisation walkthrough](portfolio-1-database-design/docs/normalisation.md). Each later portfolio’s README explains its setup and run order.

## Running the work locally

The main tools are PostgreSQL, its command-line tools (`psql`, `createdb`, `pg_dump`, `pg_restore` and `pgbench`), and Node.js with npm. Portfolio 4 also needs the services used by each experiment, such as Redis and a MongoDB-protocol server. Its README gives the details.

Install the JavaScript dependencies from the repository root:

```bash
npm install
```

Use separate databases for the first three portfolios so that the larger dataset and concurrency demonstrations do not change Portfolio 1’s sample data.

| Database | Purpose | Starting data |
|---|---|---|
| `konga_p1` | Database design and constraint tests | Portfolio 1’s small sample |
| `konga_p2` | Query optimisation | Portfolio 2’s large seed |
| `konga_p3` | Transactions and concurrency | Portfolio 1’s small sample |

To set up Portfolio 1, run the following from the repository root:

```bash
createdb konga_p1
psql -X -v ON_ERROR_STOP=1 -d konga_p1 -f portfolio-1-database-design/sql/01_schema.sql
psql -X -v ON_ERROR_STOP=1 -d konga_p1 -f portfolio-1-database-design/sql/02_sample_data.sql
psql -X -d konga_p1 -f portfolio-1-database-design/sql/03_constraint_tests.sql
```

The schema script deletes and recreates the `konga` schema in the selected database. Run it in a database intended for these exercises. The sample-data script is intended for empty tables, while the constraint tests create their own records and roll them back.

Follow the Portfolio 2 and Portfolio 3 READMEs to create and load their databases. Both use Portfolio 1’s schema, but Portfolio 2’s large seed has its own UUIDs. Portfolio 3 uses the UUIDs from the small sample. Mixing the datasets can leave a script looking for records that are not there.

The npm commands in [package.json](package.json) provide shortcuts for the JavaScript scripts. For example:

```bash
PGDATABASE=konga_p2 npm run p2:experiments
PGDATABASE=konga_p3 npm run p3:lab
npm run p4:data
```

Some demonstrations go beyond reading data. The large seed clears tables, concurrency scripts reset demonstration records, and the durability script deliberately stops a PostgreSQL server. The durability exercise belongs on a disposable instance, separate from databases you want to keep.

## Reading the evidence

A script being present does not mean every experiment has been completed. The portfolio READMEs distinguish between prepared work, recorded results and design-only exercises.

Portfolio 2 now includes a [fresh query comparison](portfolio-2-query-optimisation/evidence/comparison.md) for the UUID-based schema. The experiment reports and load-test output have also been refreshed. Older standalone index-size and pg_stat_statements files remain historical. Compatibility checks are recorded in [current-schema-validation.md](portfolio-2-query-optimisation/evidence/current-schema-validation.md). Portfolio 3 also retains older transcripts with numeric fixture IDs. Those files are kept as records of the earlier runs, rather than presented as fresh output from the updated scripts.

Portfolio 4’s analysis identifies the comparisons that still need measured results. Its wide-column model is a design exercise. Timings from any portfolio depend on the machine, database settings, dataset and cache state, so a fresh run may produce different numbers.

## AI assistance

I used ChatGPT/Codex while developing this portfolio. The assistance included explaining concepts such as explaining transitive dependencies, drafting and revising documentation, generating and correcting SQL and JavaScript, test scripts, and diagnosing errors from terminal output. Diagrams were prepared using mermaid extension in vscode marketplace

AI also helped align scripts with the UUID-based schema  as previous work used integers for ID causing a discrepancy across the app, and run selected checks in separate test databases. Where a test was blocked, declined or not run, that limitation should remain visible. Generated text and code are not evidence that an experiment succeeded; saved database output and reproducible checks are needed to support the results.

This repository therefore includes AI-assisted work. The explanations, scripts and results still need to be reviewed against the course requirements, and I remain responsible for understanding and explaining what is submitted. The portfolio notes distinguish measured results from proposed designs and work that is still pending.

## Scope and limitations

The project simplifies a real marketplace so the database concepts remain manageable. Portfolio 1 tracks a single warehouse and allows at most one shipment per seller for each order. The datasets are synthetic, and most experiments use local services rather than a production deployment.

The business context draws on public descriptions of Konga, including its seller handbook and coverage from Techpoint and Entrepreneurs.ng. The database structure and generated records are part of this simulation.


<!-- Note -->
portfolio 5 is incomplete as I am not very avast with cloud services