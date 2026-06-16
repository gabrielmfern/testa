import { first, last, sum, includes } from "./chunk.js";

test("first([1, 2, 3]) -> 1", () => {
  expect(first([1, 2, 3])).toBe(1);
});

test("first([]) -> undefined", () => {
  expect(first([])).toBe(undefined);
});

test("last([1, 2, 3]) -> 3", () => {
  expect(last([1, 2, 3])).toBe(3);
});

test("sum([1, 2, 3]) -> 6", () => {
  expect(sum([1, 2, 3])).toBe(6);
});

test("sum([]) -> 0", () => {
  expect(sum([])).toBe(0);
});

test("includes([1, 2], 2) -> true", () => {
  expect(includes([1, 2], 2)).toBe(true);
});

test("includes([1, 2], 9) -> false", () => {
  expect(includes([1, 2], 9)).toBe(false);
});
