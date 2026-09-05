describe("suites", () => {
  test("simple test works", () => {
    expect(4 + 1).toBe(5);
  });

  describe.skip("this is a describe that should be skipped", () => {
    test("this fails but it should never run", () => {
      expect(4 + 1).toBe(6);
    });
  });

  describe.todo("this is a suite that has not yet been implemented");

  describe.runIf(true)("a suite that runs", () => {
    test("its test also runs", () => {
      expect(1 + 1).toBe(2);
    });
  });

  describe.runIf(false)("a suite that never runs, so it's fine", () => {
    test("this would fail, but it never runs", () => {
      expect(1 + 1).toBe(3);
    });
  });

  describe.skipIf(false)("a suite that isn't skipped", () => {
    test("its test also runs", () => {
      expect(1 + 1).toBe(2);
    });
  });

  describe.skipIf(true)("a suite that's skipped, so it's fine", () => {
    test("this would fail, but it's skipped", () => {
      expect(1 + 1).toBe(3);
    });
  });
});
