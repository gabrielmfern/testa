import { withTax, tier } from "./tax.js";

test("withTax(100, 0.1) -> 110", () => {
  expect(withTax(100, 0.1)).toBe(110);
});

test("withTax(200, 0.25) -> 250", () => {
  expect(withTax(200, 0.25)).toBe(250);
});

test("tier(1500) -> \"gold\"", () => {
  expect(tier(1500)).toBe("gold");
});

test("tier(150) -> \"silver\"", () => {
  expect(tier(150)).toBe("silver");
});

test("tier(10) -> \"bronze\"", () => {
  expect(tier(10)).toBe("bronze");
});
