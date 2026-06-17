export function toInt(s) {
  return parseInt(s, 10);
}

export function toFloat(s) {
  return parseFloat(s);
}

export function isNumeric(s) {
  if (typeof s !== "string" || s.trim() === "") return false;
  return !Number.isNaN(Number(s));
}
