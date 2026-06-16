export function clamp(n, lo, hi) {
  return Math.min(hi, Math.max(lo, n));
}

export function roundTo(n, d) {
  const f = 10 ** d; return Math.round(n * f) / f;
}

export function isEven(n) {
  return n % 2 === 0;
}
