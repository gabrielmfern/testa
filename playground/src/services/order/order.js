export function subtotal(items) {
  return items.reduce((s, i) => s + i.price * i.qty, 0);
}

export function withShipping(subtotal, fee) {
  return subtotal + fee;
}

export function freeShipping(subtotal, threshold) {
  return subtotal >= threshold;
}
