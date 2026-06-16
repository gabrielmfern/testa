export function withTax(amount, rate) {
  return Math.round(amount * (1 + rate));
}

export function tier(spend) {
  return spend >= 1000 ? 'gold' : spend >= 100 ? 'silver' : 'bronze';
}
