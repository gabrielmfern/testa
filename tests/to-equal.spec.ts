describe("toEqual", () => {
  describe("primitives", () => {
    test("same value", () => {
      expect(1).toEqual(1);
      expect("a").toEqual("a");
      expect(true).toEqual(true);
      expect(null).toEqual(null);
      expect(undefined).toEqual(undefined);
    });

    test("different value", () => {
      expect(1).not.toEqual(2);
      expect("a").not.toEqual("b");
      expect(true).not.toEqual(false);
    });

    test("NaN equals NaN", () => {
      expect(NaN).toEqual(NaN);
    });

    test("+0 does not equal -0", () => {
      expect(0).not.toEqual(-0);
    });

    test("null does not equal undefined", () => {
      expect(null).not.toEqual(undefined);
    });

    test("different types", () => {
      expect(1).not.toEqual("1");
      expect(0).not.toEqual(false);
    });
  });

  describe("boxed primitives", () => {
    test("same boxed value", () => {
      expect(new Number(1)).toEqual(new Number(1));
      expect(new String("a")).toEqual(new String("a"));
      expect(new Boolean(true)).toEqual(new Boolean(true));
    });

    test("different boxed value", () => {
      expect(new Number(1)).not.toEqual(new Number(2));
      expect(new String("a")).not.toEqual(new String("b"));
      expect(new Boolean(true)).not.toEqual(new Boolean(false));
    });

    test("boxed does not equal primitive", () => {
      expect(new Number(1)).not.toEqual(1);
      expect(1).not.toEqual(new Number(1));
      expect(new String("a")).not.toEqual("a");
      expect(new Boolean(true)).not.toEqual(true);
    });
  });

  describe("dates", () => {
    test("same time", () => {
      expect(new Date(0)).toEqual(new Date(0));
    });

    test("different time", () => {
      expect(new Date(0)).not.toEqual(new Date(1));
    });

    test("two invalid dates are equal", () => {
      expect(new Date("nope")).toEqual(new Date("nah"));
    });

    test("invalid date does not equal a valid one", () => {
      expect(new Date("nope")).not.toEqual(new Date(0));
    });
  });

  describe("regexps", () => {
    test("same source and flags", () => {
      expect(/a+/gi).toEqual(/a+/gi);
    });

    test("different source", () => {
      expect(/a+/).not.toEqual(/b+/);
    });

    test("different flags", () => {
      expect(/a+/g).not.toEqual(/a+/i);
    });
  });

  describe("urls", () => {
    test("same href", () => {
      expect(new URL("https://example.com/a?b=1")).toEqual(new URL("https://example.com/a?b=1"));
    });

    test("different href", () => {
      expect(new URL("https://example.com/a")).not.toEqual(new URL("https://example.com/b"));
    });
  });

  describe("functions", () => {
    test("same function object", () => {
      const fn = () => 1;
      expect(fn).toEqual(fn);
    });

    test("different function objects with the same name and body", () => {
      function named() { return 1; }
      const other = function named() { return 1; };
      expect(named).not.toEqual(other);
      expect(() => {}).not.toEqual(() => {});
    });
  });

  describe("kind mismatch", () => {
    test("array does not equal object", () => {
      expect([]).not.toEqual({});
    });

    test("date does not equal number", () => {
      expect(new Date(0)).not.toEqual(0);
    });

    test("regexp does not equal string", () => {
      expect(/a/).not.toEqual("/a/");
    });
  });

  describe("temporal", () => {
    const hasTemporal = typeof (globalThis as any).Temporal !== "undefined";
    const Temporal = (globalThis as any).Temporal;

    test.skipIf(!hasTemporal)("instant", () => {
      expect(Temporal.Instant.from("2024-01-01T00:00:00Z")).toEqual(Temporal.Instant.from("2024-01-01T00:00:00Z"));
      expect(Temporal.Instant.from("2024-01-01T00:00:00Z")).not.toEqual(Temporal.Instant.from("2024-01-02T00:00:00Z"));
    });

    test.skipIf(!hasTemporal)("zoned date time", () => {
      expect(Temporal.ZonedDateTime.from("2024-01-01T00:00:00[UTC]")).toEqual(Temporal.ZonedDateTime.from("2024-01-01T00:00:00[UTC]"));
      expect(Temporal.ZonedDateTime.from("2024-01-01T00:00:00[UTC]")).not.toEqual(Temporal.ZonedDateTime.from("2024-01-01T00:00:00[America/Sao_Paulo]"));
    });

    test.skipIf(!hasTemporal)("plain date time", () => {
      expect(Temporal.PlainDateTime.from("2024-01-01T10:00")).toEqual(Temporal.PlainDateTime.from("2024-01-01T10:00"));
      expect(Temporal.PlainDateTime.from("2024-01-01T10:00")).not.toEqual(Temporal.PlainDateTime.from("2024-01-01T11:00"));
    });

    test.skipIf(!hasTemporal)("plain date", () => {
      expect(Temporal.PlainDate.from("2024-01-01")).toEqual(Temporal.PlainDate.from("2024-01-01"));
      expect(Temporal.PlainDate.from("2024-01-01")).not.toEqual(Temporal.PlainDate.from("2024-01-02"));
    });

    test.skipIf(!hasTemporal)("plain time", () => {
      expect(Temporal.PlainTime.from("10:00")).toEqual(Temporal.PlainTime.from("10:00"));
      expect(Temporal.PlainTime.from("10:00")).not.toEqual(Temporal.PlainTime.from("11:00"));
    });

    test.skipIf(!hasTemporal)("plain year month", () => {
      expect(Temporal.PlainYearMonth.from("2024-01")).toEqual(Temporal.PlainYearMonth.from("2024-01"));
      expect(Temporal.PlainYearMonth.from("2024-01")).not.toEqual(Temporal.PlainYearMonth.from("2024-02"));
    });

    test.skipIf(!hasTemporal)("plain month day", () => {
      expect(Temporal.PlainMonthDay.from("01-01")).toEqual(Temporal.PlainMonthDay.from("01-01"));
      expect(Temporal.PlainMonthDay.from("01-01")).not.toEqual(Temporal.PlainMonthDay.from("01-02"));
    });

    test.skipIf(!hasTemporal)("duration compares by string form", () => {
      expect(Temporal.Duration.from("PT1H")).toEqual(Temporal.Duration.from({ hours: 1 }));
      expect(Temporal.Duration.from({ hours: 1 })).not.toEqual(Temporal.Duration.from({ minutes: 60 }));
    });
  });

  describe("arrays", () => {
    test("same elements", () => {
      expect([1, "a", null]).toEqual([1, "a", null]);
      expect([[1, [2]], { a: [3] }]).toEqual([[1, [2]], { a: [3] }]);
    });

    test("different elements", () => {
      expect([1, 2]).not.toEqual([1, 3]);
      expect([[1]]).not.toEqual([[2]]);
    });

    test("different length", () => {
      expect([1, 2]).not.toEqual([1]);
      expect([1, undefined]).not.toEqual([1]);
    });

    test("holes and undefined are the same", () => {
      expect([undefined]).toEqual([,]);
    });

    test("empty", () => {
      expect([]).toEqual([]);
    });
  });

  describe("objects", () => {
    test("same keys and values", () => {
      expect({ a: 1, b: { c: [1, 2] } }).toEqual({ a: 1, b: { c: [1, 2] } });
    });

    test("key order does not matter", () => {
      expect({ a: 1, b: 2 }).toEqual({ b: 2, a: 1 });
    });

    test("different value", () => {
      expect({ a: 1 }).not.toEqual({ a: 2 });
      expect({ a: { b: 1 } }).not.toEqual({ a: { b: 2 } });
    });

    test("missing and extra keys", () => {
      expect({ a: 1 }).not.toEqual({ a: 1, b: 2 });
      expect({ a: 1, b: 2 }).not.toEqual({ a: 1 });
    });

    test("undefined values are ignored", () => {
      expect({ a: 1, b: undefined }).toEqual({ a: 1 });
      expect({ a: 1 }).toEqual({ a: 1, b: undefined });
    });

    test("undefined does not match a defined value", () => {
      expect({ a: undefined }).not.toEqual({ a: null });
      expect({ a: null }).not.toEqual({ a: undefined });
    });

    test("prototype is ignored", () => {
      class Point {
        x: number;
        constructor(x: number) {
          this.x = x;
        }
      }
      expect(new Point(1)).toEqual({ x: 1 });
    });

    test("symbol keys", () => {
      const s = Symbol("s");
      expect({ [s]: 1 }).toEqual({ [s]: 1 });
      expect({ [s]: 1 }).not.toEqual({ [s]: 2 });
    });

    test("empty", () => {
      expect({}).toEqual({});
    });
  });

  describe("errors", () => {
    test("same name and message", () => {
      expect(new Error("boom")).toEqual(new Error("boom"));
    });

    test("different message", () => {
      expect(new Error("boom")).not.toEqual(new Error("bang"));
    });

    test("different class", () => {
      expect(new TypeError("boom")).not.toEqual(new RangeError("boom"));
    });

    test("cause is compared when expected has one", () => {
      expect(new Error("boom", { cause: 1 })).toEqual(new Error("boom", { cause: 1 }));
      expect(new Error("boom", { cause: 1 })).not.toEqual(new Error("boom", { cause: 2 }));
    });

    test("enumerable own properties are compared", () => {
      expect(Object.assign(new Error("boom"), { code: 1 })).not.toEqual(Object.assign(new Error("boom"), { code: 2 }));
    });
  });

  describe("cycles", () => {
    test("matching cycles are equal", () => {
      const a: any = { x: 1 };
      a.self = a;
      const b: any = { x: 1 };
      b.self = b;
      expect(a).toEqual(b);
    });

    test("a cycle does not equal a non-cycle", () => {
      const a: any = { x: 1 };
      a.self = a;
      const b: any = { x: 1, self: { x: 1, self: {} } };
      expect(a).not.toEqual(b);
    });
  });
});
