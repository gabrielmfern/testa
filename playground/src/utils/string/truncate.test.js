import { truncate, ellipsis, startsWith } from "./truncate.js";

test("truncate(\"hello\", 3) -> \"hel\"", () => {
  expect(truncate("hello", 3)).toBe("hel");
});

test("truncate(\"hi\", 5) -> \"hi\"", () => {
  expect(truncate("hi", 5)).toBe("hi");
});

test("ellipsis(\"hello world\", 5) -> \"hello...\"", () => {
  expect(ellipsis("hello world", 5)).toBe("hello...");
});

test("ellipsis(\"hi\", 5) -> \"hi\"", () => {
  expect(ellipsis("hi", 5)).toBe("hi");
});

test("ellipsis(\"abcde\", 5) -> \"abcde\"", () => {
  expect(ellipsis("abcde", 5)).toBe("abcde");
});

test("startsWith(\"hello\", \"he\") -> true", () => {
  expect(startsWith("hello", "he")).toBe(true);
});

test("startsWith(\"hello\", \"wo\") -> false", () => {
  expect(startsWith("hello", "wo")).toBe(false);
});

test("startsWith(\"hello\", \"\") -> true", () => {
  expect(startsWith("hello", "")).toBe(true);
});
