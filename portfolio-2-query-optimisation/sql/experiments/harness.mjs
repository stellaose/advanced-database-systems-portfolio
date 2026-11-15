// Small measurement harness for the Portfolio 2 experiments (Node.js).
// - explain(): runs EXPLAIN (ANALYZE, BUFFERS) 1 warm-up + `runs` timed runs and returns the median time, the last plan text
//   and parsed facts (estimated vs actual rows at the top node, buffer hits/reads, sort method).
// - Every SQL statement executed is appended to evidence/experiments/executed-sql.sql.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";

const here = path.dirname(fileURLToPath(import.meta.url));
export const OUT = process.env.EXPERIMENT_OUT_DIR ?? path.join(here, "..", "..", "evidence", "experiments");
fs.mkdirSync(OUT, { recursive: true });
const LOG = path.join(OUT, "executed-sql.sql");

// KONGA_PG_* overrides the standard libpq environment variables.
export async function connect() {
  const client = new pg.Client({
    host: process.env.KONGA_PG_HOST ?? process.env.PGHOST ?? "/tmp",
    port: Number(process.env.KONGA_PG_PORT ?? process.env.PGPORT ?? 5432),
    user: process.env.KONGA_PG_USER ?? process.env.PGUSER ?? process.env.USER,
    database: process.env.KONGA_PG_DB ?? process.env.PGDATABASE ?? "konga_p2",
    password: process.env.KONGA_PG_PASSWORD ?? process.env.PGPASSWORD,
  });
  await client.connect();
  return client;
}

export const median = (xs) => { const s = [...xs].sort((a, b) => a - b), m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };

export async function run(db, sql, label = "") {
  fs.appendFileSync(LOG, `-- ${label}\n${sql.trim().replace(/;$/, "")};\n\n`);
  return db.query({ text: sql, rowMode: "array" });
}

export async function explain(db, sql, label, { runs = 3, save = null } = {}) {
  const q = sql.trim().replace(/;$/, "");
  fs.appendFileSync(LOG, `-- ${label}\nEXPLAIN (ANALYZE, BUFFERS) ${q};\n\n`);
  const times = []; let plan = "";
  for (let i = 0; i <= runs; i++) {                          // run 0 is a warm-up and is discarded
    const r = await db.query({ text: `EXPLAIN (ANALYZE, BUFFERS) ${q}`, rowMode: "array" });
    plan = r.rows.map((x) => x[0]).join("\n");
    if (i > 0) times.push(parseFloat(plan.match(/Execution Time: ([0-9.]+)/)[1]));
  }
  const top = plan.match(/\(cost=[0-9.]+\.\.([0-9.]+) rows=(\d+) .*?\) \(actual time=[0-9.]+\.\.[0-9.]+ rows=(\d+)/);
  const rootBuffers = plan.split("\n").find((line) => /^  Buffers:/.test(line)) ?? "";
  const shared = rootBuffers.match(/shared ((?:(?:hit|read|dirtied|written)=\d+\s*)+)/)?.[1] ?? "";
  const counter = (name) => Number(shared.match(new RegExp(`${name}=(\\d+)`))?.[1] ?? 0);
  const sort = plan.match(/Sort Method: ([^\n]*)/);
  const res = {
    label, ms: Math.round(median(times) * 1000) / 1000, est_rows: top ? Number(top[2]) : null, act_rows: top ? Number(top[3]) : null,
    buf_hit: counter("hit"), buf_read: counter("read"), sort: sort ? sort[1].trim() : "",
    first_node: plan.split("\n")[0].trim().slice(0, 90), plan,
  };
  if (save) fs.writeFileSync(path.join(OUT, save), `-- ${label}\n-- ${q}\n\n${plan}\n`);
  return res;
}

export function table(rows, cols) {
  const head = "| " + cols.map(([h]) => h).join(" | ") + " |\n|" + "---|".repeat(cols.length) + "\n";
  return head + rows.map((r) => "| " + cols.map(([, k]) => r[k] ?? "").join(" | ") + " |").join("\n") + "\n";
}
