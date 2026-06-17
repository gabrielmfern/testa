export function truncate(s, n) {
  return s.slice(0, n);
}

export function ellipsis(s, n) {
  if (s.length <= n) return s;
  return s.slice(0, n) + "...";
}

export function startsWith(s, p) {
  return s.slice(0, p.length) === p;
}
