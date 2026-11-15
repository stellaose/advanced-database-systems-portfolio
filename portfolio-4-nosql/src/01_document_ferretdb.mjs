#!/usr/bin/env node
// Document model for the Konga product catalogue.
// Runs against FerretDB (MongoDB wire protocol, data stored in PostgreSQL) via the official mongodb driver. NOT real MongoDB.
// Also runs the same query on PostgreSQL JSONB for comparison. Env: MONGO_URI, KONGA_PG_* (database konga_p1).
import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { MongoClient } from 'mongodb';
import pg from 'pg';
import { bench, h } from './harness.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const docs = JSON.parse(fs.readFileSync(path.join(HERE, '..', 'data', 'products.json'), 'utf8'));
const cli = new MongoClient(process.env.MONGO_URI || 'mongodb://127.0.0.1:27017');
await cli.connect();
const col = cli.db('konga_nosql').collection('products');
await col.drop().catch(() => {});
const f2 = (x) => x.toFixed(2);

h('1. Load the catalogue as documents (variants and attributes embedded)');
await col.insertMany(docs);
console.log('documents:', await col.countDocuments({}));
console.log('one document:', JSON.stringify(await col.findOne({ category: 'Phones' }), null, 1).slice(0, 700), '...');

h('2. Flexible schema: category-specific attributes, no ALTER TABLE');
await col.insertOne({ _id: 99001, seller_id: 7, name: 'Solar Lantern 99001', brand: 'SunKing', category: 'Appliances', status: 'live',
  attributes: { power_w: 5, solar: true, battery_hours: 12 }, variants: [{ sku: 'P99001-V1', price: 8500, stock: 30 }],
  tags: ['new'], rating_avg: 4.2, rating_count: 11 });
console.log('inserted a product with brand-new attributes (solar, battery_hours); nothing else changed:',
  JSON.stringify(await col.findOne({ _id: 99001 }, { projection: { attributes: 1 } })));
await col.deleteOne({ _id: 99001 });

const Q = { category: 'Phones', status: 'live', 'attributes.ram_gb': { $gte: 8 }, 'attributes.network': '5G', 'variants.price': { $lte: 300000 } };
const { 'variants.price': _drop, ...Q2 } = Q;                      // same without the array condition
const qMongo = () => col.find(Q).sort({ rating_avg: -1 }).limit(20).toArray();
const qMongo2 = () => col.find(Q2).sort({ rating_avg: -1 }).limit(20).toArray();

h('3. Query: live 5G phones with at least 8 GB RAM under N300,000, best rated first');
const res = await qMongo();
console.log('rows returned:', res.length, '| first:', res[0].name, JSON.stringify(res[0].attributes), res[0].rating_avg);
const [m0, p0] = await bench(qMongo); console.log(`no secondary index : median ${f2(m0)} ms, p95 ${f2(p0)} ms`);
const [n0, r0] = await bench(qMongo2); console.log(`  (without the variants.price condition) no index: median ${f2(n0)} ms, p95 ${f2(r0)} ms`);
await col.createIndex({ category: 1, 'attributes.network': 1, 'attributes.ram_gb': 1 }, { name: 'ix_cat_net_ram' });
const [m1, p1] = await bench(qMongo); console.log(`compound index     : median ${f2(m1)} ms, p95 ${f2(p1)} ms`);
const [n1, r1] = await bench(qMongo2); console.log(`  (without the variants.price condition) index   : median ${f2(n1)} ms, p95 ${f2(r1)} ms`);
console.log('indexes:', JSON.stringify((await col.listIndexes().toArray()).map((i) => i.name)));

h('4. Atomic update inside ONE document (stock decrement of a variant, guarded)');
console.log('note: FerretDB 1.x does not support $elemMatch with field conditions, so the guard addresses the variant by array position; on real MongoDB $elemMatch with the positional operator is the safer form.');
const before = (await col.findOne({ _id: 1 }, { projection: { variants: 1 } })).variants[0];
let r = await col.updateOne({ _id: 1, 'variants.0.stock': { $gte: 1 } }, { $inc: { 'variants.0.stock': -1 } });
const after = (await col.findOne({ _id: 1 }, { projection: { variants: 1 } })).variants[0];
console.log(`matched=${r.matchedCount} modified=${r.modifiedCount}; stock ${before.stock} -> ${after.stock}`);
r = await col.updateOne({ _id: 1, 'variants.0.stock': { $gte: 10 ** 6 } }, { $inc: { 'variants.0.stock': -1 } });
console.log(`guard fails when stock is too low: matched=${r.matchedCount} (nothing changed)`);

h('5. Aggregation pipeline: live products and average rating per category (analytics inside the store)');
// FerretDB 1.x quirk found while testing: a $group with TWO $sum accumulators returns 0 for the second one (silent wrong answer),
// so each sum is computed in its own pipeline and combined in JavaScript.
async function groupSum(expr) {
  const out = await col.aggregate([{ $match: { status: 'live' } }, { $group: { _id: '$category', v: { $sum: expr } } }]).toArray();
  return Object.fromEntries(out.map((x) => [x._id, x.v]));
}
const counts = await groupSum(1), rsum = await groupSum('$rating_avg');
for (const cat of Object.keys(counts).sort())
  console.log(' ', JSON.stringify({ category: cat, live_products: counts[cat], avg_rating: Math.round((rsum[cat] / counts[cat]) * 100) / 100 }));
const bad = (await col.aggregate([{ $match: { status: 'live' } }, { $group: { _id: '$category', n: { $sum: 1 }, rating_total: { $sum: '$rating_avg' } } }, { $sort: { _id: 1 } }]).toArray())[0];
console.log('  compatibility gap (kept as evidence): one pipeline with two $sum gives', JSON.stringify({ n: bad.n, rating_total: bad.rating_total }),
  '(rating_total should be about', (Math.round(rsum[bad._id] * 10) / 10), ')');
console.log('  $avg, $max, $min, $addToSet and $elemMatch with field conditions are also not implemented in FerretDB 1.x; real MongoDB supports them.');

h('6. Same query on PostgreSQL JSONB (relational engine, document column)');
const db = new pg.Client({ host: process.env.KONGA_PG_HOST || 'localhost', port: Number(process.env.KONGA_PG_PORT || 5432),
  user: process.env.KONGA_PG_USER || os.userInfo().username, database: process.env.KONGA_P1_DB || 'konga_p1' });
await db.connect();
await db.query('DROP SCHEMA IF EXISTS nosql_cmp CASCADE; CREATE SCHEMA nosql_cmp; CREATE TABLE nosql_cmp.products (id int PRIMARY KEY, doc jsonb NOT NULL)');
await db.query({ text: "INSERT INTO nosql_cmp.products SELECT (d->>'_id')::int, d FROM jsonb_array_elements($1::jsonb) d", values: [JSON.stringify(docs)] });
await db.query('ANALYZE nosql_cmp.products');
const SQL = `SELECT doc->>'name', (doc->'attributes'->>'ram_gb')::int, doc->>'rating_avg' FROM nosql_cmp.products
  WHERE doc->>'category' = 'Phones' AND doc->>'status' = 'live' AND (doc->'attributes'->>'ram_gb')::int >= 8
    AND doc->'attributes'->>'network' = '5G'
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(doc->'variants') v WHERE (v->>'price')::numeric <= 300000)
  ORDER BY (doc->>'rating_avg')::numeric DESC LIMIT 20`;
const qPg = async () => (await db.query({ text: SQL, rowMode: 'array' })).rows;
const rows = await qPg();
console.log('rows returned:', rows.length, '| first:', JSON.stringify(rows[0]));
const [a0, b0] = await bench(qPg); console.log(`JSONB, no index          : median ${f2(a0)} ms, p95 ${f2(b0)} ms`);
await db.query('CREATE INDEX ix_doc_gin ON nosql_cmp.products USING gin (doc jsonb_path_ops)');
await db.query("CREATE INDEX ix_cat_net ON nosql_cmp.products ((doc->>'category'), (doc->'attributes'->>'network'))");
await db.query('ANALYZE nosql_cmp.products');
const [a1, b1] = await bench(qPg); console.log(`JSONB, expression index  : median ${f2(a1)} ms, p95 ${f2(b1)} ms`);
console.log(`\nSUMMARY (median ms)  FerretDB no-index ${f2(m0)} | FerretDB index ${f2(m1)} | FerretDB w/o price cond: no-index ${f2(n0)}, index ${f2(n1)} | PG JSONB no-index ${f2(a0)} | PG JSONB index ${f2(a1)}`);
await db.query('DROP SCHEMA nosql_cmp CASCADE');
await db.end();
await cli.close();
