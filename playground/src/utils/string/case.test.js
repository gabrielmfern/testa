import { capitalize, kebab, snake } from "./case.js";

test("capitalize(\"hello\") -> \"Hello\"", () => {
  expect(capitalize("hello")).toBe("Hello");
});

test("capitalize(\"\") -> \"\"", () => {
  expect(capitalize("")).toBe("");
});

test("capitalize(\"a\") -> \"A\"", () => {
  expect(capitalize("a")).toBe("A");
});

test("kebab(\"helloWorld\") -> \"hello-world\"", () => {
  expect(kebab("helloWorld")).toBe("hello-world");
});

test("kebab(\"Foo Bar\") -> \"foo-bar\"", () => {
  expect(kebab("Foo Bar")).toBe("foo-bar");
});

test("snake(\"helloWorld\") -> \"hello_world\"", () => {
  expect(snake("helloWorld")).toBe("hello_world");
});

test("snake(\"Foo Bar\") -> \"foo_bar\"", () => {
  expect(snake("Foo Bar")).toBe("foo_bar");
});
