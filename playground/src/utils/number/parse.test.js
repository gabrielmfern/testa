import { toInt, toFloat, isNumeric } from "./parse.js";

test('toInt("42") -> 42', () => {
  expect(toInt("42")).toBe(42);
});

test('toInt("10px") -> 10', () => {
  expect(toInt("10px")).toBe(10);
});

test('toFloat("3.14") -> 3.14', () => {
  expect(toFloat("3.14")).toBe(3.14);
});

test('toFloat("1.5kg") -> 1.5', () => {
  expect(toFloat("1.5kg")).toBe(1.5);
});

test('isNumeric("123") -> true', () => {
  expect(isNumeric("123")).toBe(true);
});

test('isNumeric("12.5") -> true', () => {
  expect(isNumeric("12.5")).toBe(true);
});

test('isNumeric("abc") -> false', () => {
  expect(isNumeric("abc")).toBe(false);
});

test('isNumeric("") -> false', () => {
  expect(isNumeric("")).toBe(false);
});
