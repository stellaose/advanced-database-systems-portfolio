#!/usr/bin/env node
// Replication and failover lab for Konga (Portfolio 5, Study Session 2: 2.1.4.2 replication, 2.1.4.3 consistency models, 2.2 CAP and BASE).
//
// Builds its OWN throwaway primary (port 5440) and streaming replica (port 5441) under /tmp/replab, loads the Portfolio 1
// sample database, then runs R1..R6. It never touches any other PostgreSQL instance.
//
//   node sql/replication_lab.mjs     # needs initdb/pg_ctl/pg_basebackup on PATH or PGBIN
//
// Runs as your own OS user (RUN_AS). Set PGBIN if the PostgreSQL binaries are not found.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

pg.types.setTypeParser(20, Number);
// PGBIN: folder with initdb, pg_ctl, pg_basebackup. Default: ask pg_config; override with PGBIN=... (Homebrew: $(brew --prefix postgresql@15)/bin).
const PGBIN = process.env.PGBIN || spawnSync('pg_config', ['--bindir'], { encoding: 'utf8' }).stdout.trim();
const RUN_AS = process.env.RUN_AS || os.userInfo().username;   // your own Mac user; the lab's own clusters trust local connections
const BASE = '/tmp/replab', P_DIR = `${BASE}/primary`, R_DIR = `${BASE}/replica`, SOCK = BASE;
const P_PORT = 5440, R_PORT = 5441;
const HERE = path.dirname(fileURLToPath(import.meta.url));
const P1 = path.join(HERE, '..', '..', 'portfolio-1-database-design', 'sql');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const say = (m = '') => console.log(m);
const head = (c, t) => { say(); say('='.repeat(96)); say(`${c}. ${t}`); say('='.repeat(96)); };
const median = (a) => { const s = [...a].sort((x, y) => x - y), m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
const q95 = (a) => [...a].sort((x, y) => x - y)[Math.floor(0.95 * (a.length - 1))];
const now = () => Number(process.hrtime.bigint()) / 1e6;
const shq = (s) => `'${s.replace(/'/g, `'\\''`)}'`;

function sh(cmd, check = true) {
  const full = process.getuid() === 0 ? `su ${RUN_AS} -c ${shq(cmd)}` : cmd;
  const r = spawnSync('bash', ['-c', full], { encoding: 'utf8' });
  if (check && r.status !== 0) throw new Error(`${cmd}\n${r.stdout}\n${r.stderr}`);
  return r;
}
async function q(port, sql, values) {
  const c = new pg.Client({ host: SOCK, port, user: RUN_AS, database: 'konga_p1' });
  await c.connect();
  try { return (await c.query({ text: sql, values, rowMode: 'array' })).rows; } finally { await c.end(); }
}
const conn = async (port) => { const c = new pg.Client({ host: SOCK, port, user: RUN_AS, database: 'konga_p1' }); await c.connect(); return c; };
const pgCtl = (d, action, port) => sh(`${PGBIN}/pg_ctl -D ${d} ${port ? `-o '-p ${port} -k ${SOCK}'` : ''} -l ${BASE}/log_${path.basename(d)}.txt ${action} -w`, false);
async function waitUp(port, seconds = 10) {
  const t0 = Date.now();
  while (Date.now() - t0 < seconds * 1000) { try { await q(port, 'select 1'); return true; } catch { await sleep(200); } }
  return false;
}
// Your variant ids are UUIDs, so 'variant N' means the N-th variant in SKU order (stable for the sample data).
const stock = async (port, v) => (await q(port, `select quantity_in_store from konga.inventory where variant_id = (select variant_id from konga.product_variants order by sku limit 1 offset ${v - 1})`))[0][0];

async function build() {
  for (const d of [P_DIR, R_DIR]) if (fs.existsSync(d)) pgCtl(d, 'stop -m immediate');
  sh(`rm -rf ${BASE}; mkdir -p ${BASE}`);
  sh(`${PGBIN}/initdb -D ${P_DIR} -U ${RUN_AS} --auth=trust >/dev/null`);
  fs.appendFileSync(`${P_DIR}/postgresql.conf`, `port = ${P_PORT}\nunix_socket_directories = '${SOCK}'\nlisten_addresses = 'localhost'\nwal_level = replica\nmax_wal_senders = 5\nmax_replication_slots = 5\nwal_keep_size = '128MB'\n`);
  fs.appendFileSync(`${P_DIR}/pg_hba.conf`, 'local replication all trust\nhost replication all 127.0.0.1/32 trust\n');
  pgCtl(P_DIR, 'start', P_PORT);
  sh(`psql -h ${SOCK} -p ${P_PORT} -U ${RUN_AS} -d postgres -qc 'CREATE DATABASE konga_p1'`);
  for (const f of ['01_schema.sql', '02_sample_data.sql'])
    sh(`psql -h ${SOCK} -p ${P_PORT} -U ${RUN_AS} -d konga_p1 -q -f ${path.resolve(P1, f)} >/dev/null`);
  sh(`${PGBIN}/pg_basebackup -D ${R_DIR} -h ${SOCK} -p ${P_PORT} -U ${RUN_AS} -R -X stream -C -S replica1 -d 'application_name=replica1' 2>&1`);
  // a standby needs its own port; -R wrote primary_conninfo (with application_name) and standby.signal
  fs.appendFileSync(`${R_DIR}/postgresql.conf`, `port = ${R_PORT}\n`);
  pgCtl(R_DIR, 'start', R_PORT);
  if (!(await waitUp(R_PORT))) throw new Error('replica did not start');
}

async function r1() {
  head('R1', 'Streaming replication is running (primary -> replica)');
  for (const row of await q(P_PORT, 'select application_name, state, sync_state, sent_lsn, replay_lsn from pg_stat_replication'))
    say(`  pg_stat_replication on primary: ${JSON.stringify(row)}`);
  say(`  primary pg_is_in_recovery() = ${(await q(P_PORT, 'select pg_is_in_recovery()'))[0][0]}   replica pg_is_in_recovery() = ${(await q(R_PORT, 'select pg_is_in_recovery()'))[0][0]}`);
  say(`  rows visible on replica after the initial copy: customers = ${(await q(R_PORT, 'select count(*) from konga.customers'))[0][0]}, products = ${(await q(R_PORT, 'select count(*) from konga.products'))[0][0]}`);
  try { await q(R_PORT, 'update konga.inventory set quantity_in_store = 0'); } catch (e) { say(`  write on the replica is refused: ${e.message.split('\n')[0]}`); }
}

async function r2() {
  head('R2', 'Asynchronous replication: how long until a write on the primary is visible on the replica?');
  const pc = await conn(P_PORT), rc = await conn(R_PORT), lags = [];
  for (let i = 0; i < 30; i++) {
    const val = 1000 + i, t0 = now();
    await pc.query('update konga.inventory set quantity_in_store = $1 where variant_id = (select variant_id from konga.product_variants order by sku limit 1 offset 0)', [val]);
    for (;;) {
      const r = await rc.query({ text: 'select quantity_in_store from konga.inventory where variant_id = (select variant_id from konga.product_variants order by sku limit 1 offset 0)', rowMode: 'array' });
      if (r.rows[0][0] === val) break;
    }
    lags.push(now() - t0);
  }
  say(`  30 writes: time until the replica shows the new value: median ${median(lags).toFixed(2)} ms, max ${Math.max(...lags).toFixed(2)} ms (same machine, so network delay is ~0)`);
  await pc.end(); await rc.end();
}

async function r3() {
  head('R3', 'Eventual consistency: a stale read when the replica is behind (lag injected with recovery_min_apply_delay = 3 s)');
  say('  The delay is injected on purpose to emulate a slow link or a busy replica; this is not natural lag.');
  await q(R_PORT, "alter system set recovery_min_apply_delay = '3s'"); await q(R_PORT, 'select pg_reload_conf()'); await sleep(1000);
  const oldV = await stock(P_PORT, 4);
  await q(P_PORT, 'update konga.inventory set quantity_in_store = 7 where variant_id = (select variant_id from konga.product_variants order by sku limit 1 offset 3)');
  say('  primary: UPDATE inventory SET quantity_in_store = 7 WHERE variant_id = 4  (committed)');
  say(`  replica read immediately after : ${await stock(R_PORT, 4)}   <- STALE (old value ${oldV}); a customer who just bought would not see their own change`);
  say(`  primary read                   : ${await stock(P_PORT, 4)}   <- read-your-writes needs the primary (or wait)`);
  await sleep(3500);
  say(`  replica read 3.5 s later       : ${await stock(R_PORT, 4)}   <- caught up: eventually consistent`);
  await q(R_PORT, 'alter system reset recovery_min_apply_delay'); await q(R_PORT, 'select pg_reload_conf()'); await sleep(1000);
  say('  (delay removed again)');
}

async function commitCost(n = 300) {
  const c = await conn(P_PORT), t = [];
  for (let i = 0; i < n; i++) {
    const s = now();
    await c.query('update konga.inventory set quantity_in_store = quantity_in_store where variant_id = (select variant_id from konga.product_variants order by sku limit 1 offset 1)');
    t.push(now() - s);
  }
  await c.end();
  return [median(t), q95(t)];
}

async function r4() {
  head('R4', 'Synchronous vs asynchronous commit: what does waiting for the replica cost?');
  const res = {};
  for (const [label, names, level] of [['async (default)', '', 'on'], ['sync, replica has WAL on disk (on)', 'replica1', 'on'], ['sync, replica has applied it (remote_apply)', 'replica1', 'remote_apply']]) {
    await q(P_PORT, `alter system set synchronous_standby_names = '${names}'`); await q(P_PORT, `alter system set synchronous_commit = '${level}'`);
    await q(P_PORT, 'select pg_reload_conf()'); await sleep(1500);
    const syncState = (await q(P_PORT, 'select sync_state from pg_stat_replication'))[0][0];
    const [m, p] = await commitCost(); res[label] = m;
    say(`  ${label.padEnd(46)} replica sync_state = ${syncState.padEnd(8)} single-row commit latency: median ${m.toFixed(2)} ms, p95 ${p.toFixed(2)} ms`);
  }
  const base = res['async (default)'];
  say(`  -> waiting for the replica multiplied median commit latency by ${(res['sync, replica has WAL on disk (on)'] / base).toFixed(1)}x (flush) and ${(res['sync, replica has applied it (remote_apply)'] / base).toFixed(1)}x (apply) on a zero-distance link; across a real network it adds the round trip.`);
}

async function r5() {
  head('R5', 'Consistency versus availability (CAP): synchronous commit when the replica is unreachable');
  await q(P_PORT, "alter system set synchronous_standby_names = 'replica1'"); await q(P_PORT, "alter system set synchronous_commit = 'on'");
  await q(P_PORT, 'select pg_reload_conf()'); await sleep(1000);
  pgCtl(R_DIR, 'stop -m fast'); say('  replica stopped (a network partition or a crashed standby)');
  const r = spawnSync('timeout', ['4', 'psql', '-h', SOCK, '-p', String(P_PORT), '-U', RUN_AS, '-d', 'konga_p1', '-qc',
    'update konga.inventory set quantity_in_store = quantity_in_store where variant_id = (select variant_id from konga.product_variants order by sku limit 1 offset 1)'], { encoding: 'utf8' });
  say('  synchronous commit with the replica down: ' + (r.status === 124 ? 'no answer after 4 s, the client gave up (exit code 124)' : `returned (exit ${r.status})`));
  say('  The primary refuses to acknowledge a commit it cannot copy: consistency is kept, availability for writes is lost.');
  await q(P_PORT, "alter system set synchronous_standby_names = ''"); await q(P_PORT, 'select pg_reload_conf()'); await sleep(1000);
  const t0 = now(); const c2 = await conn(P_PORT);
  await c2.query('update konga.inventory set quantity_in_store = quantity_in_store where variant_id = (select variant_id from konga.product_variants order by sku limit 1 offset 1)');
  say(`  after switching back to asynchronous: the same write succeeds in ${(now() - t0).toFixed(1)} ms (availability kept, but a crash now could lose the last writes, see R6)`);
  await c2.end();
  await q(P_PORT, 'alter system reset synchronous_commit'); await q(P_PORT, 'select pg_reload_conf()');
  pgCtl(R_DIR, 'start', R_PORT); if (!(await waitUp(R_PORT))) throw new Error('replica did not restart'); await sleep(2000);
}

function killPrimaryHard() {
  const pid = fs.readFileSync(`${P_DIR}/postmaster.pid`, 'utf8').split('\n')[0].trim();
  const kids = spawnSync('pgrep', ['-P', pid], { encoding: 'utf8' }).stdout.split('\n').filter(Boolean);
  for (const p of [...kids, pid]) spawnSync('kill', ['-9', p]);
}

async function r6() {
  head('R6', 'Failover and data loss with asynchronous replication (RPO > 0)');
  say(`  before: primary stock for variant 3 = ${await stock(P_PORT, 3)}, replica = ${await stock(R_PORT, 3)}`);
  pgCtl(R_DIR, 'stop -m fast'); say('  replica goes offline (a short outage)');
  await q(P_PORT, 'update konga.inventory set quantity_in_store = 555 where variant_id = (select variant_id from konga.product_variants order by sku limit 1 offset 2)'); say("  primary COMMITS: variant 3 stock = 555 (client was told 'success')");
  killPrimaryHard(); await sleep(1500);
  say('  primary crashes (kill -9) before the replica ever received that commit');
  pgCtl(R_DIR, 'start', R_PORT); if (!(await waitUp(R_PORT))) throw new Error('replica did not restart'); await sleep(1000);
  sh(`${PGBIN}/pg_ctl -D ${R_DIR} promote -w >/dev/null`); await sleep(1000);
  say(`  replica promoted: pg_is_in_recovery() = ${(await q(R_PORT, 'select pg_is_in_recovery()'))[0][0]}  (it is the new primary)`);
  say(`  new primary stock for variant 3 = ${await stock(R_PORT, 3)}   <- the acknowledged write of 555 is LOST`);
  await q(R_PORT, 'update konga.inventory set quantity_in_store = 40 where variant_id = (select variant_id from konga.product_variants order by sku limit 1 offset 2)'); say('  new primary accepts writes again (service restored after the promote).');
  say('  Lessons: (1) asynchronous replication can lose acknowledged commits; (2) the old primary must not be restarted as a primary (split brain) until it is rebuilt as a replica of the new one.');
}

function cleanup() {
  for (const d of [P_DIR, R_DIR]) pgCtl(d, 'stop -m immediate');
}

const ver = sh(`${PGBIN}/postgres --version`).stdout.trim();
say(`Replication lab  ${new Date().toISOString().slice(0, 19).replace('T', ' ')} UTC  server: ${PGBIN}/postgres --version -> ${ver}`);
await build(); await r1(); await r2(); await r3(); await r4(); await r5(); await r6(); cleanup();
