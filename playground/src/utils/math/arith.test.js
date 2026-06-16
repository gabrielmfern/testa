import { add, sub, mul, div } from "./arith.js";

test("add(2, 3) -> 5", () => {
  expect(add(2, 3)).toBe(5);
});

test("add(-1, 1) -> 0", () => {
  expect(add(-1, 1)).toBe(0);
});

test("sub(5, 3) -> 2", () => {
  expect(sub(5, 3)).toBe(2);
});

test("mul(4, 3) -> 12", () => {
  expect(mul(4, 3)).toBe(12);
});

test("mul(0, 9) -> 0", () => {
  expect(mul(0, 9)).toBe(0);
});

test("div(6, 2) -> 3", () => {
  expect(div(6, 2)).toBe(3);
});

test("div(1, 0) -> 0", () => {
  expect(div(1, 0)).toBe(0);
});
