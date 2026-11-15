# Analysis: choosing NoSQL models for the Konga simulation

The [relational design in Portfolio 1](../../portfolio-1-database-design/docs/design-report.md) provides the foundation for this project, particularly for orders, payments and stock. This portfolio explores whether other database models would make some marketplace tasks easier to handle, such as storing different product attributes, managing short-lived sessions and finding product recommendations.

The sections below explain what each experiment is intended to show. The evidence files have not yet been added, so the timing, stock and result comparisons still need to be completed after the scripts are run.

## 1. Where other database models could help

The relational design works well for data with clear relationships and business rules. Some parts of the marketplace have different needs, which makes them useful cases for exploring NoSQL models.

| Marketplace need | How it affects the relational design | Model explored |
|---|---|---|
| Product attributes vary by category: phones have RAM and network details, while clothing has sizes and colours | A fixed table may need many nullable columns. Alternatives include separate attribute rows or a JSONB column | Documents with a flexible `attributes` object |
| Carts, sessions and counters change frequently, and some records expire | Tables need frequent small updates and a way to remove expired records | Key-value storage with time to live (TTL) |
| Product recommendations follow several connected purchases | SQL needs more joins or recursive queries as the paths become longer | Graph traversal |
| Shipment tracking produces many events, usually read for one shipment at a time | A growing event table needs suitable indexes and a partitioning strategy | Wide-column storage partitioned by shipment; design only |

## 2. What to examine in the experiments

### Document model: FerretDB

A product document can hold the product details, its variants (product variations) and its category-specific attributes together. For example, a new product could include `solar` and `battery_hours` without adding columns to a shared product table. This makes the model useful for a catalogue where different categories need different information.

The experiment compares a filtered product query in FerretDB, with and without a compound index, against the same task using PostgreSQL JSONB. Record the median times from the SUMMARY line in `evidence/01-document-model-output.txt` and explain whether the index helped. The comparison applies to this setup and its 2,000 documents; it should not be treated as a general result for all document databases.

The stock test checks a guarded update to one variant (product variation) inside a product document. Record the stock before and after the update, along with the number of documents matched when the requested quantity exceeds the available stock. This tests an update within one document. It does not establish how a transaction across several documents would behave.

Compatibility also needs checking. Record any operators rejected by the installed FerretDB version and check the results of aggregation pipelines against the expected answers. A query that runs without an error still needs to return the correct result. If the experiment uses MongoDB directly instead, describe that setup and report its results.

### Key-value model: Redis

The Redis experiments use expiring keys for sessions, hashes for carts and a list for recently viewed products. These examples show how a key-value model can represent small pieces of application state without requiring a join.

The flash-sale test starts with one unit in stock and sends 50 simultaneous purchase requests. Compare the number of successful purchases using a separate GET and SET with the number using a Lua script that checks and decrements stock in one atomic operation. The expected result for the atomic version is one successful purchase. Record the actual counts from section 4 of `evidence/02-keyvalue-output.txt`. This tests the same stock rule introduced in Portfolio 1 and explored through concurrent transactions in Portfolio 3.

The cache-aside test compares reading a product page from PostgreSQL with retrieving its cached value from Redis. Record both timings, then compare the time taken for 5,000 requests with and without caching, including the hit rate. A cheap database query may leave little time for a cache to save, so any small improvement needs to be interpreted carefully. The more expensive Portfolio 2 Q8 report provides a second case: compare its cache-miss and cache-hit times to see whether caching makes a clearer difference.

For durability, record whether the test key survives a process crash under each persistence setting. Keep the conclusion limited to the failure that was tested. A process kill alone does not establish how much data would survive a power failure, or fully compare the guarantees of `everysec` and `always`.

### Graph model: LadybugDB

The graph experiment expresses the same recommendation queries in Cypher and SQL. Check that the results match before comparing their execution times; a faster query is only useful if it answers the same question.

For the two-hop and three-hop queries, record the PostgreSQL and LadybugDB median times from section 5 of the graph output. These short paths use about 15,000 edges, so the comparison describes a relatively small graph with fixed-depth queries.

The reachability test then explores paths of length 3, 4 and 6. Compare the times in section 6 and confirm that the result counts match. The recursive SQL version does not use a visited-set shortcut, which may affect its performance. Any advantage for the graph query should therefore be discussed alongside the way each query was written, rather than attributed entirely to the database model.

## 3. How the models fit the marketplace

This table summarises the role each model could play in this project. It is a guide to the design choices, rather than a claim that one model will always outperform another.

| Need | Relational: PostgreSQL | Document | Key-value | Graph | Wide-column |
|---|---|---|---|---|---|
| Orders, payments and stock | Strong fit for related records, transactions and constraints | Depends on transaction support and document boundaries | Useful for supporting operations; needs care for authoritative records | Mainly useful for relationships | Requires careful transaction and consistency design |
| Flexible product attributes | JSONB is an option | Natural fit for varied attributes | Limited querying of attributes | Usually unnecessary | Possible, depending on access patterns |
| Sessions, carts and counters | Supports them, with expiry logic where needed | Possible | Good fit for key-based access and expiry | Usually unnecessary | Possible |
| Relationship traversal | Useful for joins and recursive queries | Less direct for long paths | Limited relationship queries | Natural fit for traversals | Usually requires precomputed relationships |
| Large shipment-event streams | Indexing and partitioning can help | Possible | Useful for selected recent data | Usually unnecessary | Useful candidate for shipment-based access |
| Ad hoc reports across related data | Strong fit for joins and aggregation | Depends on document structure | Usually needs another reporting store | Useful for relationship-based reports | Usually requires query-specific tables |

## 4. Consistency: ACID, BASE and CAP

Study Session 2 introduces ACID, BASE and the CAP trade-off. In this design, orders, payments and stock need reliable transaction handling because an incorrect update could affect a customer's purchase or a seller's payment. PostgreSQL remains responsible for these records.

Some supporting features can tolerate a delay. A recently viewed list or a cached report may briefly show older data without preventing checkout. That makes eventual consistency a possible choice for those features, provided their requirements allow it.

The wide-column shipment-event design considers local quorum writes with three replicas and eventual consistency across data centres. The consistency and availability guarantees would depend on replica placement, read settings and the network failure involved. A local quorum setting alone does not establish how the whole system behaves during a partition.

No multi-node NoSQL cluster is tested here, so these are design considerations. Portfolio 5 examines replication and consistency using PostgreSQL.

## 5. Where NewSQL fits

NewSQL systems aim to combine distributed SQL with ACID transactions. They are relevant to this case study because the marketplace may eventually need to distribute data while keeping transactional operations together.

A distributed SQL system could be considered for the transactional database. Whether it would also replace specialist stores depends on the catalogue, caching and recommendation requirements. No NewSQL system is tested in this portfolio, so there are no measurements to compare. The main questions would be whether the extra scale justifies the operational complexity and the cost of coordinating transactions across nodes.

## 6. Proposed approach

For this project, PostgreSQL remains the source of truth for orders, payments and stock. Redis is a candidate for sessions, carts and cached reports. Product attributes can stay in PostgreSQL JSONB or move to a document model if the experiments show a useful benefit.

A graph database becomes more relevant when recommendations need deeper or variable-length paths. The short recommendation queries should be compared with their SQL equivalents before adding another database to the system. Wide-column storage is a future option if tracking-event volume and access patterns justify it.

The final recommendation should follow the measured results. For each model, the decision needs to account for correctness, performance and the work required to operate another database.
