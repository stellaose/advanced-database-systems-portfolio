
set -u
cd "$(dirname "$0")/.."
BIN=/usr/lib/postgresql/16/bin
PGDATA=/tmp/pgdata
PSQL="psql -h /tmp -p 5433 -U pgrun -X -q"
start()  { for i in 1 2 3 4 5 6; do su pgrun -c "$BIN/pg_ctl -D $PGDATA -o '-p 5433 -k /tmp' -l /tmp/pg.log start -w" >/dev/null 2>&1 && return; sleep 2; done; echo "server did not start"; }
crash()  { pkill -9 -u pgrun -x postgres; for i in $(seq 1 20); do pgrep -u pgrun -x postgres >/dev/null || break; sleep 0.5; done; echo "   >> server killed with SIGKILL (no clean shutdown, no checkpoint)"; }
OUT=evidence
say()    { echo; echo "### $*"; }

enable_prepared() {
  if ! grep -q '^max_prepared_transactions' $PGDATA/postgresql.conf; then
    echo "max_prepared_transactions = 5" >> $PGDATA/postgresql.conf
    su pgrun -c "$BIN/pg_ctl -D $PGDATA -o '-p 5433 -k /tmp' -l /tmp/pg.log restart -w" >/dev/null
  fi
}
enable_prepared
$PSQL -d konga_p3 -f sql/00_reset_state.sql

{
echo "DURABILITY TEST  ($(date -u +%F\ %T) UTC)"
say "1. Commit one change; start a second change and leave it uncommitted"
$PSQL -d konga_p3 -c "SET search_path=konga; BEGIN; UPDATE inventory SET quantity_in_store = 111 WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a'; COMMIT;"
echo "   committed: variant 4 on_hand set to 111"
( $PSQL -d konga_p3 -c "SET search_path=konga; BEGIN; UPDATE inventory SET quantity_in_store = 222 WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a'; SELECT pg_sleep(120);" >/dev/null 2>&1 & )
sleep 2
echo "   uncommitted: a second session has set it to 222 but not committed (visible only to itself)"
$PSQL -d konga_p3 -t -c "SELECT 'before crash, other sessions see: ' || quantity_in_store FROM konga.inventory WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a'"
say "2. Crash the server"
crash
say "3. Restart and look at what survived"
start
$PSQL -d konga_p3 -t -c "SELECT 'after crash recovery: ' || quantity_in_store || '  (111 = committed change kept, 222 = uncommitted change lost)' FROM konga.inventory WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a'"
echo "   server log lines from recovery:"
grep -E "not properly shut down|redo starts|redo done|database system is ready" /tmp/pg.log | tail -4 | sed 's/^/   /'
} > $OUT/03-durability-test.txt 2>&1
cat $OUT/03-durability-test.txt

# ---------------------------------------------------------------- two-phase commit
$PSQL -d postgres -c "DROP DATABASE IF EXISTS konga_pay" -c "CREATE DATABASE konga_pay"
$PSQL -d konga_pay -c "CREATE TABLE ledger (entry_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, order_ref text NOT NULL UNIQUE, amount numeric(14,2) NOT NULL CHECK (amount > 0), status text NOT NULL)"
$PSQL -d konga_p3 -f sql/00_reset_state.sql
{
echo "TWO-PHASE COMMIT TEST  ($(date -u +%F\ %T) UTC)"
echo "Two databases stand for two services: konga_p3 (orders + stock) and konga_pay (payment ledger)."
echo "Goal: 'reserve stock + create order' and 'record payment' must both happen or neither."

say "CASE 1: both participants vote YES, coordinator commits both"
$PSQL -d konga_p3 <<'SQL'
SET search_path = konga;
BEGIN;
INSERT INTO orders (customer_id, shipping_address_id, total_amount) VALUES ('bceec3c5-c731-4fb2-a8f0-5066b1f987d9', '3b91ba08-d10e-46c6-bd68-e2cdf722b92c', 1.00);
UPDATE inventory SET quantity_reserved = quantity_reserved + 1 WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a';
PREPARE TRANSACTION 'order_tx_1';
SQL
$PSQL -d konga_pay -c "BEGIN; INSERT INTO ledger (order_ref, amount, status) VALUES ('ORD-1', 18500, 'captured'); PREPARE TRANSACTION 'pay_tx_1';"
echo "   Phase 1 done: both branches PREPARED (promise to commit, nothing visible yet)."
$PSQL -d konga_p3 -c "SELECT 'orders branch sees test orders: ' || count(*) FROM konga.orders WHERE total_amount = 1.00" -t
$PSQL -d konga_p3 -c "SELECT gid, database FROM pg_prepared_xacts"
$PSQL -d konga_pay -c "SELECT gid, database FROM pg_prepared_xacts"
echo "   While prepared, the locks are still held. Another session tries to change the same stock row (lock_timeout 1s):"
$PSQL -d konga_p3 -c "SET lock_timeout='1s'; UPDATE konga.inventory SET quantity_reserved = quantity_reserved WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a'" 2>&1 | head -1 | sed 's/^/   /'
echo "   Phase 2: coordinator commits both."
$PSQL -d konga_p3 -c "COMMIT PREPARED 'order_tx_1'"
$PSQL -d konga_pay -c "COMMIT PREPARED 'pay_tx_1'"
$PSQL -d konga_p3 -t -c "SELECT 'orders: ' || count(*) || ' test order(s), variant 4 reserved = ' || (SELECT quantity_reserved FROM konga.inventory WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a') FROM konga.orders WHERE total_amount = 1.00"
$PSQL -d konga_pay -t -c "SELECT 'ledger: ' || count(*) || ' entry' FROM ledger"

say "CASE 2: second participant votes NO (payment rejected); coordinator rolls back the first"
$PSQL -d konga_p3 <<'SQL'
SET search_path = konga;
BEGIN;
INSERT INTO orders (customer_id, shipping_address_id, total_amount) VALUES ('4cb025ea-36e9-4b9f-8c44-0475cf012951', 'a69034f9-5dac-4987-b5d8-576114135d44', 1.00);
UPDATE inventory SET quantity_reserved = quantity_reserved + 1 WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a';
PREPARE TRANSACTION 'order_tx_2';
SQL
echo "   orders branch: PREPARED (vote yes)"
$PSQL -d konga_pay -c "BEGIN; INSERT INTO ledger (order_ref, amount, status) VALUES ('ORD-2', 0, 'captured'); PREPARE TRANSACTION 'pay_tx_2';" 2>&1 | head -1 | sed 's/^/   payment branch: /'
echo "   payment branch could not prepare (vote no). Coordinator aborts the prepared orders branch:"
$PSQL -d konga_p3 -c "ROLLBACK PREPARED 'order_tx_2'"
$PSQL -d konga_p3 -t -c "SELECT 'orders: ' || count(*) || ' test order(s) (still 1 from case 1), variant 4 reserved = ' || (SELECT quantity_reserved FROM konga.inventory WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a') FROM konga.orders WHERE total_amount = 1.00"
$PSQL -d konga_pay -t -c "SELECT 'ledger: ' || count(*) || ' entry (still 1 from case 1)' FROM ledger"

say "CASE 3: crash while both branches are prepared (the 'in-doubt' state)"
$PSQL -d konga_p3 <<'SQL'
SET search_path = konga;
BEGIN;
INSERT INTO orders (customer_id, shipping_address_id, total_amount) VALUES ('b5e50a05-94b8-4b5a-9c3c-1dfe6f16c3a1', '631503e3-8d01-453b-8dc1-a534e595f818', 1.00);
UPDATE inventory SET quantity_reserved = quantity_reserved + 1 WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a';
PREPARE TRANSACTION 'order_tx_3';
SQL
$PSQL -d konga_pay -c "BEGIN; INSERT INTO ledger (order_ref, amount, status) VALUES ('ORD-3', 18500, 'captured'); PREPARE TRANSACTION 'pay_tx_3';"
echo "   both branches prepared; now the server crashes before the coordinator can send COMMIT."
crash
start
echo "   after restart, the prepared transactions are still there (they were written to the WAL):"
$PSQL -d konga_p3 -c "SELECT gid, database FROM pg_prepared_xacts ORDER BY gid"
$PSQL -d konga_p3 -t -c "SELECT 'visible orders: ' || count(*) || ' (only case 1; case 3 order is still invisible because it is not committed)' FROM konga.orders WHERE total_amount = 1.00"
echo "   coordinator recovers and finishes phase 2:"
$PSQL -d konga_p3 -c "COMMIT PREPARED 'order_tx_3'"
$PSQL -d konga_pay -c "COMMIT PREPARED 'pay_tx_3'"
$PSQL -d konga_p3 -t -c "SELECT 'orders: ' || count(*) || ' test orders, variant 4 reserved = ' || (SELECT quantity_reserved FROM konga.inventory WHERE variant_id = '2ad24f49-d621-4d7c-a124-ae758543e76a') FROM konga.orders WHERE total_amount = 1.00"
$PSQL -d konga_pay -t -c "SELECT 'ledger: ' || count(*) || ' entries' FROM ledger"
$PSQL -d konga_p3 -t -c "SELECT 'prepared transactions left: ' || count(*) FROM pg_prepared_xacts"
} > $OUT/04-two-phase-commit.txt 2>&1
cat $OUT/04-two-phase-commit.txt
$PSQL -d konga_p3 -f sql/00_reset_state.sql
