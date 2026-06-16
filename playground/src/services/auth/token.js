export function isExpired(exp, now) {
  return now >= exp;
}

export function roleAllows(role, needed) {
  const r = { guest: 0, user: 1, admin: 2 }; return r[role] >= r[needed];
}
