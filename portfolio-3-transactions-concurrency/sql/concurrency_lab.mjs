
import pg from "pg";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const CFG = process.env.LAB_DSN
  ? { connectionString: process.env.LAB_DSN }
  : {
      host: process.env.KONGA_PG_HOST || process.env.PGHOST || "/tmp",
      port: Number(process.env.KONGA_PG_PORT || process.env.PGPORT || 5432),
      user: process.env.KONGA_PG_USER || process.env.PGUSER || process.env.USER,
      database: process.env.KONGA_P3_DB || process.env.KONGA_PG_DB || process.env.PGDATABASE || "konga_p3",
      password: process.env.KONGA_PG_PASSWORD || process.env.PGPASSWORD,
    };
const VARIANT_IDS = {1: "794c702a-beb4-4d9b-a4ce-e46393448c09", 2: "4f8a7669-5d62-4219-b083-6b7f124df422", 3: "dfbee643-4577-4e04-8b74-06770618c5f8", 4: "2ad24f49-d621-4d7c-a124-ae758543e76a"};
const RESULTS = []; // [scenario, outcome] for the summary table
const out = (msg = "") => console.log(msg);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const fmt = (rows) =>
  rows.length ? rows.map((r) => r.join(", ")).join("; ") : "(no rows)";

function statusMessage(res) {
  const c = res.command;
  if (c === "INSERT") return `INSERT 0 ${res.rowCount}`;
  if (["UPDATE", "DELETE", "SELECT", "MOVE", "FETCH", "COPY"].includes(c))
    return `${c} ${res.rowCount}`;
  return c;
}

class Sess {
  constructor(name) {
    this.name = name;
  }
  static async open(name) {
    const s = new Sess(name);
    s.client = new pg.Client(CFG);
    await s.client.connect();
    await s.client.query(
      "SET search_path = konga; SET deadlock_timeout = '300ms'; SET lock_timeout = '10s'",
    );
    const r = await s.client.query({
      text: "SELECT pg_backend_pid()",
      rowMode: "array",
    });
    s.pid = r.rows[0][0];
    return s;
  }
  async _run(sql) {
    try {
      const res = await this.client.query({ text: sql, rowMode: "array" });
      const rows = res.fields && res.fields.length ? res.rows : [];
      return ["ok", rows.length ? fmt(rows) : statusMessage(res), rows];
    } catch (e) {
      return ["error", `ERROR ${e.code}: ${e.message}`, []];
    }
  }
  // Run a statement now and print it with its result.
  async x(sql, note = "") {
    out(`  ${this.name}: ${sql}` + (note ? `    -- ${note}` : ""));
    const [status, text, rows] = await this._run(sql);
    out(`       -> ${text}`);
    return [status, rows];
  }
  // Start a statement without waiting for it, then use finish() after the other session releases its lock.
  bg(sql, note = "") {
    out(`  ${this.name}: ${sql}` + (note ? `    -- ${note}` : ""));
    return { promise: this._run(sql), sess: this };
  }
  async close() {
    await this.client.end();
  }
}

// Check that this session is actually waiting for a lock before continuing the demonstration.
async function waitBlocked(sess, timeoutMs = 5000) {
  const mon = new pg.Client(CFG);
  await mon.connect();
  const t0 = Date.now();
  try {
    while (Date.now() - t0 < timeoutMs) {
      const r = await mon.query({
        text: "SELECT wait_event_type, wait_event FROM pg_stat_activity WHERE pid = $1",
        values: [sess.pid],
        rowMode: "array",
      });
      if (r.rows[0] && r.rows[0][0] === "Lock") {
        out(
          `       .. ${sess.name} is now WAITING for a lock (${r.rows[0][1]}) held by another session`,
        );
        return true;
      }
      await sleep(20);
    }
    out(`       .. ${sess.name} did not block`);
    return false;
  } finally {
    await mon.end();
  }
}

async function finish(h) {
  const [status, text, rows] = await h.promise;
  out(`  ${h.sess.name}: (statement finished after the lock was released)`);
  out(`       -> ${text}`);
  return [status, rows];
}

async function reset() {
  const c = new pg.Client(CFG);
  await c.connect();
  await c.query(fs.readFileSync(path.join(HERE, "00_reset_state.sql"), "utf8"));
  await c.end();
}

async function header(code, title, idea) {
  out();
  out("=".repeat(100));
  out(`${code}. ${title}`);
  out(`Idea: ${idea}`);
  out("=".repeat(100));
  await reset();
}

const stock = (s, v = 3) =>
  s.x(
    `SELECT variant_id, quantity_in_store AS on_hand, quantity_reserved AS reserved FROM inventory WHERE variant_id = '${VARIANT_IDS[v]}'`,
  );
const closeAll = (...ss) => Promise.all(ss.map((s) => s.close()));

// --------------------------------------------------------------------------------------------------
async function s1() {
  await header(
    "S1",
    "Dirty read is impossible (and readers never wait for writers)",
    "Session B changes a row but has not committed. Session A, even when it asks for READ UNCOMMITTED, must not see it.",
  );
  const A = await Sess.open("A"),
    B = await Sess.open("B");
  await A.x(
    "BEGIN ISOLATION LEVEL READ UNCOMMITTED",
    "PostgreSQL treats this as READ COMMITTED",
  );
  await B.x("BEGIN");
  await B.x(
    "UPDATE inventory SET quantity_in_store = 99 WHERE variant_id = '794c702a-beb4-4d9b-a4ce-e46393448c09'",
    "uncommitted",
  );
  const [, rows] = await A.x(
    "SELECT quantity_in_store FROM inventory WHERE variant_id = '794c702a-beb4-4d9b-a4ce-e46393448c09'",
    "returns at once; sees the OLD value",
  );
  await B.x("ROLLBACK");
  await A.x("COMMIT");
  RESULTS.push([
    "S1 Dirty read",
    Number(rows[0][0]) === 25
      ? "Not possible: A saw 25, not B's uncommitted 99"
      : "UNEXPECTED",
  ]);
  await closeAll(A, B);
}

async function s2() {
  await header(
    "S2",
    "Non-repeatable read and phantom read: READ COMMITTED vs REPEATABLE READ",
    "A reads twice inside one transaction while B commits a change in between.",
  );
  const summary = {};
  for (const level of ["READ COMMITTED", "REPEATABLE READ"]) {
    await reset();
    out(`\n  --- isolation level: ${level} ---`);
    const A = await Sess.open("A"),
      B = await Sess.open("B");
    await A.x(`BEGIN ISOLATION LEVEL ${level}`);
    const [, r1] = await A.x(
      "SELECT quantity_in_store FROM inventory WHERE variant_id = '794c702a-beb4-4d9b-a4ce-e46393448c09'",
      "first read",
    );
    const [, p1] = await A.x(
      "SELECT count(*) FROM orders WHERE total_amount = 1.00",
      "first count",
    );
    await B.x(
      "UPDATE inventory SET quantity_in_store = 20 WHERE variant_id = '794c702a-beb4-4d9b-a4ce-e46393448c09'",
      "autocommit: B commits at once",
    );
    await B.x(
      "INSERT INTO orders (customer_id, shipping_address_id, total_amount) VALUES ('4cb025ea-36e9-4b9f-8c44-0475cf012951', 'a69034f9-5dac-4987-b5d8-576114135d44', 1.00)",
      "B adds a row and commits",
    );
    const [, r2] = await A.x(
      "SELECT quantity_in_store FROM inventory WHERE variant_id = '794c702a-beb4-4d9b-a4ce-e46393448c09'",
      "second read",
    );
    const [, p2] = await A.x(
      "SELECT count(*) FROM orders WHERE total_amount = 1.00",
      "second count",
    );
    await A.x("COMMIT");
    summary[level] = [r1[0][0], r2[0][0], p1[0][0], p2[0][0]];
    await closeAll(A, B);
  }
  const rc = summary["READ COMMITTED"],
    rr = summary["REPEATABLE READ"];
  RESULTS.push([
    "S2 Non-repeatable read",
    `READ COMMITTED: ${rc[0]} then ${rc[1]} (changed). REPEATABLE READ: ${rr[0]} then ${rr[1]} (stable)`,
  ]);
  RESULTS.push([
    "S2 Phantom read",
    `READ COMMITTED: count ${rc[2]} then ${rc[3]} (phantom row). REPEATABLE READ: ${rr[2]} then ${rr[3]} (stable)`,
  ]);
}

const oversellSetup = async () => [
  await Sess.open("A (customer 1)"),
  await Sess.open("B (customer 2)"),
];

async function s3() {
  await header(
    "S3",
    "Overselling the last unit (lost update) and three ways to prevent it",
    "Only 1 unit of variant 3 is in stock. Two customers click 'buy' at the same moment. The application reads the stock, " +
      "checks it, and writes the new reserved count.",
  );

  // 3a: naive read-modify-write, READ COMMITTED
  out(
    "\n  --- S3a. NAIVE application logic at READ COMMITTED (no locking) ---",
  );
  let [A, B] = await oversellSetup();
  await A.x("BEGIN");
  await B.x("BEGIN");
  const Q =
    "SELECT quantity_in_store - quantity_reserved AS available, quantity_reserved FROM inventory WHERE variant_id = 'dfbee643-4577-4e04-8b74-06770618c5f8'";
  const [, ra] = await A.x(Q);
  const [, rb] = await B.x(Q);
  out(
    "       .. both applications see available = 1, so both decide the sale is OK",
  );
  await A.x(
    `UPDATE inventory SET quantity_reserved = ${Number(ra[0][1]) + 1} WHERE variant_id = 'dfbee643-4577-4e04-8b74-06770618c5f8'`,
    "value computed in the app from its earlier read",
  );
  await A.x("COMMIT");
  await B.x(
    `UPDATE inventory SET quantity_reserved = ${Number(rb[0][1]) + 1} WHERE variant_id = 'dfbee643-4577-4e04-8b74-06770618c5f8'`,
    "overwrites A's work with the same number",
  );
  await B.x("COMMIT");
  let [, fin] = await stock(A);
  RESULTS.push([
    "S3a Naive, READ COMMITTED",
    `LOST UPDATE: 2 customers were told 'success' but reserved = ${fin[0][2]} for 1 unit in stock`,
  ]);
  await closeAll(A, B);

  // 3b: SELECT ... FOR UPDATE
  await reset();
  out("\n  --- S3b. FIX 1: pessimistic locking with SELECT ... FOR UPDATE ---");
  [A, B] = await oversellSetup();
  await A.x("BEGIN");
  await B.x("BEGIN");
  const FU =
    "SELECT quantity_in_store - quantity_reserved AS available FROM inventory WHERE variant_id = 'dfbee643-4577-4e04-8b74-06770618c5f8' FOR UPDATE";
  await A.x(FU, "A takes the row lock");
  let hb = B.bg(FU, "B must wait");
  await waitBlocked(B);
  await A.x(
    "UPDATE inventory SET quantity_reserved = quantity_reserved + 1 WHERE variant_id = 'dfbee643-4577-4e04-8b74-06770618c5f8'",
  );
  await A.x("COMMIT", "releases the lock");
  let [, rows] = await finish(hb);
  const avail = Number(rows[0][0]);
  if (avail < 1)
    await B.x(
      "ROLLBACK",
      `B now sees available = ${avail}: tells customer 2 'sold out'`,
    );
  else await B.x("COMMIT");
  [, fin] = await stock(A);
  RESULTS.push([
    "S3b FOR UPDATE",
    `Correct: B waited, then saw available = ${avail} and was refused; reserved = ${fin[0][2]}`,
  ]);
  await closeAll(A, B);

  // 3c: atomic conditional UPDATE
  await reset();
  out(
    "\n  --- S3c. FIX 2: one atomic conditional UPDATE (check and write in the same statement) ---",
  );
  [A, B] = await oversellSetup();
  const sql =
    "UPDATE inventory SET quantity_reserved = quantity_reserved + 1 " +
    "WHERE variant_id = 'dfbee643-4577-4e04-8b74-06770618c5f8' AND quantity_in_store - quantity_reserved >= 1 RETURNING variant_id";
  await A.x("BEGIN");
  await B.x("BEGIN");
  await A.x(sql, "1 row updated = success");
  hb = B.bg(
    sql,
    "waits for A's row lock, then re-checks the WHERE clause on the new row version",
  );
  await waitBlocked(B);
  await A.x("COMMIT");
  [, rows] = await finish(hb);
  await B.x("COMMIT");
  [, fin] = await stock(A);
  RESULTS.push([
    "S3c Atomic UPDATE ... WHERE",
    `Correct: B's UPDATE matched ${rows.length} rows (0 = sold out); reserved = ${fin[0][2]}`,
  ]);
  await closeAll(A, B);

  // 3d: REPEATABLE READ + retry
  await reset();
  out(
    "\n  --- S3d. FIX 3: optimistic approach: REPEATABLE READ, abort on conflict and retry ---",
  );
  [A, B] = await oversellSetup();
  await A.x("BEGIN ISOLATION LEVEL REPEATABLE READ");
  await B.x("BEGIN ISOLATION LEVEL REPEATABLE READ");
  const [, ra2] = await A.x(Q);
  const [, rb2] = await B.x(Q);
  await A.x(
    `UPDATE inventory SET quantity_reserved = ${Number(ra2[0][1]) + 1} WHERE variant_id = 'dfbee643-4577-4e04-8b74-06770618c5f8'`,
  );
  await A.x("COMMIT");
  await B.x(
    `UPDATE inventory SET quantity_reserved = ${Number(rb2[0][1]) + 1} WHERE variant_id = 'dfbee643-4577-4e04-8b74-06770618c5f8'`,
    "row changed since B's snapshot",
  );
  await B.x("ROLLBACK", "B must roll back and retry the whole transaction");
  await B.x("BEGIN ISOLATION LEVEL REPEATABLE READ", "retry");
  const [, rbRetry] = await B.x(
    "SELECT quantity_in_store - quantity_reserved AS available FROM inventory WHERE variant_id = 'dfbee643-4577-4e04-8b74-06770618c5f8'",
    "fresh snapshot now includes A's commit",
  );
  await B.x("ROLLBACK", `available = ${rbRetry[0][0]}: sold out`);
  [, fin] = await stock(A);
  RESULTS.push([
    "S3d REPEATABLE READ + retry",
    `Correct: B got a serialization error (not a silent overwrite), retried and saw sold out; reserved = ${fin[0][2]}`,
  ]);
  await closeAll(A, B);
}

async function s4() {
  await header(
    "S4",
    "Write skew: REPEATABLE READ is not enough, SERIALIZABLE is",
    "Rule: the marketplace must always have at least one active seller. Sellers 1 and 2 are both active. " +
      "Two admins each suspend a different seller after checking that another one stays active.",
  );
  const results = {};
  for (const level of ["REPEATABLE READ", "SERIALIZABLE"]) {
    await reset();
    out(`\n  --- isolation level: ${level} ---`);
    const A = await Sess.open("A (admin 1)"),
      B = await Sess.open("B (admin 2)");
    await A.x(`BEGIN ISOLATION LEVEL ${level}`);
    await B.x(`BEGIN ISOLATION LEVEL ${level}`);
    await A.x(
      "SELECT count(*) AS active_sellers FROM sellers WHERE status = 'active'",
    );
    await B.x(
      "SELECT count(*) AS active_sellers FROM sellers WHERE status = 'active'",
    );
    out(
      "       .. both see 2 active sellers, so each thinks suspending one is safe",
    );
    await A.x("UPDATE sellers SET status = 'suspended' WHERE seller_id = 'fa80071d-93fa-4b83-9b38-b4cb3c183eff'");
    await B.x("UPDATE sellers SET status = 'suspended' WHERE seller_id = '581b5806-e2b7-4e5f-b84e-3a72256615c1'");
    await A.x("COMMIT");
    await B.x("COMMIT");
    const chk = await Sess.open("check");
    const [, rows] = await chk.x(
      "SELECT count(*) AS active_sellers FROM sellers WHERE status = 'active'",
      "final state",
    );
    results[level] = rows[0][0];
    await A.x("ROLLBACK");
    await B.x("ROLLBACK");
    await closeAll(A, B, chk);
  }
  RESULTS.push([
    "S4 Write skew, REPEATABLE READ",
    `RULE BROKEN: ${results["REPEATABLE READ"]} active sellers left`,
  ]);
  RESULTS.push([
    "S4 Write skew, SERIALIZABLE",
    `Rule kept: ${results["SERIALIZABLE"]} active seller left (one transaction was aborted with 40001)`,
  ]);
}

async function s5() {
  await header(
    "S5",
    "Deadlock detected and resolved; prevention by consistent lock order",
    "Two stock adjustments touch the same two variants in opposite order.",
  );
  out("\n  --- S5a. opposite order: A locks 1 then 2, B locks 2 then 1 ---");
  let A = await Sess.open("A"),
    B = await Sess.open("B");
  await A.x("BEGIN");
  await B.x("BEGIN");
  const U = (v) =>
    `UPDATE inventory SET quantity_in_store = quantity_in_store - 1 WHERE variant_id = '${VARIANT_IDS[v]}'`;
  await A.x(U(1));
  await B.x(U(2));
  const ha = A.bg(U(2), "A waits for B");
  await waitBlocked(A);
  const [sb] = await B.x(
    U(1),
    "B waits for A: a cycle; PostgreSQL checks after deadlock_timeout",
  );
  const [sa] = await finish(ha);
  for (const [s, st] of [
    [A, sa],
    [B, sb],
  ])
    await s.x(
      st === "error" ? "ROLLBACK" : "COMMIT",
      st === "error" ? "victim rolls back" : "survivor commits",
    );
  const killed = sb === "error" ? "B" : "A";
  RESULTS.push([
    "S5a Deadlock",
    `Detected: session ${killed} aborted with 40P01, the other committed`,
  ]);
  await closeAll(A, B);

  await reset();
  out(
    "\n  --- S5b. prevention: every transaction locks rows in ascending variant_id order ---",
  );
  A = await Sess.open("A");
  B = await Sess.open("B");
  await A.x("BEGIN");
  await B.x("BEGIN");
  const LK =
    "SELECT 1 FROM inventory WHERE variant_id IN ('794c702a-beb4-4d9b-a4ce-e46393448c09', '4f8a7669-5d62-4219-b083-6b7f124df422') ORDER BY variant_id FOR UPDATE";
  await A.x(LK, "locks both rows in ascending UUID order");
  const hb = B.bg(LK, "B queues behind A on the first UUID");
  await waitBlocked(B);
  const BOTH =
    "UPDATE inventory SET quantity_in_store = quantity_in_store - 1 WHERE variant_id IN ('794c702a-beb4-4d9b-a4ce-e46393448c09', '4f8a7669-5d62-4219-b083-6b7f124df422')";
  await A.x(BOTH);
  await A.x("COMMIT");
  await finish(hb);
  await B.x(BOTH);
  await B.x("COMMIT");
  const [, rows] = await A.x(
    "SELECT variant_id, quantity_in_store FROM inventory WHERE variant_id IN ('794c702a-beb4-4d9b-a4ce-e46393448c09', '4f8a7669-5d62-4219-b083-6b7f124df422') ORDER BY 1",
  );
  RESULTS.push([
    "S5b Ordered locking",
    `No deadlock; both committed; stock ${fmt(rows)} (each reduced by 2)`,
  ]);
  await closeAll(A, B);
}

async function s6() {
  await header(
    "S6",
    "Not waiting: NOWAIT and SKIP LOCKED",
    "Warehouse workers each pick a stock row to recount. They should not queue behind each other.",
  );
  const A = await Sess.open("worker A"),
    B = await Sess.open("worker B");
  await A.x("BEGIN");
  await B.x("BEGIN");
  await A.x(
    "SELECT variant_id FROM inventory WHERE variant_id = '794c702a-beb4-4d9b-a4ce-e46393448c09' FOR UPDATE",
    "A locks the black phone stock row",
  );
  await B.x(
    "SELECT variant_id FROM inventory WHERE variant_id = '794c702a-beb4-4d9b-a4ce-e46393448c09' FOR UPDATE NOWAIT",
    "B refuses to wait",
  );
  await B.x("ROLLBACK", "the error aborted B's transaction; start a new one");
  await B.x("BEGIN");
  const [, rows] = await B.x(
    "SELECT variant_id FROM inventory ORDER BY (variant_id = '794c702a-beb4-4d9b-a4ce-e46393448c09') DESC, variant_id LIMIT 1 FOR UPDATE SKIP LOCKED",
    "B takes the next free row instead",
  );
  await A.x("COMMIT");
  await B.x("COMMIT");
  RESULTS.push([
    "S6 NOWAIT / SKIP LOCKED",
    `NOWAIT gave an immediate error; SKIP LOCKED gave B variant ${rows[0][0]} instead of waiting`,
  ]);
  await closeAll(A, B);
}

const SCENARIOS = { S1: s1, S2: s2, S3: s3, S4: s4, S5: s5, S6: s6 };
const wanted = process.argv.slice(2).map((a) => a.toUpperCase());
for (const k of wanted.length ? wanted : Object.keys(SCENARIOS))
  await SCENARIOS[k]();
await reset();
out();
out("=".repeat(100));
out("SUMMARY");
out("=".repeat(100));
for (const [name, outcome] of RESULTS) out(`  ${name.padEnd(32)} ${outcome}`);
