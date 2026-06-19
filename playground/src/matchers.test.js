// Exercises every core matcher and the .not modifier. Mirrors how a vitest user
// would write them; each block should pass.

test("equality", () => {
  expect(1).toBe(1);
  expect("a").toBe("a");
  expect(NaN).toBe(NaN);
  expect(1).not.toBe(2);
  expect({ a: 1, b: [2, 3] }).toEqual({ a: 1, b: [2, 3] });
  expect({ a: 1, b: undefined }).toEqual({ a: 1 });
  expect({ a: 1, b: undefined }).not.toStrictEqual({ a: 1 });
  expect({ a: 1 }).toStrictEqual({ a: 1 });
  expect([1, 2, 3]).toEqual([1, 2, 3]);
  expect([1, 2]).not.toEqual([1, 2, 3]);
  expect(new Date(10)).toEqual(new Date(10));
  expect(/ab+/gi).toEqual(/ab+/gi);
  expect(/ab+/g).not.toEqual(/ab+/i);
  expect(new Map([["a", 1]])).toEqual(new Map([["a", 1]]));
  expect(new Set([1, 2, 3])).toEqual(new Set([3, 2, 1]));
});

test("toMatchObject", () => {
  expect({ a: 1, b: 2, c: 3 }).toMatchObject({ a: 1, c: 3 });
  expect({ nested: { x: 1, y: 2 } }).toMatchObject({ nested: { x: 1 } });
  expect({ a: 1 }).not.toMatchObject({ a: 2 });
  expect([{ a: 1 }, { b: 2 }]).toMatchObject([{ a: 1 }, { b: 2 }]);
});

test("truthiness and nullish", () => {
  expect(1).toBeTruthy();
  expect(0).toBeFalsy();
  expect("").toBeFalsy();
  expect(null).toBeNull();
  expect(undefined).toBeUndefined();
  expect(1).toBeDefined();
  expect(null).not.toBeUndefined();
  expect(NaN).toBeNaN();
  expect(1).not.toBeNaN();
});

test("numbers", () => {
  expect(5).toBeGreaterThan(4);
  expect(5).toBeGreaterThanOrEqual(5);
  expect(4).toBeLessThan(5);
  expect(5).toBeLessThanOrEqual(5);
  expect(0.1 + 0.2).toBeCloseTo(0.3);
  expect(0.1 + 0.2).toBeCloseTo(0.3, 5);
  expect(3.14159).toBeCloseTo(3.14, 2);
  expect(5).not.toBeGreaterThan(10);
});

test("containment, shape, pattern", () => {
  expect([1, 2, 3]).toContain(2);
  expect("hello world").toContain("world");
  expect(new Set([1, 2])).toContain(1);
  expect([1, 2]).not.toContain(3);
  expect([{ a: 1 }, { b: 2 }]).toContainEqual({ a: 1 });
  expect([{ a: 1 }]).not.toContainEqual({ a: 2 });
  expect([1, 2, 3]).toHaveLength(3);
  expect("abcd").toHaveLength(4);
  expect({ a: { b: { c: 42 } } }).toHaveProperty("a.b.c");
  expect({ a: { b: { c: 42 } } }).toHaveProperty("a.b.c", 42);
  expect({ a: { b: 1 } }).toHaveProperty(["a", "b"], 1);
  expect({ a: 1 }).not.toHaveProperty("b");
  expect("2024-01-01").toMatch("2024");
  expect("hello").toMatch(/^h.*o$/);
  expect("hello").not.toMatch(/^x/);
});

test("type", () => {
  expect("s").toBeTypeOf("string");
  expect(1).toBeTypeOf("number");
  expect(true).toBeTypeOf("boolean");
  expect(() => {}).toBeTypeOf("function");
  expect(1).not.toBeTypeOf("string");
  expect([]).toBeInstanceOf(Array);
  expect(new Error("x")).toBeInstanceOf(Error);
  expect(new Map()).toBeInstanceOf(Map);
  expect({}).not.toBeInstanceOf(Array);
});

test("misc value", () => {
  expect(2).toBeOneOf([1, 2, 3]);
  expect({ a: 1 }).toBeOneOf([{ a: 1 }, { a: 2 }]);
  expect(5).not.toBeOneOf([1, 2, 3]);
  expect(4).toSatisfy((n) => n % 2 === 0);
  expect(3).not.toSatisfy((n) => n % 2 === 0);
});

test("errors", () => {
  expect(() => {
    throw new Error("boom");
  }).toThrow();
  expect(() => {
    throw new Error("boom happened");
  }).toThrow("boom");
  expect(() => {
    throw new Error("boom happened");
  }).toThrow(/bo+m/);
  expect(() => {
    throw new TypeError("bad type");
  }).toThrow(TypeError);
  expect(() => {
    throw new Error("exact");
  }).toThrowError(new Error("exact"));
  expect(() => {}).not.toThrow();
});

// These should each report as a failure (not ok), proving the matchers actually
// throw on mismatch rather than silently passing.
test.fails("toBe mismatch fails", () => {
  expect(1).toBe(2);
});
test.fails("toEqual mismatch fails", () => {
  expect({ a: 1 }).toEqual({ a: 2 });
});
test.fails("negated pass fails", () => {
  expect(1).not.toBe(1);
});
test.fails("toThrow on non-throwing fails", () => {
  expect(() => 1).toThrow();
});
