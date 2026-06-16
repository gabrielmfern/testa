import { count, uniqCount, isEmpty } from "./uniq.js";

test("count([1, 1, 2]) -> 3", () => {
  expect(count([1, 1, 2])).toBe(3);
});

test("uniqCount([1, 1, 2]) -> 2", () => {
  expect(uniqCount([1, 1, 2])).toBe(2);
});

test("uniqCount([]) -> 0", () => {
  expect(uniqCount([])).toBe(0);
});

test("isEmpty([]) -> true", () => {
  expect(isEmpty([])).toBe(true);
});

test("isEmpty([1]) -> false", () => {
  expect(isEmpty([1])).toBe(false);
});
