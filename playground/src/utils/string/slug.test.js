import { slug, dedash, wordCount } from "./slug.js";

test("slug(\"Hello World\") -> \"hello-world\"", () => {
  expect(slug("Hello World")).toBe("hello-world");
});

test("slug(\"  Foo  Bar  \") -> \"foo-bar\"", () => {
  expect(slug("  Foo  Bar  ")).toBe("foo-bar");
});

test("slug(\"single\") -> \"single\"", () => {
  expect(slug("single")).toBe("single");
});

test("dedash(\"hello-world\") -> \"hello world\"", () => {
  expect(dedash("hello-world")).toBe("hello world");
});

test("dedash(\"a--b\") -> \"a b\"", () => {
  expect(dedash("a--b")).toBe("a b");
});

test("wordCount(\"one two three\") -> 3", () => {
  expect(wordCount("one two three")).toBe(3);
});

test("wordCount(\"\") -> 0", () => {
  expect(wordCount("")).toBe(0);
});

test("wordCount(\"  spaced  out  \") -> 2", () => {
  expect(wordCount("  spaced  out  ")).toBe(2);
});
