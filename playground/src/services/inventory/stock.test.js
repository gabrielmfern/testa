import { inStock, reorder, available } from "./stock.js";

test("inStock(5) -> true", () => {
  expect(inStock(5)).toBe(true);
});

test("inStock(0) -> false", () => {
  expect(inStock(0)).toBe(false);
});

test("reorder(2, 5) -> true", () => {
  expect(reorder(2, 5)).toBe(true);
});

test("reorder(10, 5) -> false", () => {
  expect(reorder(10, 5)).toBe(false);
});

test("reorder(5, 5) -> true", () => {
  expect(reorder(5, 5)).toBe(true);
});

test("available(100, 30) -> 70", () => {
  expect(available(100, 30)).toBe(70);
});

test("available(10, 10) -> 0", () => {
  expect(available(10, 10)).toBe(0);
});
