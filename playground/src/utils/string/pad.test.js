import { padLeft, truncate, repeat } from "./pad.js";

test("padLeft(\"5\", 3, \"0\") -> \"005\"", () => {
  expect(padLeft("5", 3, "0")).toBe("005");
});

test("padLeft(\"ab\", 4) -> \"  ab\"", () => {
  expect(padLeft("ab", 4)).toBe("  ab");
});

test("truncate(\"hello\", 10) -> \"hello\"", () => {
  expect(truncate("hello", 10)).toBe("hello");
});

test("truncate(\"hello world\", 5) -> \"hell…\"", () => {
  expect(truncate("hello world", 5)).toBe("hell…");
});

test("repeat(\"ab\", 3) -> \"ababab\"", () => {
  expect(repeat("ab", 3)).toBe("ababab");
});

test("repeat(\"x\", 0) -> \"\"", () => {
  expect(repeat("x", 0)).toBe("");
});
