export function isEmail(s) {
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(s);
}

export function isBlank(s) {
  return s.trim().length === 0;
}

export function inRange(n, lo, hi) {
  return n >= lo && n <= hi;
}
