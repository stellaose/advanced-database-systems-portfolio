-- Found by security_tests.mjs T4: the application role could DELETE customers (and other business records).
-- Konga keeps order and payment history for accounting, so the app role may not delete these rows.
REVOKE DELETE ON konga.customers, konga.orders, konga.order_items, konga.payments, konga.refunds, konga.payouts FROM konga_app;
