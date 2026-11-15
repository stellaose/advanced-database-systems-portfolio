#!/usr/bin/env node
// Compare recommendations written in Cypher with SQL queries over the marketplace relationships from Portfolio 1.
import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import lbug from '@ladybugdb/core';
import pg from 'pg';
import { bench, h, rng } from './harness.mjs';

pg.types.setTypeParser(20, Number);   // bigint (count) -> JS number so it compares with LadybugDB's INT64
const DATA = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'data');
const products = new Map(JSON.parse(fs.readFileSync(path.join(DATA, 'products.json'), 'utf8')).map((p) => [p._id, p]));
const purchases = fs.readFileSync(path.join(DATA, 'purchases.csv'), 'utf8').trim().split('\n').slice(1).map((l) => l.split(',').map(Number));

const tmp = '/tmp/ladybug_p4';
fs.rmSync(tmp, { recursive: true, force: true }); fs.mkdirSync(tmp, { recursive: true });
const csv = (name, rows) => fs.writeFileSync(`${tmp}/${name}.csv`, rows.map((r) => r.join(',')).join('\n') + '\n');
csv('customers', [...new Set(purchases.map((p) => p[0]))].sort((a, b) => a - b).map((c) => [c]));
csv('products', [...products].map(([id, p]) => [id, p.name, p.category]));
csv('purchased', purchases);

const db = new lbug.Database(`${tmp}/db`);
const conn = new lbug.Connection(db);
const norm = (v) => (typeof v === 'bigint' ? Number(v) : v);
// Run Cypher (optionally with parameters) and return rows as arrays of values.
async function cy(q, params) {
  let res;
  if (params) res = await conn.execute(await conn.prepare(q), params);
  else res = await conn.query(q);
  if (Array.isArray(res)) res = res[res.length - 1];
  return (await res.getAll()).map((o) => Object.values(o).map(norm));
}

h('1. Graph schema (nodes and relationships)');
for (const ddl of ['CREATE NODE TABLE Customer(id INT64, PRIMARY KEY(id))',
  'CREATE NODE TABLE Product(id INT64, name STRING, category STRING, PRIMARY KEY(id))',
  'CREATE REL TABLE PURCHASED(FROM Customer TO Product, quantity INT64)']) { console.log(' ', ddl); await conn.query(ddl); }
await conn.query(`COPY Customer FROM '${tmp}/customers.csv'`);
await conn.query(`COPY Product FROM '${tmp}/products.csv'`);
await conn.query(`COPY PURCHASED FROM '${tmp}/purchased.csv'`);
console.log('nodes:', (await cy('MATCH (c:Customer) RETURN count(*)'))[0][0], 'customers,', (await cy('MATCH (p:Product) RETURN count(*)'))[0][0],
  'products | edges:', (await cy('MATCH ()-[r:PURCHASED]->() RETURN count(*)'))[0][0]);

h("2. 'Customers who bought this also bought' (2 hops) in Cypher");
const top = (await cy('MATCH (:Customer)-[:PURCHASED]->(p:Product) RETURN p.id, count(*) AS n ORDER BY n DESC, p.id LIMIT 1'))[0][0];
const CY1 = `MATCH (c:Customer)-[:PURCHASED]->(x:Product {id: $pid}), (c)-[:PURCHASED]->(o:Product)
  WHERE o.id <> x.id RETURN o.id, o.name, count(DISTINCT c) AS together ORDER BY together DESC, o.id LIMIT 5`;
console.log('most-bought product:', top, products.get(top).name);
const rows = await cy(CY1, { pid: top });
for (const r of rows) console.log('  ', JSON.stringify(r));

const CID = (await cy('MATCH (c:Customer)-[:PURCHASED]->(:Product) RETURN c.id, count(*) AS n ORDER BY n DESC, c.id LIMIT 1'))[0][0];
h('3. Recommend for one customer: products bought by customers who share at least 1 product with her, that she has not bought (3 hops)');
const CY2 = `MATCH (me:Customer {id: $cid})-[:PURCHASED]->(shared:Product)<-[:PURCHASED]-(peer:Customer)
  WHERE peer.id <> me.id
  WITH me, peer, count(DISTINCT shared) AS overlap WHERE overlap >= 1
  MATCH (peer)-[:PURCHASED]->(rec:Product) WHERE NOT EXISTS { MATCH (me)-[:PURCHASED]->(rec) }
  RETURN rec.id, rec.name, count(DISTINCT peer) AS score ORDER BY score DESC, rec.id LIMIT 5`;
console.log('customer', CID);
for (const r of await cy(CY2, { cid: CID })) console.log('  ', JSON.stringify(r));

h('4. Same two questions in PostgreSQL (self-joins on a purchases table)');
const pgc = new pg.Client({ host: process.env.KONGA_PG_HOST || 'localhost', port: Number(process.env.KONGA_PG_PORT || 5432),
  user: process.env.KONGA_PG_USER || os.userInfo().username, database: process.env.KONGA_P1_DB || 'konga_p1' });
await pgc.connect();
const sql = async (text, values) => (await pgc.query({ text, values, rowMode: 'array' })).rows.map((r) => r.map(norm));
await pgc.query('DROP SCHEMA IF EXISTS graph_cmp CASCADE; CREATE SCHEMA graph_cmp; CREATE TABLE graph_cmp.purchases (customer_id int, product_id int, quantity int, PRIMARY KEY (customer_id, product_id)); CREATE INDEX ON graph_cmp.purchases (product_id)');
await pgc.query({ text: 'INSERT INTO graph_cmp.purchases SELECT * FROM unnest($1::int[], $2::int[], $3::int[])',
  values: [purchases.map((p) => p[0]), purchases.map((p) => p[1]), purchases.map((p) => p[2])] });
await pgc.query('ANALYZE graph_cmp.purchases');
const SQL1 = `SELECT b.product_id, count(DISTINCT a.customer_id) AS together FROM graph_cmp.purchases a JOIN graph_cmp.purchases b ON b.customer_id = a.customer_id AND b.product_id <> a.product_id
  WHERE a.product_id = $1 GROUP BY b.product_id ORDER BY together DESC, b.product_id LIMIT 5`;
const SQL2 = `WITH peers AS (SELECT p2.customer_id AS peer, count(*) AS overlap FROM graph_cmp.purchases p1 JOIN graph_cmp.purchases p2 ON p2.product_id = p1.product_id AND p2.customer_id <> p1.customer_id
                 WHERE p1.customer_id = $1 GROUP BY p2.customer_id HAVING count(*) >= 1)
  SELECT pu.product_id, count(DISTINCT pu.customer_id) AS score FROM graph_cmp.purchases pu JOIN peers ON peers.peer = pu.customer_id
  WHERE NOT EXISTS (SELECT 1 FROM graph_cmp.purchases m WHERE m.customer_id = $1 AND m.product_id = pu.product_id)
  GROUP BY pu.product_id ORDER BY score DESC, pu.product_id LIMIT 5`;
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sql1 = await sql(SQL1, [top]);
console.log('Q-also-bought SQL result:', JSON.stringify(sql1)); console.log('matches Cypher result:', same(rows.map((r) => [r[0], r[2]]), sql1));
const s2 = await sql(SQL2, [CID]); const c2 = await cy(CY2, { cid: CID });
console.log('Q-recommend SQL result:', JSON.stringify(s2)); console.log('matches Cypher result:', same(c2.map((r) => [r[0], r[2]]), s2));

h('5. Timing (median over 20 random inputs, ms)');
const R = rng(3);
const pids = R.sample([...products.keys()].sort((a, b) => a - b), 20);
const cids = R.sample(Array.from({ length: 2000 }, (_, i) => i + 1), 20);
const timed = (fn, args) => { let i = 0; return bench(() => fn(args[i++ % args.length]), args.length * 4, args.length); };
const [cm, cp] = await timed((p) => cy(CY1, { pid: p }), pids);
const [sm, sp] = await timed((p) => sql(SQL1, [p]), pids);
console.log(`also-bought (2 hops) : LadybugDB/Cypher median ${cm.toFixed(2)} ms (p95 ${cp.toFixed(2)}) | PostgreSQL SQL median ${sm.toFixed(2)} ms (p95 ${sp.toFixed(2)})`);
const [cm2, cp2] = await timed((c) => cy(CY2, { cid: c }), cids);
const [sm2, sp2] = await timed((c) => sql(SQL2, [c]), cids);
console.log(`recommend (3 hops)   : LadybugDB/Cypher median ${cm2.toFixed(2)} ms (p95 ${cp2.toFixed(2)}) | PostgreSQL SQL median ${sm2.toFixed(2)} ms (p95 ${sp2.toFixed(2)})`);

h("6. Reachability: how many customers can be reached from customer CID within k 'shared product' steps");
console.log('(each step = customer -> product -> customer, i.e. 2 edges; PostgreSQL uses a recursive CTE, Cypher uses a shortest-path pattern)');
const cyReach = async (k) => (await cy(`MATCH (a:Customer {id: $c})-[e:PURCHASED* SHORTEST 1..${2 * k}]-(b:Customer) RETURN count(DISTINCT b)`, { c: CID }))[0][0];
const sqlReach = async (k) => (await sql(`WITH RECURSIVE r(customer_id, depth) AS (SELECT $1::int, 0 UNION
    SELECT p2.customer_id, r.depth + 1 FROM r JOIN graph_cmp.purchases p1 ON p1.customer_id = r.customer_id
    JOIN graph_cmp.purchases p2 ON p2.product_id = p1.product_id WHERE r.depth < $2)
    SELECT count(DISTINCT customer_id) - 1 FROM r`, [CID, k]))[0][0];
for (const k of [1, 2, 3, 4, 6]) {
  try {
    const a = await cyReach(k), b = await sqlReach(k);
    const [kc] = await bench(() => cyReach(k), 10, 1), [kp] = await bench(() => sqlReach(k), 10, 1);
    console.log(`  k=${k}: reachable customers Cypher ${a} | SQL ${b} ${a === b ? '(match)' : '(DIFFERENT)'} | LadybugDB ${kc.toFixed(1)} ms | PostgreSQL ${kp.toFixed(1)} ms`);
  } catch (e) { console.log(`  k=${k}: error ${String(e.message).slice(0, 150)}`); }
}
await pgc.query('DROP SCHEMA graph_cmp CASCADE');
await pgc.end();
process.exit(0);
