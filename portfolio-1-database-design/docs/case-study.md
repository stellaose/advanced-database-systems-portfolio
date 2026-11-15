# Case study: Konga 

This project uses a simulated marketplace based on Konga to explore the five portfolio tasks. The root README gives the full case study, including the organisation, its customers, the data it handles and its main operations.

## Scope of the simulated model

Konga brings several sellers together in one marketplace. Sellers list their products, customers place orders and pay, and either Konga logistics or the seller handles delivery.

For this project, the database covers the product catalogue, stock, shopping carts, checkout, orders, payments, shipments, reviews and seller payouts. All data is synthetic. The model is an academic exercise and does not describe Konga's actual database.

## Why it suits the five portfolio tasks

- **P1/P2: Database design and query optimisation.** Customers, sellers, products and orders are closely related, giving the design clear examples of table relationships and joins. The catalogue and order data can also be expanded to more than 100,000 rows to compare indexes and query execution plans.
- **P3: Transactions and concurrency.** Checkout involves several related steps, including reserving stock, processing payment, creating an order and arranging a shipment. If two customers try to buy the last unit at the same time, the database must handle the competing requests without overselling.
- **P4: NoSQL models.** Different product categories need different attributes: a phone may have a storage capacity, while clothing has a size. This provides a useful case for a document model. Carts and sessions can be explored with key-value storage, while product recommendations can be explored with a graph model.
- **P5: Distributed databases.** Sales events can bring sudden increases in traffic. This makes the marketplace a useful setting for examining read replicas, sharding by seller or region, and the trade-offs between availability and consistency.

## Candidate entities (draft, to refine in P1)

The starting set of entities covers customers and their addresses, sellers, the product catalogue, stock and the records created during a purchase. These are represented by the following candidate tables:

`customers`, `addresses`, `sellers`, `categories`, `brands`, `products`, `product_variants`, `inventory`, `carts`, `cart_items`, `orders`, `order_items`, `payments`, `refunds`, `shipments`, `shipment_events`, `reviews`, `coupons` and `payouts`.

## Sources

The business description draws on the Konga seller handbook and public coverage from Techpoint and Entrepreneurs.ng. All data in this repository is synthetic.
