import { has, size, getOr } from "./pick.js";

test("has({ a: 1 }, \"a\") -> true", () => {
  expect(has({ a: 1 }, "a")).toBe(true);
});

test("has({ a: 1 }, \"b\") -> false", () => {
  expect(has({ a: 1 }, "b")).toBe(false);
});

test("size({ a: 1, b: 2 }) -> 2", () => {
  expect(size({ a: 1, b: 2 })).toBe(2);
});

test("size({  }) -> 0", () => {
  expect(size({  })).toBe(0);
});

test("getOr({ a: 1 }, \"a\", 0) -> 1", () => {
  expect(getOr({ a: 1 }, "a", 0)).toBe(1);
});

test("getOr({  }, \"x\", 9) -> 9", () => {
  expect(getOr({  }, "x", 9)).toBe(9);
});
