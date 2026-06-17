import { pairCount, dot, sameLength, zipString } from "./zip.js";

test("pairCount([1, 2], [3, 4, 5]) -> 2", () => {
  expect(pairCount([1, 2], [3, 4, 5])).toBe(2);
});

test("pairCount([], [1]) -> 0", () => {
  expect(pairCount([], [1])).toBe(0);
});

test("dot([1, 2, 3], [4, 5, 6]) -> 32", () => {
  expect(dot([1, 2, 3], [4, 5, 6])).toBe(32);
});

test("dot([1, 2], [3, 4, 5]) -> 11", () => {
  expect(dot([1, 2], [3, 4, 5])).toBe(11);
});

test("sameLength([1, 2], [3, 4]) -> true", () => {
  expect(sameLength([1, 2], [3, 4])).toBe(true);
});

test("sameLength([1], [2, 3]) -> false", () => {
  expect(sameLength([1], [2, 3])).toBe(false);
});

test("zipString([1, 2], ['a', 'b']) -> '1:a,2:b'", () => {
  expect(zipString([1, 2], ["a", "b"])).toBe("1:a,2:b");
});

test("zipString([1, 2, 3], ['a']) -> '1:a'", () => {
  expect(zipString([1, 2, 3], ["a"])).toBe("1:a");
});
