// Shared helpers for the Portfolio 4 scripts: timing and a small seeded random generator.
import { performance } from 'node:perf_hooks';

/** Median and 95th-percentile latency in ms of an (async) fn over `runs` calls after `warm` warm-ups. */
export async function bench(fn, runs = 30, warm = 3) {
  for (let i = 0; i < warm; i++) await fn();
  const t = [];
  for (let i = 0; i < runs; i++) {
    const s = performance.now();
    await fn();
    t.push(performance.now() - s);
  }
  t.sort((a, b) => a - b);
  const mid = t.length >> 1;
  const median = t.length % 2 ? t[mid] : (t[mid - 1] + t[mid]) / 2;
  return [median, t[Math.floor(0.95 * (t.length - 1))]];
}

export const h = (title) => console.log(`\n=== ${title} ===`);
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** mulberry32: a small deterministic PRNG, so the same seed always gives the same data. */
export function rng(seed) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  next.int = (lo, hi) => lo + Math.floor(next() * (hi - lo + 1));     // inclusive both ends
  next.uniform = (lo, hi) => lo + next() * (hi - lo);
  next.choice = (arr) => arr[Math.floor(next() * arr.length)];
  next.sample = (arr, k) => {
    const c = [...arr];
    for (let i = 0; i < k; i++) { const j = i + Math.floor(next() * (c.length - i)); [c[i], c[j]] = [c[j], c[i]]; }
    return c.slice(0, k);
  };
  next.weighted = (items, weights) => {
    const total = weights.reduce((a, b) => a + b, 0);
    let x = next() * total;
    for (let i = 0; i < items.length; i++) { x -= weights[i]; if (x < 0) return items[i]; }
    return items[items.length - 1];
  };
  return next;
}
