// Edit distance algorithms, all written from scratch.

// Levenshtein: insert, delete, substitute (each cost 1).
// ponytail: two-row DP, O(min(a,b)) space. Full matrix only if you need the alignment path.
export function levenshtein(a, b) {
  if (a === b) return 0;
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;
  // keep the shorter string as the inner dimension
  if (a.length < b.length) [a, b] = [b, a];

  let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
  let curr = new Array(b.length + 1);
  for (let i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      curr[j] = Math.min(
        prev[j] + 1, // delete
        curr[j - 1] + 1, // insert
        prev[j - 1] + cost, // substitute
      );
    }
    [prev, curr] = [curr, prev];
  }
  return prev[b.length];
}

// Optimal string alignment (restricted Damerau-Levenshtein): adds adjacent
// transposition, but no substring is edited more than once.
export function osaDistance(a, b) {
  if (a === b) return 0;
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;

  // full matrix: transposition needs the row two back
  const d = Array.from({ length: a.length + 1 }, () => new Array(b.length + 1).fill(0));
  for (let i = 0; i <= a.length; i++) d[i][0] = i;
  for (let j = 0; j <= b.length; j++) d[0][j] = j;

  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      d[i][j] = Math.min(
        d[i - 1][j] + 1,
        d[i][j - 1] + 1,
        d[i - 1][j - 1] + cost,
      );
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) {
        d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
      }
    }
  }
  return d[a.length][b.length];
}

// True (unrestricted) Damerau-Levenshtein with adjacent transpositions.
// Uses the full algorithm with a "last seen row per character" table.
export function damerauLevenshtein(a, b) {
  if (a === b) return 0;
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;

  const INF = a.length + b.length;
  const da = new Map(); // char -> last row it appeared in
  // matrix padded by 1 on top/left for the boundary row/col
  const d = Array.from({ length: a.length + 2 }, () => new Array(b.length + 2).fill(0));
  d[0][0] = INF;
  for (let i = 0; i <= a.length; i++) {
    d[i + 1][0] = INF;
    d[i + 1][1] = i;
  }
  for (let j = 0; j <= b.length; j++) {
    d[0][j + 1] = INF;
    d[1][j + 1] = j;
  }

  for (let i = 1; i <= a.length; i++) {
    let db = 0; // last col in this row where chars matched
    for (let j = 1; j <= b.length; j++) {
      const k = da.get(b[j - 1]) ?? 0; // last row b[j-1] was seen
      const l = db;
      let cost = 1;
      if (a[i - 1] === b[j - 1]) {
        cost = 0;
        db = j;
      }
      d[i + 1][j + 1] = Math.min(
        d[i][j] + cost, // substitute / match
        d[i + 1][j] + 1, // insert
        d[i][j + 1] + 1, // delete
        d[k][l] + (i - k - 1) + 1 + (j - l - 1), // transpose
      );
    }
    da.set(a[i - 1], i);
  }
  return d[a.length + 1][b.length + 1];
}

// Hamming: substitutions only, strings must be equal length.
export function hamming(a, b) {
  if (a.length !== b.length) throw new Error("hamming: strings must be equal length");
  let dist = 0;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) dist++;
  return dist;
}

// LCS edit distance: insert and delete only (no substitution).
// Equals a.length + b.length - 2 * |LCS|.
export function lcsDistance(a, b) {
  if (a === b) return 0;
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;
  if (a.length < b.length) [a, b] = [b, a];

  let prev = new Array(b.length + 1).fill(0);
  let curr = new Array(b.length + 1).fill(0);
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      curr[j] = a[i - 1] === b[j - 1]
        ? prev[j - 1] + 1
        : Math.max(prev[j], curr[j - 1]);
    }
    [prev, curr] = [curr, prev];
  }
  const lcs = prev[b.length];
  return a.length + b.length - 2 * lcs;
}
