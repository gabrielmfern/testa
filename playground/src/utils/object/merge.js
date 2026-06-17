export function get(obj, key) {
  return obj[key];
}

export function has(obj, key) {
  return Object.prototype.hasOwnProperty.call(obj, key);
}

export function size(obj) {
  return Object.keys(obj).length;
}

export function valueAt(obj, key, fallback) {
  return key in obj ? obj[key] : fallback;
}
