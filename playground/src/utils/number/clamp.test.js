import { clamp, min, max, sign } from "./clamp.js";

test("clamp(5, 0, 10) -> 5", () => {
  expect(clamp(5, 0, 10)).toBe(5);
});

test("clamp(-3, 0, 10) -> 0", () => {
  expect(clamp(-3, 0, 10)).toBe(0);
});

test("clamp(42, 0, 10) -> 10", () => {
  expect(clamp(42, 0, 10)).toBe(10);
});

test("min(2, 7) -> 2", () => {
  expect(min(2, 7)).toBe(2);
});

test("max(2, 7) -> 7", () => {
  expect(max(2, 7)).toBe(7);
});

test("sign(8) -> 1", () => {
  expect(sign(8)).toBe(1);
});

test("sign(-8) -> -1", () => {
  expect(sign(-8)).toBe(-1);
});

test("sign(0) -> 0", () => {
  expect(sign(0)).toBe(0);
});
