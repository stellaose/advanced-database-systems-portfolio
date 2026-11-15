#!/usr/bin/env bash
# Dedicated Portfolio 2 database only: temporarily removes four secondary indexes.
set -euo pipefail
cd "$(dirname "$0")"
export PGDATABASE=${KONGA_PG_DB:-${PGDATABASE:-konga_p2}}
export PGHOST=${KONGA_PG_HOST:-${PGHOST:-/tmp}}
export PGPORT=${KONGA_PG_PORT:-${PGPORT:-5432}}
export PGUSER=${KONGA_PG_USER:-${PGUSER:-${USER}}}
if [ -n "${KONGA_PG_PASSWORD:-}" ]; then export PGPASSWORD=$KONGA_PG_PASSWORD; fi
OUT=${PGBENCH_OUT_DIR:-../../../evidence/experiments/pgbench}
mkdir -p "$OUT"
restore_indexes() {
  psql -X -q -v ON_ERROR_STOP=1 <<'SQL'
SET search_path TO konga;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_orders_customer_placed ON orders (customer_id, placed_at DESC);
CREATE INDEX IF NOT EXISTS idx_reviews_product_created ON reviews (product_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_products_name_trgm ON products USING gin (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_orders_pending_placed ON orders (placed_at) WHERE status = 'pending';
SQL
}
# Restore indexes even if pgbench fails or is interrupted.
trap restore_indexes EXIT
for i in idx_orders_customer_placed idx_reviews_product_created idx_products_name_trgm idx_orders_pending_placed; do
  psql -X -q -v ON_ERROR_STOP=1 -c "DROP INDEX IF EXISTS konga.$i"
done
psql -X -q -v ON_ERROR_STOP=1 -c 'VACUUM ANALYZE konga.orders, konga.reviews, konga.products'
printf '%s\n' '== WITHOUT indexes' | tee "$OUT/e8_without_indexes.txt"
pgbench -n -f workload.sql -c 4 -j 2 -T "${PGBENCH_SECONDS:-20}" 2>&1 | tee -a "$OUT/e8_without_indexes.txt"
restore_indexes
psql -X -q -v ON_ERROR_STOP=1 -c 'VACUUM ANALYZE konga.orders, konga.reviews, konga.products'
printf '%s\n' '== WITH indexes' | tee "$OUT/e8_with_indexes.txt"
pgbench -n -f workload.sql -c 4 -j 2 -T "${PGBENCH_SECONDS:-20}" 2>&1 | tee -a "$OUT/e8_with_indexes.txt"
trap - EXIT
