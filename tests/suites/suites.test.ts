describe("suites", () => {
  test("simple test works", () => {
    expect(4 + 1).toBe(5);
  });

  describe.skip("this is a describe that should be skipped", () => {
    test("this fails but it should never run", () => {
      expect(4 + 1).toBe(6);
    });
  });
});
