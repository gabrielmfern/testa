import { clamp, roundTo, isEven } from "./round.js";

test("clamp(5, 0, 10) -> 5", () => {
  expect(clamp(5, 0, 10)).toBe(5);
});

test("clamp(-1, 0, 10) -> 0", () => {
  expect(clamp(-1, 0, 10)).toBe(0);
});

test("clamp(99, 0, 10) -> 10", () => {
  expect(clamp(99, 0, 10)).toBe(10);
});

test("roundTo(1.2345, 2) -> 1.23", () => {
  expect(roundTo(1.2345, 2)).toBe(1.23);
});

test("roundTo(1.005, 1) -> 1", () => {
  expect(roundTo(1.005, 1)).toBe(1);
});

test("isEven(4) -> true", () => {
  expect(isEven(4)).toBe(true);
});

test("isEven(3) -> false", () => {
  expect(isEven(3)).toBe(false);
});
