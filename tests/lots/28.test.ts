test("28", () => {
  const sum = (a: number, b: number): number => a + b;

  expect(sum(1, 1)).toBe(2);
  expect('foo' + 'bar').toBe('foobar');
  expect(1.5).toBe(1.5);
});
