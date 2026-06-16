export function count(a) {
  return a.length;
}

export function uniqCount(a) {
  return new Set(a).size;
}

export function isEmpty(a) {
  return a.length === 0;
}
