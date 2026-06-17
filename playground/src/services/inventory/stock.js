export function inStock(qty) {
  return qty > 0;
}

export function reorder(qty, threshold) {
  return qty <= threshold;
}

export function available(stock, reserved) {
  return stock - reserved;
}
