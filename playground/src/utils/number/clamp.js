export function clamp(x, lo, hi) {
  if (x < lo) return lo;
  if (x > hi) return hi;
  return x;
}

export function min(a, b) {
  return a < b ? a : b;
}

export function max(a, b) {
  return a > b ? a : b;
}

export function sign(x) {
  if (x > 0) return 1;
  if (x < 0) return -1;
  return 0;
}
