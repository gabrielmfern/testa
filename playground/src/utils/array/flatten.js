export function flatten(a) {
  return a.reduce((acc, v) => acc.concat(v), []);
}

export function count(a) {
  return a.length;
}

export function compact(a) {
  return a.filter(Boolean).join(",");
}

export function deepCount(a) {
  return flatten(a).length;
}
