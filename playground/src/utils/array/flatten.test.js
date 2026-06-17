import { flatten, count, compact, deepCount } from "./flatten.js";

test("flatten([[1], [2, 3]]) length -> 3", () => {
  expect(flatten([[1], [2, 3]]).length).toBe(3);
});

test("flatten([[1], [2, 3]]) -> [1,2,3]", () => {
  expect(JSON.stringify(flatten([[1], [2, 3]]))).toBe("[1,2,3]");
});

test("flatten([[1, [2]], [3]]) one level -> [1,[2],3]", () => {
  expect(JSON.stringify(flatten([[1, [2]], [3]]))).toBe("[1,[2],3]");
});

test("count([1, 2, 3]) -> 3", () => {
  expect(count([1, 2, 3])).toBe(3);
});

test("count([]) -> 0", () => {
  expect(count([])).toBe(0);
});

test("compact([1, 0, 2, null, 3]) -> '1,2,3'", () => {
  expect(compact([1, 0, 2, null, 3])).toBe("1,2,3");
});

test("compact([0, false, '']) -> ''", () => {
  expect(compact([0, false, ""])).toBe("");
});

test("deepCount([[1], [2, 3]]) -> 3", () => {
  expect(deepCount([[1], [2, 3]])).toBe(3);
});
