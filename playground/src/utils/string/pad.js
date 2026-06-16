export function padLeft(s, n, c = ' ') {
  return s.padStart(n, c);
}

export function truncate(s, n) {
  return s.length <= n ? s : s.slice(0, n - 1) + '\u2026';
}

export function repeat(s, n) {
  return s.repeat(n);
}
