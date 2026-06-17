export function pairCount(a, b) {
  return Math.min(a.length, b.length);
}

export function dot(a, b) {
  let total = 0;
  for (let i = 0; i < pairCount(a, b); i++) {
    total += a[i] * b[i];
  }
  return total;
}

export function sameLength(a, b) {
  return a.length === b.length;
}

export function zipString(a, b) {
  const out = [];
  for (let i = 0; i < pairCount(a, b); i++) {
    out.push(`${a[i]}:${b[i]}`);
  }
  return out.join(",");
}
