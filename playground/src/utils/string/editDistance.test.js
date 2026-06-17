import {
  levenshtein,
  osaDistance,
  damerauLevenshtein,
  hamming,
  lcsDistance,
} from "./editDistance.js";

// --- levenshtein ---
test("levenshtein identical -> 0", () => {
  expect(levenshtein("abc", "abc")).toBe(0);
});

test("levenshtein empty -> other length", () => {
  expect(levenshtein("", "abc")).toBe(3);
  expect(levenshtein("abc", "")).toBe(3);
});

test("levenshtein kitten/sitting -> 3", () => {
  expect(levenshtein("kitten", "sitting")).toBe(3);
});

test("levenshtein is symmetric", () => {
  expect(levenshtein("flaw", "lawn")).toBe(levenshtein("lawn", "flaw"));
});

test("levenshtein single substitution -> 1", () => {
  expect(levenshtein("cat", "bat")).toBe(1);
});

// --- osa (restricted damerau) ---
test("osa transposition -> 1", () => {
  expect(osaDistance("ca", "ac")).toBe(1);
});

test("osa ca/abc -> 3 (restricted: no double edit)", () => {
  // classic case where OSA differs from true Damerau (which gives 2)
  expect(osaDistance("ca", "abc")).toBe(3);
});

test("osa matches levenshtein when no transpositions", () => {
  expect(osaDistance("kitten", "sitting")).toBe(3);
});

// --- damerau-levenshtein (unrestricted) ---
test("damerau transposition -> 1", () => {
  expect(damerauLevenshtein("ca", "ac")).toBe(1);
});

test("damerau ca/abc -> 2 (allows reuse)", () => {
  expect(damerauLevenshtein("ca", "abc")).toBe(2);
});

test("damerau identical -> 0", () => {
  expect(damerauLevenshtein("abc", "abc")).toBe(0);
});

test("damerau <= levenshtein", () => {
  const a = "a cat";
  const b = "an act";
  expect(damerauLevenshtein(a, b)).toBeLessThanOrEqual(levenshtein(a, b));
});

// --- hamming ---
test("hamming equal-length diff -> count", () => {
  expect(hamming("karolin", "kathrin")).toBe(3);
});

test("hamming identical -> 0", () => {
  expect(hamming("abc", "abc")).toBe(0);
});

test("hamming throws on length mismatch", () => {
  expect(() => hamming("abc", "ab")).toThrow();
});

// --- lcs distance ---
test("lcs distance identical -> 0", () => {
  expect(lcsDistance("abc", "abc")).toBe(0);
});

test("lcs distance substitution counts as 2", () => {
  // one substitution = one delete + one insert
  expect(lcsDistance("cat", "bat")).toBe(2);
});

test("lcs distance kitten/sitting -> 5", () => {
  expect(lcsDistance("kitten", "sitting")).toBe(5);
});

test("lcs distance empty -> other length", () => {
  expect(lcsDistance("", "abc")).toBe(3);
});
