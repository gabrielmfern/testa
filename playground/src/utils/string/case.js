export function capitalize(s) {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export function kebab(s) {
  return s.replace(/([a-z])([A-Z])/g, '$1-$2').replace(/\s+/g, '-').toLowerCase();
}

export function snake(s) {
  return s.replace(/([a-z])([A-Z])/g, '$1_$2').replace(/\s+/g, '_').toLowerCase();
}
