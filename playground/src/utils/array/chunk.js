export function first(a) {
  return a[0];
}

export function last(a) {
  return a[a.length - 1];
}

export function sum(a) {
  return a.reduce((x, y) => x + y, 0);
}

export function includes(a, v) {
  return a.includes(v);
}
