import { isLeap, daysInMonth } from "./fmt.js";

test("isLeap(2000) -> true", () => {
  expect(isLeap(2000)).toBe(true);
});

test("isLeap(1900) -> false", () => {
  expect(isLeap(1900)).toBe(false);
});

test("isLeap(2024) -> true", () => {
  expect(isLeap(2024)).toBe(true);
});

test("daysInMonth(2024, 1) -> 29", () => {
  expect(daysInMonth(2024, 1)).toBe(29);
});

test("daysInMonth(2023, 1) -> 28", () => {
  expect(daysInMonth(2023, 1)).toBe(28);
});

test("daysInMonth(2024, 0) -> 31", () => {
  expect(daysInMonth(2024, 0)).toBe(31);
});
