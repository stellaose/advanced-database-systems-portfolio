# Mapping the marketplace data to NoSQL models

The [Portfolio 1 design](../../portfolio-1-database-design/docs/design-report.md) is the starting point for these choices. The table explains which parts remain relational and which could benefit from a different model. Each choice follows the way the data is read or updated.

| Konga data | Relational design (Portfolio 1) | NoSQL model chosen | Why |
|---|---|---|---|
| Product catalogue (products, variants, brand, category-specific attributes) | Products, product variations, brands and categories; category-specific attributes are explored here | **Document**: one document per product, variants embedded, free-form `attributes` | Attributes differ by category; the page reads one product at a time |
| Order history snapshot | orders + order_items | Document (items embedded, price frozen at purchase) | The purchased items and their prices can be read together as a historical snapshot |
| Orders, payments, stock, payouts | normalised tables with constraints | **Stay relational (PostgreSQL)** | Need ACID, constraints and joins (Portfolio 3) |
| Login sessions, carts, view counters, recently viewed, leaderboard | carts + cart_items tables | **Key-value (Redis)** | Access by key and expiry handling; persistence requirements still need to be defined |
| "Customers also bought", recommendations | self-joins over order_items | **Graph (LadybugDB / Cypher)** | Multi-hop questions about relationships |
| Shipment tracking events | shipment_events | **Wide-column (Cassandra), design only** | Huge append-only time series, read by shipment or by hub and day |
