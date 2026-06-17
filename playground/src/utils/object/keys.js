export function keyCount(obj) {
  return Object.keys(obj).length;
}

export function firstKey(obj) {
  return Object.keys(obj)[0];
}

export function hasKey(obj, k) {
  return Object.prototype.hasOwnProperty.call(obj, k);
}
