#!/usr/bin/env node
// Security tests for Konga (Study Session 3, 3.2.2 database security: confidentiality, integrity, availability; least privilege; injection).
// Uses the konga_p1 database and the roles from Portfolio 1 (sql/04_physical_design.sql). Env: PG_HOST/PG_PORT/PG_DB/PG_USER.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const H = process.env.PG_HOST || 'localhost', P = Number(process.env.PG_PORT || 5432), DB = process.env.PG_DB || 'konga_p1';
const ADMIN = process.env.PG_USER || os.userInfo().username;
const HERE = path.dirname(fileURLToPath(import.meta.url));
const clients = [];
// Connect as the admin user, then SET ROLE to the Konga role (the Portfolio 1 roles are NOLOGIN group roles).
async function conn(role) {
  const c = new pg.Client({ host: H, port: P, user: ADMIN, database: DB });
  await c.connect(); clients.push(c);
  if (role !== ADMIN) await c.query(`SET ROLE ${role}`);
  return c;
}
const say = (m = '') => console.log(m);
const head = (c, t) => { say(); say('='.repeat(96)); say(`${c}. ${t}`); say('='.repeat(96)); };
const first = (e) => e.message.split('\n')[0];
const ATTACK = "zzz' UNION SELECT customer_id, email_address || ' : ' || password_hash FROM konga.customers --";
const BENIGN = 'Samsung';

// BAD: user input pasted into the SQL text
async function vulnerableSearch(c, term) {
  const sql = `SELECT product_id, name FROM konga.products WHERE name ILIKE '%${term}%'`;
  return [sql, (await c.query({ text: sql, rowMode: 'array' })).rows];
}
// GOOD: value sent separately from the SQL text
async function safeSearch(c, term) {
  const sql = 'SELECT product_id, name FROM konga.products WHERE name ILIKE $1';
  return [sql, (await c.query({ text: sql, values: [`%${term}%`], rowMode: 'array' })).rows];
}

// Baseline: the Portfolio 1 grants (konga_app may DELETE). Restoring them makes the T4 finding reproducible on every run.
const adminC = await conn(ADMIN);
await adminC.query('GRANT DELETE ON konga.customers, konga.orders, konga.order_items, konga.payments, konga.refunds, konga.payouts TO konga_app');

head('T1', "SQL injection against string-built SQL (running as the application's own role, konga_app)");
const app = await conn('konga_app');
let [sql, rows] = await vulnerableSearch(app, BENIGN); say(`  normal search '${BENIGN}': ${rows.length} rows`);
[sql, rows] = await vulnerableSearch(app, ATTACK); say(`  attacker types: ${ATTACK}`);
say(`  executed SQL : ${sql}`);
say(`  RESULT: ${rows.length} rows; leaked: ${JSON.stringify(rows.map((r) => String(r[1]).slice(0, 60)).slice(0, 3))}`);

head('T2', 'The same attack against a parameterised query');
[sql, rows] = await safeSearch(app, ATTACK); say(`  executed SQL : ${sql}   (value sent separately)`);
say(`  RESULT: ${rows.length} rows (the attack text is treated as a product name to search for, so nothing leaks)`);

head('T3', 'Defence in depth: the same injection when the application runs as the low-privilege support role');
const sup = await conn('konga_support');
try { await vulnerableSearch(sup, ATTACK); say('  RESULT: leaked (unexpected)'); }
catch (e) {
  say(`  RESULT: blocked by the database even though the code was vulnerable -> ${first(e)}`);
  say('  (Here the support role has no rights on products at all. Had the query read a table it may see, the password_hash column would still be denied, see T4.)');
}

head('T4', 'Least privilege: what each role may do');
const checks = [['konga_support', 'SELECT email_address FROM konga.customers LIMIT 1', true],
  ['konga_support', 'SELECT password_hash FROM konga.customers LIMIT 1', false],
  ['konga_analyst', 'SELECT * FROM konga.v_seller_sales LIMIT 1', true],
  ['konga_analyst', 'SELECT * FROM konga.customers LIMIT 1', false],
  ['konga_support', 'DELETE FROM konga.orders WHERE false', false],
  ['konga_app', 'DELETE FROM konga.customers WHERE false', false]];
async function runChecks() {
  let bad = 0;
  for (const [role, text, shouldWork] of checks) {
    const c = await conn(role);
    let worked = true;
    try { await c.query(text); } catch { worked = false; }
    const ok = worked === shouldWork; if (!ok) bad++;
    say(`  ${ok ? 'PASS' : 'FAIL'}  ${role.padEnd(14)} ${text.slice(0, 58).padEnd(60)} ${(worked ? 'allowed' : 'denied').padEnd(8)} (should be ${shouldWork ? 'allowed' : 'denied'})`);
  }
  return bad;
}
say('  First run, with the grants from Portfolio 1:');
let bad = await runChecks();
if (bad) {
  say(`  -> ${bad} over-privilege finding(s). Applying sql/hardening.sql (REVOKE DELETE on business tables from konga_app) and re-running:`);
  await adminC.query(fs.readFileSync(path.join(HERE, 'hardening.sql'), 'utf8'));
  bad = await runChecks(); say(`  -> findings remaining: ${bad}`);
}

head('T5', 'Integrity: a constraint rejects bad data even from the app role');
try { await app.query('UPDATE konga.inventory SET quantity_in_store = -5 WHERE variant_id = (SELECT variant_id FROM konga.product_variants ORDER BY sku LIMIT 1)'); say('  allowed (unexpected)'); }
catch (e) { say(`  negative stock refused -> ${first(e)}`); }

head('T6', 'Passwords at rest');
const a = (await adminC.query({ text: 'SELECT left(password_hash, 7), length(password_hash) FROM konga.customers LIMIT 1', rowMode: 'array' })).rows[0];
say(`  stored value looks like: ${JSON.stringify(a)}  (sample data uses placeholder hashes; a real system stores a salted slow hash such as bcrypt or argon2, never the password)`);
say('  Not tested here: TLS for connections, encryption at rest, audit logging. They are listed in docs/security-and-cloud-design.md as design requirements only.');
for (const c of clients) await c.end().catch(() => {});
