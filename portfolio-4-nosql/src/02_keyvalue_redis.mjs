#!/usr/bin/env node
// Key-value model for Konga: sessions, carts, counters, leaderboard, flash-sale stock, cache-aside, durability.
// Runs against a real Redis server. Env: REDIS_PORT (default 6380), KONGA_PG_* (database with the seeded products: konga).
import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';
import { createClient } from 'redis';
import pg from 'pg';
import { bench, h, sleep, rng } from './harness.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.REDIS_PORT || 6380);
const connect = async (port) => { const c = createClient({ url: `redis://127.0.0.1:${port}` }); c.on('error', () => {}); await c.connect(); return c; };
const r = await connect(PORT);
await r.flushAll();
const info = await r.info('server');
console.log('Redis server version:', /redis_version:(\S+)/.exec(info)[1]);

h('1. Login session with automatic expiry (TTL)');
await r.set('session:abc123', JSON.stringify({ customer_id: 1, device: 'android' }), { EX: 2 });
console.log('stored; TTL =', await r.ttl('session:abc123'), 's; value:', await r.get('session:abc123'));
await sleep(2500);
console.log('after 2.5 s:', await r.get('session:abc123'), '(expired by itself, no cleanup job)');

h('2. Shopping cart as a hash (field = variant, value = quantity)');
await r.hSet('cart:1', { 4: 1 }); await r.hIncrBy('cart:1', '4', 1); await r.hSet('cart:1', { 1: 1 }); await r.expire('cart:1', 7 * 86400);
console.log('cart:1 =', JSON.stringify(await r.hGetAll('cart:1')), '| TTL days ~', Math.floor((await r.ttl('cart:1')) / 86400));

h('3. Counters, recently viewed list, top-sellers leaderboard');
for (let i = 0; i < 1000; i++) await r.incr('views:product:7');
console.log('views:product:7 =', await r.get('views:product:7'));
for (const pid of [11, 12, 13, 11, 14, 15, 16, 12]) { await r.lRem('recent:1', 0, String(pid)); await r.lPush('recent:1', String(pid)); await r.lTrim('recent:1', 0, 4); }
console.log('recent:1 (newest first, max 5, no duplicates) =', JSON.stringify(await r.lRange('recent:1', 0, -1)));
for (const [seller, sales] of [['s1', 120], ['s2', 340], ['s3', 90], ['s2', 15]]) await r.zIncrBy('top:sellers', sales, seller);
console.log('top sellers =', JSON.stringify((await r.zRangeWithScores('top:sellers', 0, 2, { REV: true })).map((x) => [x.value, x.score])));

h('4. Flash sale: 1 unit left, 50 buyers at once (compare Portfolio 3)');
const LUA = "local s = tonumber(redis.call('GET', KEYS[1])); if s and s > 0 then redis.call('DECR', KEYS[1]); return 1 else return 0 end";
await r.set('stock:flash:3', 1);
const wins = await Promise.all(Array.from({ length: 50 }, () => r.eval(LUA, { keys: ['stock:flash:3'] })));
console.log(`successful purchases = ${wins.reduce((a, b) => a + b, 0)} of 50 attempts; stock left = ${await r.get('stock:flash:3')}`);
// Read stock and write it back separately to reproduce the lost update from Portfolio 3.
await r.set('stock:naive:3', 1);
let naive = 0;
await Promise.all(Array.from({ length: 50 }, async () => {
  const s = Number(await r.get('stock:naive:3'));
  await sleep(10);
  if (s > 0) { await r.set('stock:naive:3', s - 1); naive++; }
}));
console.log(`naive GET-then-SET: successful purchases = ${naive} of 50 (should be 1); stock left = ${await r.get('stock:naive:3')}`);

h('5. Cache-aside for the product page (Redis in front of PostgreSQL)');
const db = new pg.Client({ host: process.env.KONGA_PG_HOST || 'localhost', port: Number(process.env.KONGA_PG_PORT || 5432),
  user: process.env.KONGA_PG_USER || os.userInfo().username, database: process.env.KONGA_DB || 'konga' });
await db.connect();
// Load the UUIDs once, then use each product’s position in this list to model its popularity.
const IDS = (await db.query({ text: 'SELECT product_id FROM konga.products ORDER BY product_id', rowMode: 'array' })).rows.map((x) => x[0]);
const N = IDS.length;
const SQL = `SELECT p.product_id, p.name, p.status, json_agg(json_build_object('sku', v.sku, 'price', v.price, 'stock', i.quantity_in_store))
  FROM konga.products p JOIN konga.product_variants v USING (product_id) JOIN konga.inventory i USING (variant_id)
  WHERE p.product_id = $1 GROUP BY p.product_id`;
const fromPg = async (pid) => (await db.query({ text: SQL, values: [pid], rowMode: 'array' })).rows[0];
async function page(pid, ttl = 60) {
  const k = `page:${pid}`, v = await r.get(k);
  if (v !== null) return [v, true];
  const nv = JSON.stringify(await fromPg(pid));
  await r.set(k, nv, { EX: ttl });
  return [nv, false];
}
const R = rng(5);
const [pm, pp] = await bench(() => fromPg(IDS[R.int(1, N) - 1]), 200);
await r.set('page:hot', 'x'.repeat(600));
const [rm, rp] = await bench(() => r.get('page:hot'), 200);
console.log(`one product page: PostgreSQL median ${pm.toFixed(3)} ms (p95 ${pp.toFixed(3)}); Redis GET median ${rm.toFixed(3)} ms (p95 ${rp.toFixed(3)})`);
// Give a few products a larger share of the requests to model uneven demand.
const cum = []; let tot = 0;
for (let i = 1; i <= N; i++) { tot += 1 / i ** 1.1; cum.push(tot); }
const pick = () => { const x = R() * tot; let lo = 0, hi = N - 1; while (lo < hi) { const m = (lo + hi) >> 1; if (cum[m] < x) lo = m + 1; else hi = m; } return lo + 1; };
const reqs = Array.from({ length: 5000 }, pick);
let t0 = performance.now(); for (const p of reqs) await fromPg(IDS[p - 1]); const tNo = (performance.now() - t0) / 1000;
await r.flushDb(); let hits = 0; t0 = performance.now();
for (const p of reqs) hits += (await page(IDS[p - 1]))[1] ? 1 : 0;
const tCache = (performance.now() - t0) / 1000;
console.log(`5,000 requests with skewed popularity: no cache ${tNo.toFixed(2)} s | cache-aside ${tCache.toFixed(2)} s | hit rate ${(hits / 50).toFixed(1)}% | speed-up ${(tNo / tCache).toFixed(1)}x`);
console.log('finding: see the speed-up above. With a fast, in-memory small catalogue on the same machine a cache miss pays for PostgreSQL plus the Redis write, and a hit saves well under 1 ms, so the gain on a cheap query is small.');
const Q8 = fs.readFileSync(path.join(HERE, '..', '..', 'portfolio-2-query-optimisation', 'sql', 'queries', 'q8_top_customers_lifetime_value.sql'), 'utf8');
async function q8() {
  const k = 'report:top-customers', v = await r.get(k);
  if (v !== null) return true;
  const res = await db.query({ text: Q8, rowMode: 'array' });
  await r.set(k, JSON.stringify(res.rows), { EX: 60 });
  return false;
}
await r.del('report:top-customers'); t0 = performance.now(); await q8(); const tMiss = performance.now() - t0;
const [hm] = await bench(q8, 100, 0);
console.log(`expensive report (Portfolio 2 Q8, a heavy join): first call (miss) ${tMiss.toFixed(1)} ms; later calls (hits) median ${hm.toFixed(3)} ms -> caching pays when the query is expensive and the answer can be a minute old.`);
console.log('cost: after a price change the page can be stale for up to the TTL (60 s) unless the key is deleted on update.');
await db.end();

h('6. Durability: Redis without and with an append-only file (kill -9 test)');
function startRedis(port, extra) {
  execFileSync('redis-server', ['--port', String(port), '--daemonize', 'yes', '--dir', `/tmp/redis-${port}`, '--logfile', `/tmp/redis-${port}/log.txt`, ...extra], { stdio: 'ignore' });
}
async function durability(mode, port, extra) {
  const d = `/tmp/redis-${port}`;
  fs.rmSync(d, { recursive: true, force: true }); fs.mkdirSync(d, { recursive: true });
  startRedis(port, extra); await sleep(700);
  let c = await connect(port);
  await c.set('order:confirmed', 'ORD-1');
  const pid = Number(/process_id:(\d+)/.exec(await c.info('server'))[1]);
  c.disconnect().catch(() => {});
  process.kill(pid, 'SIGKILL'); await sleep(700);
  startRedis(port, extra); await sleep(700);
  c = await connect(port);
  console.log(`${mode.padEnd(36)} after kill -9 and restart, key = ${JSON.stringify(await c.get('order:confirmed'))}`);
  await c.disconnect();
  execFileSync('redis-cli', ['-p', String(port), 'shutdown', 'nosave'], { stdio: 'ignore' });
}
await durability("no persistence (--save '' --appendonly no)", 6391, ['--save', '', '--appendonly', 'no']);
await durability('append-only file, fsync every second', 6392, ['--appendonly', 'yes', '--appendfsync', 'everysec']);
await durability('append-only file, fsync always', 6393, ['--appendonly', 'yes', '--appendfsync', 'always']);
console.log("note: kill -9 only kills the Redis process; the operating system still holds the written bytes, so 'everysec' also survives here. The difference between 'everysec' (can lose about 1 s) and 'always' only shows in a power cut, which I did not test.");
await r.quit();
