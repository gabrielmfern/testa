import { get, has, size, valueAt } from "./merge.js";

test("get({ a: 1 }, \"a\") -> 1", () => {
  expect(get({ a: 1 }, "a")).toBe(1);
});

test("get({ a: 1 }, \"b\") -> undefined", () => {
  expect(get({ a: 1 }, "b")).toBe(undefined);
});

test("has({ a: 1 }, \"a\") -> true", () => {
  expect(has({ a: 1 }, "a")).toBe(true);
});

test("has({ a: 1 }, \"b\") -> false", () => {
  expect(has({ a: 1 }, "b")).toBe(false);
});

test("size({ a: 1, b: 2, c: 3 }) -> 3", () => {
  expect(size({ a: 1, b: 2, c: 3 })).toBe(3);
});

test("size({  }) -> 0", () => {
  expect(size({  })).toBe(0);
});

test("valueAt({ a: 1 }, \"a\", 0) -> 1", () => {
  expect(valueAt({ a: 1 }, "a", 0)).toBe(1);
});

test("valueAt({  }, \"x\", 9) -> 9", () => {
  expect(valueAt({  }, "x", 9)).toBe(9);
});
