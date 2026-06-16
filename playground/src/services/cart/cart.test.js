import { total, count, applyDiscount } from "./cart.js";

test("total([{ price: 10, qty: 2 }, { price: 5, qty: 1 }]) -> 25", () => {
  expect(total([{ price: 10, qty: 2 }, { price: 5, qty: 1 }])).toBe(25);
});

test("total([]) -> 0", () => {
  expect(total([])).toBe(0);
});

test("count([{ qty: 2 }, { qty: 3 }]) -> 5", () => {
  expect(count([{ qty: 2 }, { qty: 3 }])).toBe(5);
});

test("applyDiscount(100, 20) -> 80", () => {
  expect(applyDiscount(100, 20)).toBe(80);
});

test("applyDiscount(100, 0) -> 100", () => {
  expect(applyDiscount(100, 0)).toBe(100);
});
