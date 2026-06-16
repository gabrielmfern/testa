import { isExpired, roleAllows } from "./token.js";

test("isExpired(100, 200) -> true", () => {
  expect(isExpired(100, 200)).toBe(true);
});

test("isExpired(200, 100) -> false", () => {
  expect(isExpired(200, 100)).toBe(false);
});

test("roleAllows(\"admin\", \"user\") -> true", () => {
  expect(roleAllows("admin", "user")).toBe(true);
});

test("roleAllows(\"guest\", \"admin\") -> false", () => {
  expect(roleAllows("guest", "admin")).toBe(false);
});
