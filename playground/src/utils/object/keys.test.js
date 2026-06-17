import { keyCount, firstKey, hasKey } from "./keys.js";

test("keyCount({ a: 1, b: 2 }) -> 2", () => {
  expect(keyCount({ a: 1, b: 2 })).toBe(2);
});

test("keyCount({  }) -> 0", () => {
  expect(keyCount({  })).toBe(0);
});

test("firstKey({ a: 1, b: 2 }) -> \"a\"", () => {
  expect(firstKey({ a: 1, b: 2 })).toBe("a");
});

test("firstKey({  }) -> undefined", () => {
  expect(firstKey({  })).toBe(undefined);
});

test("hasKey({ a: 1 }, \"a\") -> true", () => {
  expect(hasKey({ a: 1 }, "a")).toBe(true);
});

test("hasKey({ a: 1 }, \"z\") -> false", () => {
  expect(hasKey({ a: 1 }, "z")).toBe(false);
});

test("hasKey({ x: 0 }, \"x\") -> true", () => {
  expect(hasKey({ x: 0 }, "x")).toBe(true);
});
