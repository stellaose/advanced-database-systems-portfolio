# Normalisation walk-through (Konga model)

_Study Session 1: normalisation organises data to reduce redundancy and avoid anomalies by breaking down large tables into smaller related ones. The normal forms are 1NF, 2NF, 3NF and BCNF. Excessive normalisation can increase query complexity, so it has to be balanced against performance._

## Objectives, and how this design meets them

| Objective (study session)                      | How it is met here                                                                                                                                                 |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Eliminate redundancy                           | Customer, seller, brand and category details are stored once and referenced by key                                                                                 |
| Avoid insertion, update and deletion anomalies | A new product can be created before anyone orders it. Renaming a seller changes one row. Deleting an order does not delete the customer                            |
| Ensure data integrity                          | Primary key, foreign key, UNIQUE and CHECK constraints, tested in `../evidence/constraint-tests-output.txt`                                                        |
| Enhance query performance                      | Smaller tables and targeted indexes (Portfolio 2). A few columns are denormalised on purpose; see [section 5](#5-deliberate-exceptions-controlled-denormalisation) |

I used the approach from the study session’s student/course/instructor example: identify which attributes depend on each key, then separate facts that belong to different entities.

I started from the kind of flat "order sheet" a first attempt at the design might produce. I normalised it step by step to 3NF and then checked it against BCNF. The early steps use simplified names to make the dependencies easier to follow. The final implementation is in [`01_schema.sql`](../sql/01_schema.sql).

## 0. Unnormalised form (UNF)

```
ORDER_SHEET(order_id, placed_at, customer_id, customer_name, customer_email, customer_phone,
            shipping_address, coupon_code,
            { variant_sku, product_name, category_name, brand_name, seller_id, seller_name,
              quantity, unit_price },                      <- repeating group
            payment_method, payment_status, shipment_status)
```

Keeping all these details in one sheet creates several problems:

- **Repeating group.** All the order lines (product variations in an order) sit inside one row.
- **Redundancy.** Customer, product and seller details are repeated on every order.
- **Update anomaly.** Changing a seller's name means updating many rows.
- **Deletion anomaly.** Deleting a customer's last order also removes the only stored copy of their details.
- **Insertion anomaly.** A new product cannot be stored until someone orders it.

## 1. First normal form (1NF)

**Rule:** each cell contains one value for its column, and the table has no repeating groups. This is usually described as storing **atomic values**.

In the unnormalised order sheet, one order contains a group of purchased items. To reach 1NF, I remove that repeating group and give each order line (product variation in an order) its own row. An order line (product variation in an order) represents one variant (product variation) within an order. If a customer buys several units of that same version, the `quantity` column records the number of units; they do not need separate rows.

For example, suppose order `1001` contains two black medium T-shirts and one blue large T-shirt. Order `1002` also contains one black medium T-shirt. The item details are stored like this:

| order_id | variant_sku  | product_name | quantity | unit_price |
| -------- | ------------ | ------------ | -------- | ---------- |
| 1001     | TSHIRT-BLK-M | T-shirt      | 2        | 5000.00    |
| 1001     | TSHIRT-BLU-L | T-shirt      | 1        | 5500.00    |
| 1002     | TSHIRT-BLK-M | T-shirt      | 1        | 5000.00    |

Each cell holds one value. There is no list of Stock Keeping Units (SKUs) or quantities inside a cell, and no repeated columns such as `item_1`, `item_2` and `item_3`. This table is only an example of the item columns; the full 1NF relation also includes the order, customer, payment and shipment details shown next.

```
ORDER_LINE(order_id, variant_sku, placed_at, customer_id, customer_name, customer_email,
           customer_phone, shipping_address, coupon_code, product_name, category_name,
           brand_name, seller_id, seller_name, quantity, unit_price,
           payment_method, payment_status, shipment_status)
PK = (order_id, variant_sku)
```

Here, `PK` means **primary key**. The pair `(order_id, variant_sku)` is a **composite primary key**, meaning that the two columns work together to identify a row:

- `order_id` alone is not unique because one order can contain several different items. In the example, order `1001` appears twice.
- `variant_sku` alone is not unique because the same variant (product variation) can appear in different orders. Here, `TSHIRT-BLK-M` appears in orders `1001` and `1002`.
- Together, the order ID and Stock Keeping Unit (SKU) identify one order line (product variation in an order), following the business rule that the same variant (product variation) appears only once per order. Buying more units increases `quantity`.

At this stage, order and customer details still repeat across the rows belonging to the same order. That repetition does not break 1NF: the repeating groups have been removed, but redundant facts remain. The next stage, 2NF, examines which columns depend on the whole composite key and which depend on only part of it.

## 2. Second normal form (2NF)

Rule: the table is in 1NF and has no partial dependency. Every non-key attribute must depend on the whole composite key, not on part of it.

The dependencies below show which columns identify the remaining information in this simplified order sheet:

| Determinant               | Determines                                                                                                    |
| ------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `order_id`                | placed_at, customer_id, customer_name, customer_email, customer_phone, shipping_address, coupon_code, payment_method, payment_status, shipment_status |
| `variant_sku`             | product_name, category_name, brand_name, seller_id, seller_name                                               |
| `(order_id, variant_sku)` | quantity, unit_price                                                                                          |

The quantity and purchase price describe a particular item in a particular order, so they depend on both parts of the key. Order details depend on `order_id`, while catalogue details depend on `variant_sku`. Separating these facts gives three relations:

- `orders(order_id, ...)` holds the facts about the order.
- `product_variants(variant_sku, ...)` holds the facts about the product.
- `order_items(order_id, variant_sku, quantity, unit_price)` holds the facts about one line of one order.

## 3. Third normal form (3NF)

Rule: the table is in 2NF and has no transitive dependency through a non-key attribute. For example, `order_id` identifies a customer, and `customer_id` identifies that customer’s name. Keeping the name in `customers` avoids repeating it in every order.

| Transitive dependency                                                                     | Fix                                                |
| ----------------------------------------------------------------------------------------- | -------------------------------------------------- |
| `order_id -> customer_id -> customer_name, email, phone`                                  | `customers` table; `orders.customer_id` FK         |
| `order_id -> shipping_address` (an address belongs to a customer and is reused)           | `addresses` table; `orders.shipping_address_id` FK |
| `order_id -> coupon_code -> discount details`                                             | `coupons` table                                    |
| `variant -> product -> category_name`                                                     | `categories` (self-referencing for the hierarchy)  |
| `product -> brand_name`                                                                   | `brands` table                                     |
| `product -> seller_id -> seller_name`                                                     | `sellers` table; `products.seller_id` FK           |
| `variant_sku -> product_name` (many variants share one product)                           | `products` split from `product_variants`           |
| `order_id -> payment_method, payment_status` (an order can have several payment attempts) | `payments` (1 order : many payments)               |
| `order_id -> shipment_status` (an order can split per seller, with tracking history)      | `shipments` and `shipment_events`                  |

Cart, inventory, reviews, refunds and payouts did not come out of the order sheet. I modelled them directly as separate entities because each has its own key and its own lifecycle. For example, stock changes independently of price, so `inventory` is separate from `product_variants`.

## 4. Boyce-Codd normal form (BCNF)

Rule: for every non-trivial dependency X -> Y, X must be a superkey.

A superkey is a column, or a combination of columns, that uniquely identifies a row. The BCNF check asks whether every determinant in a non-trivial dependency can identify a row. The following table summarises the keys considered in this design:

| Table                                                            | Candidate keys                                                                           | Result                                                                              |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `customers`                                                      | `customer_id` (PK); `email_address` and `phone_number` (both UNIQUE)                     | Every determinant is a candidate key                                                |
| `sellers`, `brands`, `categories`, `coupons`, `product_variants` | Surrogate PK plus a UNIQUE business key (`email_address`, `name`, `slug`, `code`, `sku`) | Every determinant is a candidate key                                                |
| `order_items`                                                    | `order_item_id`; `(order_id, variant_id)`                                                | `quantity` and `unit_price` depend on the keys and nothing else determines anything |
| `cart_items`                                                     | `(cart_id, variant_id)`                                                                  | The key determines `quantity`                                                       |
| `inventory`                                                      | `variant_id`                                                                             | The key determines `quantity_in_store` and `quantity_reserved`                      |
| `shipments`                                                      | `shipment_id`; `tracking_number`; `(order_id, seller_id)`                                | All are superkeys                                                                   |
| `reviews`                                                        | `review_id`; `(customer_id, product_id)`                                                 | All are superkeys                                                                   |
| `payouts`                                                        | `payout_id`; `(seller_id, period_start, period_end)`                                     | All are superkeys                                                                   |

No table has a determinant that is not a superkey, so the schema is in BCNF.

## 5. Deliberate exceptions (controlled denormalisation)

Normalisation reduces repeated facts, but the design also needs to preserve purchase history and support frequent calculations. The following columns need some explanation: some store historical facts, while others store calculated or maintained values.

| Column                        | Why it is kept                                                                                                                   | How correctness is protected                                                          |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `order_items.unit_price`      | It records the price **at the time of purchase**, and `product_variants.price` can change later                 | `CHECK (unit_price >= 0)`                                                             |
| `orders.total_amount`         | It can be derived from the items and the coupon. Storing it keeps historical orders stable and saves reports from re-aggregating | `CHECK (total_amount >= 0)`; in Portfolio 3 it is set inside the checkout transaction |
| `payouts.net_amount`          | It can be derived as `gross_sales - commission`. It is stored as the amount actually paid                                        | Generated column: `gross_sales - commission`                                       |
| `inventory.quantity_reserved` | It could be computed from open orders. It is stored so availability checks are fast                                              | `CHECK (quantity_reserved <= quantity_in_store)`                                      |

## 6. Design decisions worth explaining

- **Surrogate keys.** Most entities use a UUID stored as `VARCHAR(36)` for their primary key. `cart_items` uses a composite key, while `inventory` shares the product variation’s key. The business keys (email address, phone numbers for a customer, Stock Keeping Unit (SKU), tracking number) are kept as `UNIQUE`.
- **Referential actions.** I used `ON DELETE CASCADE` only for dependent records: addresses, cart items, shipment events and reviews. Master and history tables such as categories, sellers and orders use the default restrictive behaviour, so history cannot be deleted by accident (see test T11).
- **Partial unique indexes.** These enforce two business rules that a plain UNIQUE cannot: one default address per customer and one open cart per customer.
- **Money.** Amounts are `NUMERIC(12,2)`, never floating point, so the arithmetic is exact.
- **Shipments per seller.** One order can contain items from several sellers, so shipments are unique on `(order_id, seller_id)`.
- **Per-category product attributes.** Attributes such as RAM, size and colour are left out of the relational model on purpose. They vary too much from one category to the next and are modelled as documents in Portfolio 4.
