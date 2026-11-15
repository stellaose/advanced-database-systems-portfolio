#!/usr/bin/env node
// Horizontal fragmentation (sharding by region) with postgres_fdw (Portfolio 5; Study Session 2: 2.1.4.1 data fragmentation, 2.1.3 federated architecture).
//
// Three databases on ONE PostgreSQL server stand for three machines: shard_lagos, shard_abuja (each holds its region's orders)
// and konga_coord (the coordinator; it holds only foreign tables and the partitioned parent `orders`).
// Honest limit: all three are on one machine, so there is no real network delay; communication cost shows up only as
// row transfer and protocol overhead. Env: PG_HOST (default localhost), PG_PORT (5432), PG_USER (your OS user). Needs superuser (CREATE EXTENSION).
import os from 'node:os';
import pg from 'pg';

pg.types.setTypeParser(20, Number);
const H = process.env.PG_HOST || 'localhost', P = process.env.PG_PORT || '5432', U = process.env.PG_USER || os.userInfo().username;
const clients = [];
async function conn(db) { const c = new pg.Client({ host: H, port: Number(P), user: U, database: db }); await c.connect(); clients.push(c); return c; }
const rows = async (c, sql) => (await c.query({ text: sql, rowMode: 'array' })).rows;
const say = (m = '') => console.log(m);
const head = (c, t) => { say(); say('='.repeat(96)); say(`${c}. ${t}`); say('='.repeat(96)); };
const median = (a) => { const s = [...a].sort((x, y) => x - y), m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
const now = () => Number(process.hrtime.bigint()) / 1e6;
async function ms(c, sql, runs = 5) {
  const t = [];
  for (let i = 0; i <= runs; i++) { const s = now(); await rows(c, sql); t.push(now() - s); }
  return median(t.slice(1));
}
const plan = async (c, sql) => (await rows(c, 'EXPLAIN (VERBOSE, COSTS OFF) ' + sql)).map((r) => r[0]);

const adm = await conn('postgres');
for (const d of ['shard_lagos', 'shard_abuja', 'konga_coord', 'konga_central']) {
  await adm.query(`DROP DATABASE IF EXISTS ${d} WITH (FORCE)`); await adm.query(`CREATE DATABASE ${d}`);
}

head('S0', 'Build: 2 shards x 200,000 orders, one coordinator, one centralised copy for comparison');
const DDL = 'CREATE TABLE orders (order_id bigint, customer_id int, region text NOT NULL, status text, total_amount numeric(14,2), placed_at timestamptz, PRIMARY KEY (order_id, region))';
const FILL = (base, region) => `INSERT INTO orders SELECT ${base} + g, (g % 5000) + 1, '${region}', (ARRAY['pending','paid','shipped','delivered','cancelled'])[1 + (g % 5)],
  (1000 + (g * 37) % 90000)::numeric, now() - (g % 365) * interval '1 day' FROM generate_series(1, 200000) g`;
for (const [db, region, base] of [['shard_lagos', 'Lagos', 0], ['shard_abuja', 'Abuja', 1_000_000]]) {
  const c = await conn(db); await c.query(DDL); await c.query(FILL(base, region));
  await c.query('CREATE INDEX ON orders (customer_id)'); await c.query('ANALYZE orders');
  say(`  ${db}: ${region} orders loaded`);
}
const cen = await conn('konga_central'); await cen.query(DDL);
await cen.query(FILL(0, 'Lagos')); await cen.query(FILL(1_000_000, 'Abuja'));
await cen.query('CREATE INDEX ON orders (customer_id)'); await cen.query('CREATE INDEX ON orders (region)'); await cen.query('ANALYZE orders');
say('  konga_central: all 400,000 orders in one database (the centralised baseline)');

const cc = await conn('konga_coord');
await cc.query('CREATE EXTENSION postgres_fdw');
for (const db of ['shard_lagos', 'shard_abuja']) {
  await cc.query(`CREATE SERVER ${db} FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host '${H}', port '${P}', dbname '${db}', use_remote_estimate 'true')`);
  await cc.query(`CREATE USER MAPPING FOR CURRENT_USER SERVER ${db} OPTIONS (user '${U}')`);
}
await cc.query('CREATE TABLE orders (order_id bigint, customer_id int, region text NOT NULL, status text, total_amount numeric(14,2), placed_at timestamptz) PARTITION BY LIST (region)');
await cc.query("CREATE FOREIGN TABLE orders_lagos PARTITION OF orders FOR VALUES IN ('Lagos') SERVER shard_lagos OPTIONS (table_name 'orders')");
await cc.query("CREATE FOREIGN TABLE orders_abuja PARTITION OF orders FOR VALUES IN ('Abuja') SERVER shard_abuja OPTIONS (table_name 'orders')");
await cc.query("CREATE TABLE customers AS SELECT g AS customer_id, 'Customer ' || g AS name, CASE WHEN g % 2 = 0 THEN 'Lagos' ELSE 'Abuja' END AS home_region FROM generate_series(1, 5000) g");
await cc.query('ANALYZE customers');
say('  konga_coord: partitioned parent orders (LIST by region) with two foreign partitions; 5,000 customers stored locally');

head('S1', 'Location transparency: one query on the parent table reads both shards');
say(`  SELECT region, count(*) FROM orders GROUP BY region -> ${JSON.stringify(await rows(cc, 'SELECT region, count(*) FROM orders GROUP BY region ORDER BY 1'))}`);

head('S2', 'Partition pruning: a query that names the region only contacts one shard');
for (const line of await plan(cc, "SELECT count(*), sum(total_amount) FROM orders WHERE region = 'Lagos'")) say('  ' + line);
say('  -> only orders_lagos appears; the Abuja shard is never contacted.');

head('S3', 'Communication cost: how much work is pushed to the shard (aggregate pushdown on/off)');
const AGG = 'SELECT region, status, count(*), sum(total_amount) FROM orders GROUP BY region, status';
const res = {};
for (const flag of ['on', 'off']) {
  await cc.query(`SET enable_partitionwise_aggregate = ${flag}`); res[flag] = await ms(cc, AGG);
  const p = await plan(cc, AGG); say(`  enable_partitionwise_aggregate = ${flag}: median ${res[flag].toFixed(1)} ms`);
  const l = p.find((x) => x.includes('Remote SQL')); if (l) say('      ' + l.trim().slice(0, 230));
}
await cc.query('RESET enable_partitionwise_aggregate');
say(`  -> pushing the GROUP BY to the shards is ${(res.off / res.on).toFixed(1)}x faster than pulling 400,000 rows and aggregating on the coordinator.`);

head('S4', 'Distributed vs centralised: the same business query on 400,000 orders');
const Q = {
  'A. total revenue in Lagos (pruned to one shard)': "SELECT sum(total_amount) FROM orders WHERE region = 'Lagos'",
  'B. revenue by region (aggregate, both shards)': 'SELECT region, sum(total_amount) FROM orders GROUP BY region',
  'C. top 5 customers by spend (join with local customers table)': 'SELECT c.customer_id, c.name, sum(o.total_amount) s FROM orders o JOIN customers c USING (customer_id) GROUP BY 1, 2 ORDER BY s DESC LIMIT 5',
  "D. one customer's orders (point lookup, no region given)": 'SELECT order_id, total_amount FROM orders WHERE customer_id = 77 ORDER BY placed_at DESC LIMIT 20',
};
await cen.query("CREATE TABLE IF NOT EXISTS customers AS SELECT g AS customer_id, 'Customer ' || g AS name FROM generate_series(1, 5000) g");
say(`  ${'query'.padEnd(66)}${'centralised ms'.padStart(16)}${'distributed ms'.padStart(16)}${'ratio'.padStart(8)}`);
for (const [k, sql] of Object.entries(Q)) {
  const a = await ms(cen, sql), b = await ms(cc, sql);
  say(`  ${k.padEnd(66)}${a.toFixed(1).padStart(16)}${b.toFixed(1).padStart(16)}${(b / a).toFixed(1).padStart(7)}x`);
}
await cc.query('SET enable_partitionwise_aggregate = on');
for (const k of ['A. total revenue in Lagos (pruned to one shard)', 'B. revenue by region (aggregate, both shards)']) {
  const a = await ms(cen, Q[k]), b = await ms(cc, Q[k]);
  say(`  ${(k.slice(0, 3) + ' with enable_partitionwise_aggregate = on').padEnd(66)}${a.toFixed(1).padStart(16)}${b.toFixed(1).padStart(16)}${(b / a).toFixed(1).padStart(7)}x`);
}
await cc.query('RESET enable_partitionwise_aggregate');
say("  Rows A to D above ran with PostgreSQL's default settings (aggregate pushdown OFF); the two extra rows show the same queries with pushdown on.");
say('  Query D has no region in its WHERE clause, so it must ask BOTH shards. Query C must pull rows to the coordinator to join with its local table.');

head('S5', 'Partial availability: one shard unreachable');
await cc.query("ALTER SERVER shard_abuja OPTIONS (SET port '5999')");
say(`  Abuja shard down. Query on Lagos only: works, count = ${(await rows(cc, "SELECT count(*) FROM orders WHERE region = 'Lagos'"))[0][0]}`);
try { await cc.query('SELECT count(*) FROM orders'); say('  query on all regions: returned'); }
catch (e) { say(`  query on all regions: fails -> ${e.message.split('\n')[0].slice(0, 120)}`); }
await cc.query(`ALTER SERVER shard_abuja OPTIONS (SET port '${P}')`);
say(`  shard back: query on all regions works again, count = ${(await rows(cc, 'SELECT count(*) FROM orders'))[0][0]}`);

head('S6', 'Atomicity across shards (what this setup does NOT give you)');
say('  postgres_fdw commits each remote transaction one after another when the coordinator commits; it does not use two-phase commit.');
say('  Portfolio 3 showed PREPARE TRANSACTION / COMMIT PREPARED for a true two-phase commit. I did not test a failure between the two shard commits here.');
for (const c of clients) await c.end().catch(() => {});
