export function slug(s) {
  return s.trim().toLowerCase().replace(/\s+/g, '-');
}

export function dedash(s) {
  return s.replace(/-+/g, ' ');
}

export function wordCount(s) {
  const trimmed = s.trim();
  if (trimmed === '') return 0;
  return trimmed.split(/\s+/).length;
}
