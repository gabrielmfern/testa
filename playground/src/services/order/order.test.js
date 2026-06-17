import { subtotal, withShipping, freeShipping } from "./order.js";

test("subtotal([{ price: 10, qty: 2 }, { price: 5, qty: 1 }]) -> 25", () => {
  expect(subtotal([{ price: 10, qty: 2 }, { price: 5, qty: 1 }])).toBe(25);
});

test("subtotal([]) -> 0", () => {
  expect(subtotal([])).toBe(0);
});

test("withShipping(25, 5) -> 30", () => {
  expect(withShipping(25, 5)).toBe(30);
});

test("withShipping(100, 0) -> 100", () => {
  expect(withShipping(100, 0)).toBe(100);
});

test("freeShipping(100, 50) -> true", () => {
  expect(freeShipping(100, 50)).toBe(true);
});

test("freeShipping(30, 50) -> false", () => {
  expect(freeShipping(30, 50)).toBe(false);
});

test("freeShipping(50, 50) -> true", () => {
  expect(freeShipping(50, 50)).toBe(true);
});
