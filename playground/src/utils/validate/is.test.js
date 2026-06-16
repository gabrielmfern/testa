import { isEmail, isBlank, inRange } from "./is.js";

test("isEmail(\"a@b.com\") -> true", () => {
  expect(isEmail("a@b.com")).toBe(true);
});

test("isEmail(\"nope\") -> false", () => {
  expect(isEmail("nope")).toBe(false);
});

test("isBlank(\"  \") -> true", () => {
  expect(isBlank("  ")).toBe(true);
});

test("isBlank(\"x\") -> false", () => {
  expect(isBlank("x")).toBe(false);
});

test("inRange(5, 1, 10) -> true", () => {
  expect(inRange(5, 1, 10)).toBe(true);
});

test("inRange(0, 1, 10) -> false", () => {
  expect(inRange(0, 1, 10)).toBe(false);
});
