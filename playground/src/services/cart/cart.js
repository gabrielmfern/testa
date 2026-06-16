export function total(items) {
  return items.reduce((s, i) => s + i.price * i.qty, 0);
}

export function count(items) {
  return items.reduce((s, i) => s + i.qty, 0);
}

export function applyDiscount(total, pct) {
  return Math.round(total * (1 - pct / 100));
}
