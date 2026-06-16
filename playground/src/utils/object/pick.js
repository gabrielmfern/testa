export function has(o, k) {
  return Object.prototype.hasOwnProperty.call(o, k);
}

export function size(o) {
  return Object.keys(o).length;
}

export function getOr(o, k, d) {
  return k in o ? o[k] : d;
}
