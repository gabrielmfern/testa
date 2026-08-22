test("doesn't expect 1+1 to be 3", () => {
  expect(1 + 1).not.toBe(3);
});

test.failing("doesn't expect 1+2 to be 3", () => {
  expect(1 + 2).not.toBe(3);
});
