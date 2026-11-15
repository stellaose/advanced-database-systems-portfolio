// Portfolio 2 experiments, one per technique in Study Session 4 (Node.js).
// Run:  node sql/experiments/run_experiments.mjs      (needs the large Konga dataset from 01_seed_large.sql and the indexes from 03_indexes.sql)
// Connection: KONGA_PG_HOST / KONGA_PG_PORT / KONGA_PG_USER / KONGA_PG_DB (defaults: /tmp, 5432, current user, konga_p2)
// Output: evidence/experiments/*.md (tables), *.plan.txt (full plans), executed-sql.sql (every statement).
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import * as h from "./harness.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const db = await h.connect();
try {
const OUT = h.OUT;
const results = {};
const run = (sql, label) => h.run(db, sql, label);
const explain = (sql, label, opts) => h.explain(db, sql, label, opts);
const one = async (sql) => (await db.query({ text: sql, rowMode: "array" })).rows;
const saveMd = (name, title, intro, tbl) => fs.writeFileSync(path.join(OUT, name), `# ${title}\n\n${intro}\n\n${tbl}\n`);
const uniq = (xs) => [...new Set(xs)];

const joinNode = (plan) => {
  const m = [...plan.matchAll(/(Hash[ A-Za-z]*Join|Merge[ A-Za-z]*Join|Nested Loop[ A-Za-z]*?(?=  \()|SubPlan)/g)].map((x) => x[1].trim());
  return uniq(m).join(", ") || "-";
};
const scanNodes = (plan) => uniq([...plan.matchAll(/(Seq Scan|Index Only Scan|Index Scan|Bitmap Heap Scan|Parallel Seq Scan)/g)].map((x) => x[1])).join(", ") || "-";
const scanEst = (plan) => {
  const m = plan.match(/(?:Seq Scan|Index Scan|Index Only Scan|Bitmap Heap Scan|Bitmap Index Scan)[^\n]*\(cost=[0-9.]+\.\.[0-9.]+ rows=(\d+) [^\n]*\(actual time=[0-9.]+\.\.[0-9.]+ rows=(\d+)/);
  return m ? [Number(m[1]), Number(m[2])] : [null, null];
};

// ---------------------------------------------------------------------------
// E1. Cost-based optimisation depends on statistics (4.1.2.2, 4.1.2.3 "statistics", 4.1.3.2 "estimated vs actual")
// ---------------------------------------------------------------------------
await run("DROP SCHEMA IF EXISTS exp CASCADE"); await run("CREATE SCHEMA exp");
await run("CREATE TABLE exp.ostat AS SELECT order_id, customer_id, status, total_amount, placed_at FROM konga.orders", "E1 setup");
await run("ALTER TABLE exp.ostat SET (autovacuum_enabled = false)");
await run("CREATE INDEX ON exp.ostat (status)");
await run("ANALYZE exp.ostat");
{
  const q = "SELECT count(*), sum(total_amount) FROM exp.ostat WHERE status = 'pending'";
  const rows = [];
  rows.push(await explain(q, "A. fresh statistics ('pending' is a small share of rows)", { save: "e1_a_fresh.plan.txt" }));
  await run("UPDATE exp.ostat SET status = 'pending' WHERE right(order_id, 12)::bigint % 10 < 7", "E1: data distribution changes (about 70% become 'pending'); statistics NOT refreshed");
  rows.push(await explain(q, "B. STALE statistics after the data changed", { save: "e1_b_stale.plan.txt" }));
  await run("ANALYZE exp.ostat", "E1: refresh statistics");
  rows.push(await explain(q, "C. after ANALYZE (statistics refreshed)", { save: "e1_c_refreshed.plan.txt" }));
  for (const r of rows) { r.scan = scanNodes(r.plan); [r.scan_est, r.scan_act] = scanEst(r.plan); }
  results.E1 = rows;
  saveMd("e1_statistics.md", "E1: statistics and the cost-based optimiser",
    "Query: `" + q + "`. The optimiser chooses a plan from its *estimate* of how many rows match.",
    h.table(rows, [["Step", "label"], ["Scan chosen", "scan"], ["Estimated rows at scan", "scan_est"], ["Actual rows at scan", "scan_act"], ["Median ms", "ms"], ["Buffers hit", "buf_hit"]]));
}

// ---------------------------------------------------------------------------
// E2. Query rewriting, flattening, sargable predicates (4.1.2.3)
// ---------------------------------------------------------------------------
{
  const base = "now() - interval '7 days'";
  const variants = [
    ["IN (subquery)", `SELECT customer_id, full_name FROM konga.customers WHERE customer_id IN (SELECT customer_id FROM konga.orders WHERE placed_at >= ${base})`],
    ["EXISTS (correlated)", `SELECT c.customer_id, c.full_name FROM konga.customers c WHERE EXISTS (SELECT 1 FROM konga.orders o WHERE o.customer_id = c.customer_id AND o.placed_at >= ${base})`],
    ["JOIN + DISTINCT", `SELECT DISTINCT c.customer_id, c.full_name FROM konga.customers c JOIN konga.orders o ON o.customer_id = c.customer_id WHERE o.placed_at >= ${base}`],
  ];
  const rowsA = [];
  for (const [lab, sql] of variants) { const r = await explain(sql, "E2a " + lab, { save: `e2a_${lab.split(" ")[0].toLowerCase()}.plan.txt` }); r.join = joinNode(r.plan); rowsA.push(r); }
  const tblA = h.table(rowsA, [["Formulation", "label"], ["Join strategy in plan", "join"], ["Median ms", "ms"], ["Rows", "act_rows"]]);

  const sub = [
    ["correlated subquery per row", "SELECT o.order_id, (SELECT sum(i.quantity * i.unit_price) FROM konga.order_items i WHERE i.order_id = o.order_id) AS total FROM konga.orders o WHERE o.customer_id < '00000001-0000-4000-8000-000000003000'"],
    ["join + GROUP BY (rewritten)", "SELECT o.order_id, sum(i.quantity * i.unit_price) AS total FROM konga.orders o LEFT JOIN konga.order_items i ON i.order_id = o.order_id WHERE o.customer_id < '00000001-0000-4000-8000-000000003000' GROUP BY o.order_id"],
  ];
  const rowsB = [];
  for (const [lab, sql] of sub) { const r = await explain(sql, "E2b " + lab, { save: `e2b_${lab.split(" ")[0]}.plan.txt` }); r.join = joinNode(r.plan); rowsB.push(r); }
  const tblB = h.table(rowsB, [["Formulation", "label"], ["Strategy", "join"], ["Median ms", "ms"], ["Buffers hit", "buf_hit"]]);

  const sarg = [
    ["function on column: date_trunc('day', placed_at) = DATE", "SELECT count(*) FROM konga.orders WHERE date_trunc('day', placed_at) = date_trunc('day', now() - interval '30 days')"],
    ["range on the bare column (rewritten)", "SELECT count(*) FROM konga.orders WHERE placed_at >= date_trunc('day', now() - interval '30 days') AND placed_at < date_trunc('day', now() - interval '29 days')"],
  ];
  const rowsC = [];
  for (const [lab, sql] of sarg) { const r = await explain(sql, "E2c " + lab, { save: `e2c_${rowsC.length}.plan.txt` }); r.scan = scanNodes(r.plan); rowsC.push(r); }
  const tblC = h.table(rowsC, [["Predicate form", "label"], ["Access path", "scan"], ["Median ms", "ms"], ["Buffers hit", "buf_hit"]]);
  fs.writeFileSync(path.join(OUT, "e2_rewriting.md"),
    "# E2: query rewriting, flattening and sargable predicates\n\n## E2a. Nested query vs join (flattening)\n\n" + tblA +
    "\n## E2b. Correlated subquery vs join with aggregation\n\n" + tblB + "\n## E2c. Sargable predicate\n\n" + tblC);
  results.E2 = { a: rowsA, b: rowsB, c: rowsC };
}

// ---------------------------------------------------------------------------
// E3. Join algorithms and join order (4.1.2.3)
// ---------------------------------------------------------------------------
{
  const rows = [];
  for (const [selLabel, bound] of [["selective (UUID customer suffix below 000000000300, about 1.5% of orders)", 300], ["broad (UUID customer suffix below 000000015000, about 75% of orders)", 15000]]) {
    const sql = `SELECT o.order_id, sum(oi.quantity * oi.unit_price) FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id WHERE o.customer_id < '00000001-0000-4000-8000-${String(bound).padStart(12, '0')}' GROUP BY o.order_id`;
    for (const [algo, settings] of [["optimiser's choice", {}], ["force hash join", { enable_nestloop: "off", enable_mergejoin: "off" }],
                                    ["force merge join", { enable_nestloop: "off", enable_hashjoin: "off" }], ["force nested loop", { enable_hashjoin: "off", enable_mergejoin: "off" }]]) {
      for (const [k, v] of Object.entries(settings)) await run(`SET ${k} = ${v}`);
      const r = await explain(sql, `E3 ${selLabel} / ${algo}`, { runs: 2 });
      r.algo = algo; r.sel = selLabel.split(" (")[0]; r.join = joinNode(r.plan); r.cost = r.plan.match(/cost=[0-9.]+\.\.([0-9.]+)/)[1];
      rows.push(r);
      for (const k of Object.keys(settings)) await run(`RESET ${k}`);
    }
  }
  saveMd("e3_join_algorithms.md", "E3: join algorithms",
    "Same query, same data; only the allowed join algorithm changes (`SET enable_...`). 'Optimiser's choice' is the plan PostgreSQL picked on its own from its cost estimates.",
    h.table(rows, [["Selectivity", "sel"], ["Setting", "algo"], ["Join used", "join"], ["Estimated total cost", "cost"], ["Median ms", "ms"], ["Buffers hit", "buf_hit"]]));
  results.E3 = rows;
}

// ---------------------------------------------------------------------------
// E4. Index types and factors: single vs multi-column, covering, hash (4.1.3.1 "availability and type of indexes")
// ---------------------------------------------------------------------------
{
  await run("CREATE TABLE exp.p4 AS SELECT payment_id, order_id, method, status, amount, created_at FROM konga.payments", "E4 setup");
  await run("ANALYZE exp.p4");
  const q = "SELECT payment_id, amount, created_at FROM exp.p4 WHERE method = 'card' AND status = 'successful' ORDER BY created_at DESC LIMIT 20";
  const rows = [];
  const e4 = async (label, ddl, idx = null) => {
    if (ddl) await run(ddl);
    await run("VACUUM ANALYZE exp.p4");
    const r = await explain(q, label, { runs: 5 });
    r.scan = scanNodes(r.plan); r.sorted = r.plan.includes("Sort Key") ? "yes" : "no";
    r.size = idx ? (await one(`SELECT pg_size_pretty(pg_relation_size('exp.${idx}'))`))[0][0] : "-";
    rows.push(r);
  };
  await e4("1. no index (heap scan)", null);
  await e4("2. single-column B-tree (method)", "CREATE INDEX i_single ON exp.p4 (method)", "i_single");
  await run("DROP INDEX exp.i_single");
  await e4("3. hash index (method)", "CREATE INDEX i_hash ON exp.p4 USING hash (method)", "i_hash");
  await run("DROP INDEX exp.i_hash");
  await e4("4. multi-column B-tree (method, status, created_at DESC)", "CREATE INDEX i_multi ON exp.p4 (method, status, created_at DESC)", "i_multi");
  await run("DROP INDEX exp.i_multi");
  await e4("5. covering (same keys + INCLUDE payment_id, amount)", "CREATE INDEX i_cover ON exp.p4 (method, status, created_at DESC) INCLUDE (payment_id, amount)", "i_cover");
  saveMd("e4_index_types.md", "E4: index types and structure",
    "Query: `" + q + "` (the latest 20 successful card payments; about 28,000 rows match the filter, 150,000-row table). Buffers hit = pages read from cache (logical I/O).",
    h.table(rows, [["Index", "label"], ["Access path", "scan"], ["Sort step needed", "sorted"], ["Index size", "size"], ["Buffers hit", "buf_hit"], ["Median ms", "ms"]]));
  results.E4 = rows;
}

// ---------------------------------------------------------------------------
// E5. Pre-computation: materialised views (4.1.2.3 "materialised views")
// ---------------------------------------------------------------------------
{
  const rows = [];
  const q8 = "SELECT c.customer_id, c.full_name, count(*) AS orders, sum(o.total_amount) AS lifetime_value FROM konga.customers c JOIN konga.orders o ON o.customer_id = c.customer_id WHERE o.status = 'delivered' GROUP BY c.customer_id, c.full_name ORDER BY lifetime_value DESC LIMIT 10";
  rows.push(await explain(q8, "Q8 on base tables (join + aggregate every time)", { save: "e5_q8_base.plan.txt" }));
  await run("CREATE MATERIALIZED VIEW exp.mv_customer_ltv AS SELECT c.customer_id, c.full_name, count(*) AS orders, sum(o.total_amount) AS lifetime_value FROM konga.customers c JOIN konga.orders o ON o.customer_id = c.customer_id WHERE o.status = 'delivered' GROUP BY c.customer_id, c.full_name", "E5 materialised view");
  await run("CREATE INDEX ON exp.mv_customer_ltv (lifetime_value DESC)");
  await run("ANALYZE exp.mv_customer_ltv");
  rows.push(await explain("SELECT customer_id, full_name, orders, lifetime_value FROM exp.mv_customer_ltv ORDER BY lifetime_value DESC LIMIT 10", "Q8 from the materialised view", { save: "e5_q8_mv.plan.txt" }));
  let t0 = Date.now(); await run("REFRESH MATERIALIZED VIEW exp.mv_customer_ltv", "E5 refresh cost"); const refreshMs = Date.now() - t0;
  const q3 = "SELECT p.seller_id, date_trunc('month', o.placed_at) AS month, sum(oi.quantity * oi.unit_price) AS revenue FROM konga.orders o JOIN konga.order_items oi ON oi.order_id = o.order_id JOIN konga.product_variants v ON v.variant_id = oi.variant_id JOIN konga.products p ON p.product_id = v.product_id WHERE o.status = 'delivered' GROUP BY p.seller_id, date_trunc('month', o.placed_at)";
  rows.push(await explain(q3 + " ORDER BY 1, 2 LIMIT 20", "Seller x month revenue report on base tables", { save: "e5_rev_base.plan.txt" }));
  await run("CREATE MATERIALIZED VIEW exp.mv_seller_revenue AS " + q3, "E5 materialised view 2");
  await run("CREATE INDEX ON exp.mv_seller_revenue (seller_id, month)"); await run("ANALYZE exp.mv_seller_revenue");
  rows.push(await explain("SELECT * FROM exp.mv_seller_revenue ORDER BY seller_id, month LIMIT 20", "Seller x month revenue from the materialised view", { save: "e5_rev_mv.plan.txt" }));
  const sz = (await one("SELECT pg_size_pretty(pg_total_relation_size('exp.mv_customer_ltv')), pg_size_pretty(pg_total_relation_size('exp.mv_seller_revenue'))"))[0];
  saveMd("e5_materialised_views.md", "E5: materialised views (pre-computing results)",
    `The two queries that indexes could not speed up (Q8, and an all-seller revenue report) are pre-computed. Cost of the technique: REFRESH of the Q8 view took about ${refreshMs} ms in this run; view sizes ${sz[0]} and ${sz[1]}; the data is only as fresh as the last refresh.`,
    h.table(rows, [["Query", "label"], ["Median ms", "ms"], ["Buffers hit", "buf_hit"]]));
  results.E5 = { rows, refreshMs, sizes: sz };
}

// ---------------------------------------------------------------------------
// E6. Parallelism and memory (4.1.2.3 "parallelism"; 4.1.3.1 memory; 4.1.3.2 memory metric)
// ---------------------------------------------------------------------------
{
  const rows = [];
  const qpar = "SELECT count(*), sum(quantity * unit_price) FROM konga.order_items WHERE unit_price > 20000";
  for (const w of [0, 1, 2, 4]) {
    await run(`SET max_parallel_workers_per_gather = ${w}`);
    const r = await explain(qpar, `max_parallel_workers_per_gather = ${w}`, { runs: 3 });
    r.workers = w; r.parallel = r.plan.includes("Gather") ? "yes" : "no"; rows.push(r);
  }
  await run("RESET max_parallel_workers_per_gather");
  const tblP = h.table(rows, [["Setting", "label"], ["Parallel plan?", "parallel"], ["Median ms", "ms"]]);
  const rows2 = [];
  const sortq = "SELECT order_id, total_amount FROM konga.orders ORDER BY total_amount DESC";
  for (const wm of ["64kB", "1MB", "4MB", "64MB"]) {
    await run(`SET work_mem = '${wm}'`); await run("SET max_parallel_workers_per_gather = 0");
    const r = await explain(sortq, `ORDER BY over 150,000 rows, work_mem = ${wm}`, { runs: 3 }); r.wm = wm; rows2.push(r);
  }
  await run("RESET work_mem"); await run("RESET max_parallel_workers_per_gather");
  const tblM = h.table(rows2, [["work_mem", "wm"], ["Sort method", "sort"], ["Median ms", "ms"]]);
  fs.writeFileSync(path.join(OUT, "e6_parallelism_memory.md"),
    "# E6: parallelism and memory\n\nWorker availability depends on the server configuration and available CPU resources.\n\n## Parallel workers (scan-and-aggregate over the 450,000-row `order_items`)\n\n" + tblP +
    "\n## Memory: sort spilling to disk\n\n" + tblM);
  results.E6 = { par: rows, mem: rows2 };
}

// ---------------------------------------------------------------------------
// E7. File organisation: heap, indexed (B-tree), hash, clustered/sequential, BRIN (4.2.1.2)
// ---------------------------------------------------------------------------
{
  await run("CREATE TABLE exp.items_seq AS SELECT * FROM konga.order_items ORDER BY order_id", "E7 setup: physically sorted by order_id");
  await run("CREATE TABLE exp.items_heap AS SELECT * FROM konga.order_items ORDER BY random()", "E7 setup: random physical order (unordered heap)");
  await run("ANALYZE exp.items_seq"); await run("ANALYZE exp.items_heap");
  const corrSql = "SELECT tablename, round(correlation::numeric,3) FROM pg_stats WHERE schemaname='exp' AND attname='order_id' AND tablename IN ('items_seq','items_heap') ORDER BY 1";
  const corr = Object.fromEntries(await one(corrSql));
  const EX = "SELECT * FROM exp.{t} WHERE order_id = '00000008-0000-4000-8000-000000077777'";
  const RG = "SELECT count(*), sum(quantity) FROM exp.{t} WHERE order_id BETWEEN '00000008-0000-4000-8000-000000070000' AND '00000008-0000-4000-8000-000000071500'";
  const rows = [];
  const e7 = async (label, t, ddl = null, idx = null) => {
    if (ddl) await run(ddl);
    await run(`ANALYZE exp.${t}`);
    const out = {};
    for (const [kind, q] of [["exact match", EX], ["range (1,500 orders)", RG]]) out[kind] = await explain(q.replace("{t}", t), `E7 ${label} / ${kind}`, { runs: 3 });
    const ex = out["exact match"], rg = out["range (1,500 orders)"];
    rows.push({ label, ex_scan: scanNodes(ex.plan), ex_ms: ex.ms, ex_buf: ex.buf_hit, rg_scan: scanNodes(rg.plan), rg_ms: rg.ms, rg_buf: rg.buf_hit,
                size: idx ? (await one(`SELECT pg_size_pretty(pg_relation_size('exp.${idx}'))`))[0][0] : "-" });
  };
  await e7("Heap (unordered), no index", "items_heap");
  await e7("Heap + B-tree index (indexed organisation, scattered rows)", "items_heap", "CREATE INDEX ih_btree ON exp.items_heap (order_id)", "ih_btree");
  await e7("Heap + hash index", "items_heap", "DROP INDEX exp.ih_btree; CREATE INDEX ih_hash ON exp.items_heap USING hash (order_id)", "ih_hash");
  await run("DROP INDEX exp.ih_hash"); await run("CREATE INDEX ih_btree2 ON exp.items_heap (order_id)");
  await run("CLUSTER exp.items_heap USING ih_btree2", "E7: CLUSTER = physically sort the table by the index key (sequential / clustered organisation)");
  await e7("Clustered on order_id + B-tree", "items_heap", null, "ih_btree2");
  await run("DROP INDEX exp.ih_btree2");
  await e7("Sorted table + BRIN index (block-range)", "items_seq", "CREATE INDEX is_brin ON exp.items_seq USING brin (order_id)", "is_brin");
  const corrAfter = Object.fromEntries(await one(corrSql));
  saveMd("e7_file_organisation.md", "E7: file organisation (heap, indexed, hash, clustered, BRIN)",
    `Table: copy of \`order_items\` (450,000 rows). Physical-order correlation of \`order_id\` (1.0 = perfectly sorted on disk): random heap ${corr.items_heap}, sorted copy ${corr.items_seq}; after CLUSTER the heap table has ${corrAfter.items_heap}. Buffers = pages read from cache (logical I/O).`,
    h.table(rows, [["File organisation", "label"], ["Index size", "size"], ["Exact-match access path", "ex_scan"], ["Exact ms", "ex_ms"], ["Exact buffers", "ex_buf"],
                   ["Range access path", "rg_scan"], ["Range ms", "rg_ms"], ["Range buffers", "rg_buf"]]));
  results.E7 = { rows, corr, corrAfter };
}

// ---------------------------------------------------------------------------
// E9. Estimated vs actual rows for Q1-Q8 (cost estimates vs actual costs, 4.1.3.2)
// ---------------------------------------------------------------------------
{
  // Largest estimate error among scan/join/aggregate nodes that ran once and were not cut short by a LIMIT.
  const worstError = (plan) => {
    const stack = []; let worst = [1.0, ""];
    for (const ln of plan.split("\n")) {
      const m = ln.match(/^(\s*)(?:->\s*)?(.*?)\s+\(cost=[0-9.]+\.\.[0-9.]+ rows=(\d+) width=\d+\) \(actual time=[0-9.]+\.\.[0-9.]+ rows=(\d+) loops=(\d+)\)/);
      if (!m) continue;
      const indent = m[1].length + (ln.slice(0, m[1].length + 3).includes("->") ? 3 : 0);
      while (stack.length && stack[stack.length - 1][0] >= indent) stack.pop();
      const parent = stack.length ? stack[stack.length - 1][1] : "";
      stack.push([indent, m[2]]);
      const [name, est, act, loops] = [m[2], Number(m[3]), Number(m[4]), Number(m[5])];
      if (loops !== 1 || /^(Sort|Limit|Gather)/.test(name) || parent.startsWith("Limit")) continue;
      let ratio = Math.max(act, 1) / Math.max(est, 1); ratio = Math.max(ratio, 1 / ratio);
      if (ratio > worst[0]) worst = [ratio, name.slice(0, 45)];
    }
    return `${worst[0].toFixed(1)}x (${worst[1]})`;
  };
  const qdir = path.join(here, "..", "queries");
  const rows = [];
  for (const f of fs.readdirSync(qdir).filter((x) => /^q.*\.sql$/.test(x)).sort()) {
    const sql = fs.readFileSync(path.join(qdir, f), "utf8").split("\n").filter((l) => !l.startsWith("--")).join("\n");
    const r = await explain(sql, "E9 " + f.replace(/\.sql$/, ""), { runs: 1 });
    r.q = f.slice(0, 2).toUpperCase(); r.worst = worstError(r.plan); rows.push(r);
  }
  saveMd("e9_estimate_vs_actual.md", "E9: estimated vs actual row counts (cost-estimate accuracy)",
    "Large gaps between estimated and actual rows point to outdated statistics or a poor model (Study Session 4, 4.1.3.2). 'Worst node' is the largest estimate error among scan, join and aggregate nodes that ran once and were not cut short by a LIMIT (a LIMIT stops a scan early, which makes actual rows smaller than estimated without the estimate being wrong).",
    h.table(rows, [["Query", "q"], ["Median ms (1 run)", "ms"], ["Worst node estimate error", "worst"]]));
  results.E9 = rows;
}

// Summary numbers without the (large) plan text
const strip = (v) => Array.isArray(v) ? v.map(strip) : v && typeof v === "object" ? Object.fromEntries(Object.entries(v).filter(([k]) => k !== "plan").map(([k, x]) => [k, strip(x)])) : v;
fs.writeFileSync(path.join(OUT, "results.json"), JSON.stringify(strip(results), null, 1));
} finally {
  await db.end();
}
console.log("experiments finished");
