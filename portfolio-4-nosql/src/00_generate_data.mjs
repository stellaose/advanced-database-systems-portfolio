#!/usr/bin/env node
// Generate product and purchase data for the marketplace model introduced in Portfolio 1.
// Save products.json and purchases.csv using a fixed random seed so the data can be reproduced.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { rng } from './harness.mjs';

const DATA = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'data');
fs.mkdirSync(DATA, { recursive: true });
const R = rng(8103);
const round = (x, d) => Math.round(x * 10 ** d) / 10 ** d;

const N_PRODUCTS = 2000, N_CUSTOMERS = 2000, N_SELLERS = 50;
const CATS = {
  Phones: { brands: ['Tecno', 'Infinix', 'Samsung', 'Itel', 'Xiaomi'], base: [60000, 450000] },
  Laptops: { brands: ['HP', 'Lenovo', 'Dell', 'Asus', 'Acer'], base: [250000, 1500000] },
  Fashion: { brands: ['Ankara House', 'Lagos Wear', 'Urban Thread', 'Zuri'], base: [5000, 60000] },
  Appliances: { brands: ['Hisense', 'LG', 'Binatone', 'Scanfrost'], base: [25000, 400000] },
};
const catNames = Object.keys(CATS);

function attrs(cat) {
  if (cat === 'Phones')
    return { ram_gb: R.choice([2, 4, 6, 8, 12]), storage_gb: R.choice([32, 64, 128, 256]), network: R.choice(['4G', '5G']),
             screen_in: round(R.uniform(5.5, 6.9), 1), dual_sim: R() < 0.8 };
  if (cat === 'Laptops')
    return { cpu: R.choice(['Core i3', 'Core i5', 'Core i7', 'Ryzen 5', 'Ryzen 7']), ram_gb: R.choice([4, 8, 16, 32]),
             storage_gb: R.choice([256, 512, 1024]), screen_in: R.choice([13.3, 14.0, 15.6]) };
  if (cat === 'Fashion')
    return { sizes: R.sample(['S', 'M', 'L', 'XL', 'XXL'], R.int(2, 4)), colour: R.choice(['red', 'blue', 'green', 'black', 'gold']),
             material: R.choice(['cotton', 'ankara', 'linen', 'polyester']) };
  return { power_w: R.choice([50, 100, 500, 1200, 2000]), capacity_l: R.choice([0, 20, 50, 120, 250]), warranty_months: R.choice([6, 12, 24]) };
}

const products = [];
for (let pid = 1; pid <= N_PRODUCTS; pid++) {
  const cat = R.choice(catNames), c = CATS[cat];
  const price = round(R.uniform(...c.base), -2);
  const brand = R.choice(c.brands);
  const nVar = R.int(2, 4) - 1;                       // 1..3 variants
  products.push({
    _id: pid, seller_id: R.int(1, N_SELLERS), name: `${brand} ${cat.endsWith('s') ? cat.slice(0, -1) : cat} ${pid}`,
    brand, category: cat, status: R.weighted(['live', 'draft'], [0.95, 0.05]),
    attributes: attrs(cat),
    variants: Array.from({ length: nVar }, (_, i) => ({ sku: `P${pid}-V${i + 1}`, price: price + (i + 1) * 1000, stock: R.int(0, 80) })),
    tags: R.sample(['new', 'popular', 'bargain', 'imported', 'official-store'], R.int(0, 3)),
    rating_avg: round(R.uniform(2.5, 5.0), 1), rating_count: R.int(0, 400),
  });
}
fs.writeFileSync(path.join(DATA, 'products.json'), JSON.stringify(products));

const byCat = {};
for (const p of products) (byCat[p.category] ||= []).push(p._id);
const seen = new Map();                                // one row per (customer, product)
for (let cid = 1; cid <= N_CUSTOMERS; cid++) {
  const fav = R.choice(catNames);
  const n = R.int(3, 12);
  for (let i = 0; i < n; i++) {
    const cat = R() < 0.7 ? fav : R.choice(catNames);
    const pid = R.choice(byCat[cat]), q = R.int(1, 3);
    const key = `${cid},${pid}`;
    if (!seen.has(key)) seen.set(key, [cid, pid, q]);
  }
}
const rows = [...seen.values()].sort((a, b) => a[0] - b[0] || a[1] - b[1]);
fs.writeFileSync(path.join(DATA, 'purchases.csv'), 'customer_id,product_id,quantity\n' + rows.map((r) => r.join(',')).join('\n') + '\n');
console.log(`${products.length} products, ${N_CUSTOMERS} customers, ${rows.length} purchases`);
